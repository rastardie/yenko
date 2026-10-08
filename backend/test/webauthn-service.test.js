import assert from 'node:assert/strict';
import test from 'node:test';

import { generateRegistrationOptions, generateAuthenticationOptions } from '@simplewebauthn/server';

import { WebAuthnService } from '../src/application/webauthn-service.js';

/**
 * Unit tests for WebAuthnService's own logic (challenge issuance/consumption,
 * routing to @simplewebauthn/server, session issuance on success) using an
 * in-memory double for the repository, since this is business logic that
 * does not need a real database to verify. SQL correctness of
 * PostgresWebAuthnRepository itself is not covered here — it would need the
 * Postgres-backed integration suite (see test/integration/), which is gated
 * on TEST_DATABASE_URL elsewhere in this repo and not available in this
 * environment.
 */

class InMemoryWebAuthnRepository {
  #credentials = new Map();
  #challenges = [];

  async listCredentialsForUser(userId) {
    return [...this.#credentials.values()].filter((c) => c.user_id === userId);
  }

  async findCredentialById(id) {
    return this.#credentials.get(id) ?? null;
  }

  async createCredential({ id, userId, publicKey, counter, deviceType, backedUp, transports, deviceLabel }) {
    this.#credentials.set(id, {
      id, user_id: userId, public_key: publicKey, counter, device_type: deviceType,
      backed_up: backedUp, transports, device_label: deviceLabel ?? null,
    });
  }

  async updateCounter(id, counter) {
    const credential = this.#credentials.get(id);
    if (credential) credential.counter = counter;
  }

  async deleteCredential({ credentialId, userId }) {
    const credential = this.#credentials.get(credentialId);
    if (!credential || credential.user_id !== userId) return false;
    this.#credentials.delete(credentialId);
    return true;
  }

  async createChallenge({ userId = null, challenge, purpose, expiresAt }) {
    this.#challenges.push({ userId, challenge, purpose, expiresAt, consumed: false });
  }

  async consumeChallenge({ userId = null, purpose, challenge }) {
    const match = this.#challenges.find(
      (c) => !c.consumed && c.purpose === purpose && c.challenge === challenge &&
        c.expiresAt > new Date() && (userId == null || c.userId === userId),
    );
    if (!match) return false;
    match.consumed = true;
    return true;
  }
}

const fakeUser = { id: 'user-1', username: 'kofi', display_name: 'Kofi Mensah', status: 'active', auth_version: 0 };

function buildService({ userExists = true } = {}) {
  const webauthnRepository = new InMemoryWebAuthnRepository();
  const userRepository = {
    findById: async (id) => (userExists && id === fakeUser.id ? fakeUser : null),
  };
  const authService = {
    issueSessionForUserId: async (userId) => ({ accessToken: `token-for-${userId}` }),
  };
  const service = new WebAuthnService({
    webauthnRepository,
    userRepository,
    authService,
    rpName: 'YɛnKɔ Test',
    rpID: 'localhost',
    origin: 'http://localhost:5173',
  });
  return { service, webauthnRepository };
}

test('registrationOptions issues a challenge tied to the signed-in user', async () => {
  const { service, webauthnRepository } = buildService();
  const options = await service.registrationOptions({ userId: fakeUser.id });
  assert.equal(options.rp.id, 'localhost');
  assert.equal(options.user.name, 'kofi');
  assert.ok(options.challenge);
  const consumed = await webauthnRepository.consumeChallenge({
    userId: fakeUser.id, purpose: 'register', challenge: options.challenge,
  });
  assert.equal(consumed, true, 'the generated challenge should be consumable exactly once');
  const consumedAgain = await webauthnRepository.consumeChallenge({
    userId: fakeUser.id, purpose: 'register', challenge: options.challenge,
  });
  assert.equal(consumedAgain, false, 'a challenge cannot be consumed twice');
});

test('registrationOptions rejects an unknown user', async () => {
  const { service } = buildService({ userExists: false });
  await assert.rejects(service.registrationOptions({ userId: 'nope' }), /Account not found/);
});

test('registrationVerify rejects a malformed response', async () => {
  const { service } = buildService();
  await assert.rejects(
    service.registrationVerify({ userId: fakeUser.id, response: null }),
    /registration response is required/,
  );
});

test('registrationVerify rejects a response whose challenge was never issued', async () => {
  const { service } = buildService();
  const fakeClientData = Buffer.from(
    JSON.stringify({ challenge: 'never-issued', type: 'webauthn.create', origin: 'http://localhost:5173' }),
  ).toString('base64url');
  await assert.rejects(
    service.registrationVerify({
      userId: fakeUser.id,
      response: { response: { clientDataJSON: fakeClientData } },
    }),
    /expired or was already used/,
  );
});

test('authenticationVerify rejects an unknown credential id', async () => {
  const { service } = buildService();
  await assert.rejects(
    service.authenticationVerify({ response: { id: 'unknown-credential-id', response: {} } }),
    /not registered/,
  );
});

test('authenticationVerify rejects a malformed response', async () => {
  const { service } = buildService();
  await assert.rejects(
    service.authenticationVerify({ response: {} }),
    /authentication response is required/,
  );
});

test('status lists only the signed-in user\'s own credentials', async () => {
  const { service, webauthnRepository } = buildService();
  await webauthnRepository.createCredential({
    id: 'cred-1', userId: fakeUser.id, publicKey: Buffer.from('x'), counter: 0,
    deviceType: 'singleDevice', backedUp: false, transports: ['internal'], deviceLabel: 'My phone',
  });
  await webauthnRepository.createCredential({
    id: 'cred-2', userId: 'someone-else', publicKey: Buffer.from('y'), counter: 0,
    deviceType: 'singleDevice', backedUp: false, transports: [], deviceLabel: null,
  });
  const result = await service.status({ userId: fakeUser.id });
  assert.equal(result.credentials.length, 1);
  assert.equal(result.credentials[0].id, 'cred-1');
  assert.equal(result.credentials[0].deviceLabel, 'My phone');
});

test('deleteCredential only deletes the signed-in user\'s own credential', async () => {
  const { service, webauthnRepository } = buildService();
  await webauthnRepository.createCredential({
    id: 'cred-1', userId: 'someone-else', publicKey: Buffer.from('x'), counter: 0,
    deviceType: 'singleDevice', backedUp: false, transports: [], deviceLabel: null,
  });
  await assert.rejects(
    service.deleteCredential({ userId: fakeUser.id, credentialId: 'cred-1' }),
    /Passkey not found/,
  );
  await service.deleteCredential.call(service, { userId: 'someone-else', credentialId: 'cred-1' });
  assert.equal(await webauthnRepository.findCredentialById('cred-1'), null);
});

test('authenticationOptions produces options scoped to the configured rpID', async () => {
  const { service } = buildService();
  const options = await service.authenticationOptions();
  assert.equal(options.rpId, 'localhost');
  assert.ok(options.challenge);
});

test('sanity: the underlying library functions used by the service are callable directly', async () => {
  const regOptions = await generateRegistrationOptions({
    rpName: 'YɛnKɔ Test', rpID: 'localhost', userName: 'kofi',
  });
  assert.ok(regOptions.challenge);
  const authOptions = await generateAuthenticationOptions({ rpID: 'localhost' });
  assert.ok(authOptions.challenge);
});
