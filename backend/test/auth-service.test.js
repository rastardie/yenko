import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthService } from '../src/application/auth-service.js';
import { InMemoryUserRepository } from './fixtures/in-memory-user-repository.js';

const buildService = () => {
  const userRepository = new InMemoryUserRepository();
  const authService = new AuthService({ userRepository, jwtSecret: 'test-secret-at-least-this-long' });
  return { authService, userRepository };
};

test('signs up a new passenger and issues a session', async () => {
  const { authService } = buildService();
  const result = await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  assert.equal(result.user.role, 'passenger');
  assert.deepEqual(result.user.roles, ['passenger']);
  assert.equal(typeof result.accessToken, 'string');
});

test('signs up a new driver and grants the driver role alongside passenger', async () => {
  const { authService } = buildService();
  const result = await authService.signup({
    displayName: 'Kwame Mensah', phone: '+233200000003', pin: '6930', role: 'driver',
  });
  assert.equal(result.user.role, 'driver');
  assert.deepEqual([...result.user.roles].sort(), ['driver', 'passenger']);
});

test('stores an optional home area at signup', async () => {
  const { authService, userRepository } = buildService();
  const result = await authService.signup({
    displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930', homeArea: 'East Legon',
  });
  const user = await userRepository.findById(result.user.id);
  assert.equal(user.home_area, 'East Legon');
});

test('rejects signup with a duplicate phone number', async () => {
  const { authService } = buildService();
  await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  await assert.rejects(
    () => authService.signup({ displayName: 'Someone Else', phone: '+233200000002', pin: '1234' }),
    /already exists/,
  );
});

test('logs in by phone with the correct PIN', async () => {
  const { authService } = buildService();
  await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  const result = await authService.login({ identity: '+233200000002', pin: '6930' });
  assert.equal(result.user.phone, '+233200000002');
});

test('logs in by username with the correct PIN', async () => {
  const { authService } = buildService();
  await authService.signup({ displayName: 'Ama Owusu', username: 'ama', pin: '6930' });
  const result = await authService.login({ identity: 'ama', pin: '6930' });
  assert.equal(result.user.username, 'ama');
});

test('logs in with either the password or the quick PIN', async () => {
  const { authService } = buildService();
  await authService.signup({
    displayName: 'Ama Owusu',
    username: 'ama.owusu',
    password: 'Str0ngPassw0rd',
    quickPin: '246800',
  });
  const byPassword = await authService.login({ identity: 'ama.owusu', password: 'Str0ngPassw0rd' });
  const byPin = await authService.login({ identity: 'ama.owusu', password: '246800' });
  assert.equal(byPassword.user.id, byPin.user.id);
  await assert.rejects(
    () => authService.login({ identity: 'ama.owusu', password: '246801' }),
    /Incorrect username or password/,
  );
});

test('an account without a quick PIN cannot be entered with an empty or dummy PIN', async () => {
  const { authService } = buildService();
  await authService.signup({ displayName: 'Kofi', username: 'kofi', password: 'Str0ngPassw0rd' });
  await assert.rejects(
    () => authService.login({ identity: 'kofi', password: '0000' }),
    /Incorrect username or password/,
  );
});

test('rejects login with an incorrect password', async () => {
  const { authService } = buildService();
  await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  await assert.rejects(
    () => authService.login({ identity: '+233200000002', pin: 'wrong' }),
    /Incorrect username or password/,
  );
});

test('rejects login for a nonexistent account with the same message as a wrong password', async () => {
  const { authService } = buildService();
  await assert.rejects(
    () => authService.login({ identity: '+233299999999', pin: '6930' }),
    /Incorrect username or password/,
  );
});

test('verifies an access token and derives the primary role from group membership', async () => {
  const { authService, userRepository } = buildService();
  const signupResult = await authService.signup({ displayName: 'Kwame Mensah', phone: '+233200000001', pin: '6930' });
  await userRepository.addToGroup(signupResult.user.id, 'Drivers');

  const actor = await authService.verifyAccessToken(signupResult.accessToken);
  assert.equal(actor.role, 'driver'); // driver outranks passenger
  assert.deepEqual(new Set(actor.roles), new Set(['passenger', 'driver']));
  assert.equal(actor.subject, signupResult.user.id);
});

test('rejects a token after logout revokes its session', async () => {
  const { authService } = buildService();
  const signupResult = await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  const actorBefore = await authService.verifyAccessToken(signupResult.accessToken);
  await authService.logout(actorBefore.sessionId);
  await assert.rejects(() => authService.verifyAccessToken(signupResult.accessToken), /session has expired/);
});

test('old token is rejected once a PIN reset completes (auth_version bump)', async () => {
  const { authService, userRepository } = buildService();
  const signupResult = await authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '6930' });
  await userRepository.bumpAuthVersion(signupResult.user.id);
  await assert.rejects(() => authService.verifyAccessToken(signupResult.accessToken), /session is no longer valid/);
});

test('does not reveal whether an account exists on pin-reset request', async () => {
  const { authService } = buildService();
  const result = await authService.requestPinReset('+233200000099');
  assert.equal(result.message, 'If an account exists, a reset code has been sent.');
});

test('rejects a weak or missing credential on signup', async () => {
  const { authService } = buildService();
  await assert.rejects(
    () => authService.signup({ displayName: 'Ama Owusu', phone: '+233200000002', pin: '12' }),
    /password must be between 4 and 128 characters/,
  );
});

test('rejects a password shorter than 8 characters on explicit password signup', async () => {
  const { authService } = buildService();
  await assert.rejects(
    () => authService.signup({ displayName: 'Ama Owusu', username: 'ama', password: 'short' }),
    /password must be between 8 and 128 characters/,
  );
});

test('rejects an invalid phone format on signup', async () => {
  const { authService } = buildService();
  await assert.rejects(
    () => authService.signup({ displayName: 'Ama Owusu', phone: 'not-a-phone', pin: '6930' }),
    /phone must be in E\.164 format/,
  );
});

// --- Email signup / verification -------------------------------------------

const validEmailSignup = {
  email: 'Ama.Owusu@Example.com',
  password: 'Str0ngPassw0rd',
  displayName: 'Ama',
  legalSurname: 'Owusu',
  legalGivenNames: 'Ama Serwaa',
};

test('email signup creates an account, links a password identity and issues a session', async () => {
  const { authService, userRepository } = buildService();
  const result = await authService.emailSignup(validEmailSignup);
  assert.equal(typeof result.accessToken, 'string');
  assert.equal(result.emailVerificationRequired, true);
  assert.equal(typeof result.devCode, 'string'); // no mailer in dev → code returned
  const user = await userRepository.findByEmail('ama.owusu@example.com');
  assert.ok(user, 'user stored with normalized email');
  assert.equal(user.email_verified, false);
  assert.equal(user.legal_surname, 'Owusu');
  assert.equal(user.legal_given_names, 'Ama Serwaa');
  assert.equal(user.legal_name_source, 'self_attested');
  const identity = await userRepository.findIdentity('password', 'ama.owusu@example.com');
  assert.equal(identity.user_id, user.id);
});

test('email signup requires a full legal name', async () => {
  const { authService } = buildService();
  await assert.rejects(
    () => authService.emailSignup({ ...validEmailSignup, legalSurname: '' }),
    /full legal name/,
  );
  await assert.rejects(
    () => authService.emailSignup({ ...validEmailSignup, legalGivenNames: '123' }),
    /full legal name/,
  );
});

test('email signup rejects an invalid email and duplicates', async () => {
  const { authService } = buildService();
  await assert.rejects(() => authService.emailSignup({ ...validEmailSignup, email: 'nope' }), /valid email/);
  await authService.emailSignup(validEmailSignup);
  await assert.rejects(() => authService.emailSignup(validEmailSignup), /already exists/);
});

test('email verification confirms with the issued code and marks the email verified', async () => {
  const { authService, userRepository } = buildService();
  const result = await authService.emailSignup(validEmailSignup);
  const user = await userRepository.findByEmail('ama.owusu@example.com');
  await authService.confirmEmailVerification({ userId: user.id, code: result.devCode });
  assert.equal((await userRepository.findById(user.id)).email_verified, true);
});

test('logs in by email with the password', async () => {
  const { authService } = buildService();
  await authService.emailSignup(validEmailSignup);
  const result = await authService.login({ identity: 'ama.owusu@example.com', password: 'Str0ngPassw0rd' });
  assert.equal(result.user.email, 'ama.owusu@example.com');
});

test('uses a mail sender for the verification code when one is configured', async () => {
  const userRepository = new InMemoryUserRepository();
  const sent = [];
  const mailSender = { async send(message) { sent.push(message); } };
  const authService = new AuthService({ userRepository, jwtSecret: 'test-secret-at-least-this-long', mailSender });
  const result = await authService.emailSignup(validEmailSignup);
  assert.equal(result.devCode, undefined, 'code is emailed, not returned, when a mailer exists');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'ama.owusu@example.com');
});

// --- Social sign-in ---------------------------------------------------------

/** Minimal fake provider that returns a fixed profile for a known token. */
const fakeRegistry = (profile, provider = 'google') => ({
  get(name) {
    assert.equal(name, provider);
    return { async verify() { return { provider, ...profile }; } };
  },
});

const socialService = (profile, provider) => {
  const userRepository = new InMemoryUserRepository();
  const authService = new AuthService({
    userRepository,
    jwtSecret: 'test-secret-at-least-this-long',
    socialProviders: fakeRegistry(profile, provider),
  });
  return { authService, userRepository };
};

test('first-time social signup requires a username and a legal name', async () => {
  const { authService } = socialService({ providerUid: 'g-1', email: 'kojo@example.com', emailVerified: true });
  await assert.rejects(
    () => authService.socialAuth({ provider: 'google', token: 't', legalSurname: 'Boateng', legalGivenNames: 'Kojo' }),
    /username .* is required to sign up with google/,
  );
  await assert.rejects(
    () => authService.socialAuth({ provider: 'google', token: 't', username: 'kojo' }),
    /full legal name/,
  );
});

test('first-time social signup creates an account, identity and session', async () => {
  const { authService, userRepository } = socialService({
    providerUid: 'g-1', email: 'kojo@example.com', emailVerified: true, displayName: 'Kojo B',
  });
  const result = await authService.socialAuth({
    provider: 'google', token: 't', username: 'kojo', legalSurname: 'Boateng', legalGivenNames: 'Kojo',
  });
  assert.equal(typeof result.accessToken, 'string');
  assert.equal(result.user.username, 'kojo');
  assert.equal(result.user.email, 'kojo@example.com');
  assert.equal(result.user.emailVerified, true);
  const identity = await userRepository.findIdentity('google', 'g-1');
  assert.equal(identity.user_id, result.user.id);
});

test('a returning social user signs in without re-entering a username', async () => {
  const { authService } = socialService({ providerUid: 'g-1', email: 'kojo@example.com', emailVerified: true });
  const first = await authService.socialAuth({
    provider: 'google', token: 't', username: 'kojo', legalSurname: 'Boateng', legalGivenNames: 'Kojo',
  });
  const second = await authService.socialAuth({ provider: 'google', token: 't' });
  assert.equal(second.user.id, first.user.id);
});

test('a social login with a verified matching email links to the existing account', async () => {
  const { authService, userRepository } = socialService({
    providerUid: 'g-9', email: 'ama.owusu@example.com', emailVerified: true,
  });
  const email = await authService.emailSignup(validEmailSignup);
  const social = await authService.socialAuth({ provider: 'google', token: 't' });
  assert.equal(social.user.id, email.user.id, 'linked, not duplicated');
  const identity = await userRepository.findIdentity('google', 'g-9');
  assert.equal(identity.user_id, email.user.id);
});

test('social sign-in is rejected when no provider registry is configured', async () => {
  const userRepository = new InMemoryUserRepository();
  const authService = new AuthService({ userRepository, jwtSecret: 'test-secret-at-least-this-long' });
  await assert.rejects(
    () => authService.socialAuth({ provider: 'google', token: 't', username: 'x', legalSurname: 'Y', legalGivenNames: 'Z' }),
    /not enabled/,
  );
});
