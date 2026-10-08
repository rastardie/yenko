import { randomUUID } from 'node:crypto';

import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';

import { badRequest, conflict, notFound, unauthorized } from '../domain/errors.js';

const challengeTtlMinutes = 5;

/**
 * WebAuthn (passkey) registration and authentication for the web/PWA
 * client. Unlike native biometric unlock — a purely client-side device-lock
 * gating a cached username/password, which the server never sees — a PWA
 * has no OS-level secure storage, so the browser's own WebAuthn API is used
 * instead and every ceremony is verified here with @simplewebauthn/server.
 * See migration 012 and HANDOVER.md.
 */
export class WebAuthnService {
  constructor({ webauthnRepository, userRepository, authService, rpName, rpID, origin }) {
    this.webauthn = webauthnRepository;
    this.users = userRepository;
    this.authService = authService;
    this.rpName = rpName;
    this.rpID = rpID;
    this.origin = origin;
  }

  async registrationOptions({ userId }) {
    const user = await this.users.findById(userId);
    if (!user) throw unauthorized('Account not found.');
    const existing = await this.webauthn.listCredentialsForUser(userId);
    const options = await generateRegistrationOptions({
      rpName: this.rpName,
      rpID: this.rpID,
      userName: user.username ?? user.email ?? user.phone ?? user.display_name,
      userDisplayName: user.display_name,
      attestationType: 'none',
      excludeCredentials: existing.map((credential) => ({
        id: credential.id,
        transports: credential.transports,
      })),
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
      },
    });
    await this.webauthn.createChallenge({
      userId,
      challenge: options.challenge,
      purpose: 'register',
      expiresAt: new Date(Date.now() + challengeTtlMinutes * 60_000),
    });
    return options;
  }

  async registrationVerify({ userId, response, deviceLabel }) {
    if (!response || typeof response !== 'object') {
      throw badRequest('A WebAuthn registration response is required.');
    }
    let clientDataJSON;
    try {
      clientDataJSON = JSON.parse(
        Buffer.from(response.response?.clientDataJSON ?? '', 'base64url').toString('utf8'),
      );
    } catch {
      throw badRequest('The registration response is malformed.');
    }
    const expectedChallenge = clientDataJSON.challenge;
    const consumed = await this.webauthn.consumeChallenge({
      userId,
      purpose: 'register',
      challenge: expectedChallenge,
    });
    if (!consumed) throw conflict('This registration ceremony has expired or was already used.');

    let verification;
    try {
      verification = await verifyRegistrationResponse({
        response,
        expectedChallenge,
        expectedOrigin: this.origin,
        expectedRPID: this.rpID,
      });
    } catch (error) {
      throw badRequest(`WebAuthn registration could not be verified: ${error.message}`);
    }
    if (!verification.verified) throw badRequest('WebAuthn registration could not be verified.');

    const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;
    await this.webauthn.createCredential({
      id: credential.id,
      userId,
      publicKey: Buffer.from(credential.publicKey),
      counter: credential.counter,
      deviceType: credentialDeviceType,
      backedUp: credentialBackedUp,
      transports: response.response?.transports ?? [],
      deviceLabel: typeof deviceLabel === 'string' && deviceLabel.trim() ? deviceLabel.trim().slice(0, 120) : null,
    });
    return { id: credential.id };
  }

  async authenticationOptions() {
    const options = await generateAuthenticationOptions({
      rpID: this.rpID,
      userVerification: 'preferred',
    });
    await this.webauthn.createChallenge({
      challenge: options.challenge,
      purpose: 'authenticate',
      expiresAt: new Date(Date.now() + challengeTtlMinutes * 60_000),
    });
    return options;
  }

  async authenticationVerify({ response }) {
    if (!response || typeof response !== 'object' || typeof response.id !== 'string') {
      throw badRequest('A WebAuthn authentication response is required.');
    }
    const stored = await this.webauthn.findCredentialById(response.id);
    if (!stored) throw unauthorized('This passkey is not registered.');

    let clientDataJSON;
    try {
      clientDataJSON = JSON.parse(
        Buffer.from(response.response?.clientDataJSON ?? '', 'base64url').toString('utf8'),
      );
    } catch {
      throw badRequest('The authentication response is malformed.');
    }
    const expectedChallenge = clientDataJSON.challenge;
    const consumed = await this.webauthn.consumeChallenge({
      purpose: 'authenticate',
      challenge: expectedChallenge,
    });
    if (!consumed) throw conflict('This sign-in ceremony has expired or was already used.');

    let verification;
    try {
      verification = await verifyAuthenticationResponse({
        response,
        expectedChallenge,
        expectedOrigin: this.origin,
        expectedRPID: this.rpID,
        credential: {
          id: stored.id,
          publicKey: stored.public_key,
          counter: Number(stored.counter),
          transports: stored.transports,
        },
      });
    } catch (error) {
      throw badRequest(`WebAuthn sign-in could not be verified: ${error.message}`);
    }
    if (!verification.verified) throw unauthorized('WebAuthn sign-in could not be verified.');

    await this.webauthn.updateCounter(stored.id, verification.authenticationInfo.newCounter);
    return this.authService.issueSessionForUserId(stored.user_id);
  }

  async status({ userId }) {
    const credentials = await this.webauthn.listCredentialsForUser(userId);
    return {
      credentials: credentials.map((credential) => ({
        id: credential.id,
        deviceLabel: credential.device_label,
        createdAt: credential.created_at,
        lastUsedAt: credential.last_used_at,
      })),
    };
  }

  async deleteCredential({ userId, credentialId }) {
    const deleted = await this.webauthn.deleteCredential({ credentialId, userId });
    if (!deleted) throw notFound('Passkey not found.');
  }
}

export const randomChallengeId = () => randomUUID();
