import assert from 'node:assert/strict';
import test from 'node:test';

import { periodRange } from '../src/application/admin-service.js';
import { AuthService } from '../src/application/auth-service.js';
import { InMemoryUserRepository } from './fixtures/in-memory-user-repository.js';

const iso = (range) => [range.from.toISOString(), range.to.toISOString()];
// Sunday 2026-10-04 15:30 UTC (Accra is UTC+0).
const now = new Date('2026-10-04T15:30:00.000Z');

test('resolves today, week and month to half-open UTC ranges', () => {
  assert.deepEqual(iso(periodRange('today', undefined, undefined, now)), ['2026-10-04T00:00:00.000Z', '2026-10-05T00:00:00.000Z']);
  // Weeks run Monday to Sunday, so Sunday 4 Oct belongs to the week of Monday 28 Sep.
  assert.deepEqual(iso(periodRange('week', undefined, undefined, now)), ['2026-09-28T00:00:00.000Z', '2026-10-05T00:00:00.000Z']);
  assert.deepEqual(iso(periodRange('month', undefined, undefined, now)), ['2026-10-01T00:00:00.000Z', '2026-11-01T00:00:00.000Z']);
  assert.deepEqual(
    iso(periodRange('week', undefined, undefined, new Date('2026-10-05T00:00:00.000Z'))),
    ['2026-10-05T00:00:00.000Z', '2026-10-12T00:00:00.000Z'],
    'Monday starts a new week',
  );
  assert.deepEqual(iso(periodRange(undefined, undefined, undefined, now)), iso(periodRange('week', undefined, undefined, now)));
});

test('custom ranges include the whole end day and are validated', () => {
  assert.deepEqual(iso(periodRange('custom', '2026-10-01', '2026-10-03', now)), ['2026-10-01T00:00:00.000Z', '2026-10-04T00:00:00.000Z']);
  assert.deepEqual(iso(periodRange('custom', '2026-10-01', '2026-10-01', now)), ['2026-10-01T00:00:00.000Z', '2026-10-02T00:00:00.000Z']);
  assert.throws(() => periodRange('custom', '2026-10-03', '2026-10-01', now), /not be before/);
  assert.throws(() => periodRange('custom', '2026-02-30', '2026-03-01', now), /valid date/);
  assert.throws(() => periodRange('custom', 'soon', '2026-03-01', now), /date like/);
  assert.throws(() => periodRange('custom', undefined, undefined, now), /date like/);
  assert.throws(() => periodRange('custom', '2025-01-01', '2026-12-31', now), /one year/);
  assert.throws(() => periodRange('fortnight', undefined, undefined, now), /period must be/);
});

const buildAuth = (signupApproval) => {
  const userRepository = new InMemoryUserRepository();
  return {
    userRepository,
    authService: new AuthService({ userRepository, jwtSecret: 'test-secret-at-least-this-long', signupApproval }),
  };
};

test('signup approval policy: none, drivers and all', async () => {
  const signup = (authService, role) =>
    authService.signup({ displayName: 'Test', username: `user-${role}-${Math.random().toString(36).slice(2, 8)}`, password: 'Str0ngPassw0rd', role });

  const none = buildAuth('none').authService;
  assert.ok((await signup(none, 'driver')).accessToken);

  const drivers = buildAuth('drivers').authService;
  assert.equal((await signup(drivers, 'driver')).pending, true);
  assert.ok((await signup(drivers, 'passenger')).accessToken);

  const all = buildAuth('all').authService;
  const held = await signup(all, 'passenger');
  assert.equal(held.pending, true);
  assert.equal('accessToken' in held, false);

  assert.throws(() => buildAuth('sometimes'), /signupApproval must be/);
});

test('a pending account cannot sign in until it is activated', async () => {
  const { authService, userRepository } = buildAuth('drivers');
  await authService.signup({ displayName: 'Kofi', username: 'kofi-pending', password: 'Str0ngPassw0rd', role: 'driver' });
  await assert.rejects(() => authService.login({ identity: 'kofi-pending', password: 'Str0ngPassw0rd' }), /waiting for approval/);
  (await userRepository.findByUsername('kofi-pending')).status = 'active';
  assert.ok((await authService.login({ identity: 'kofi-pending', password: 'Str0ngPassw0rd' })).accessToken);
});

test('admin-action tokens are bound to the account and expire with its credentials', async () => {
  const { authService, userRepository } = buildAuth('none');
  const ama = await authService.signup({ displayName: 'Ama', username: 'ama-admin', password: 'Str0ngPassw0rd', quickPin: '246800' });
  const kofi = await authService.signup({ displayName: 'Kofi', username: 'kofi-admin', password: 'Str0ngPassw0rd' });

  await assert.rejects(() => authService.issueAdminActionToken({ userId: ama.user.id, credential: 'nope' }), /Incorrect password or PIN/);
  await assert.rejects(() => authService.issueAdminActionToken({ userId: ama.user.id, credential: '' }), /Enter your password/);
  const viaPin = await authService.issueAdminActionToken({ userId: ama.user.id, credential: '246800' });
  const viaPassword = await authService.issueAdminActionToken({ userId: ama.user.id, credential: 'Str0ngPassw0rd' });

  assert.equal(await authService.verifyAdminActionToken(viaPin.token, ama.user.id), true);
  assert.equal(await authService.verifyAdminActionToken(viaPassword.token, ama.user.id), true);
  assert.equal(await authService.verifyAdminActionToken(viaPin.token, kofi.user.id), false, 'not valid for another account');
  assert.equal(await authService.verifyAdminActionToken(ama.accessToken, ama.user.id), false, 'a login token is not an action token');
  assert.equal(await authService.verifyAdminActionToken(undefined, ama.user.id), false);
  assert.equal(await authService.verifyAdminActionToken('garbage', ama.user.id), false);

  // Changing the credentials (which bumps auth_version) invalidates outstanding tokens.
  await userRepository.bumpAuthVersion(ama.user.id);
  assert.equal(await authService.verifyAdminActionToken(viaPin.token, ama.user.id), false);
});

test('repeated wrong admin-action credentials lock the account for a while', async () => {
  const { authService } = buildAuth('none');
  const ama = await authService.signup({ displayName: 'Ama', username: 'ama-lock', password: 'Str0ngPassw0rd' });
  for (let i = 0; i < 5; i += 1) {
    await assert.rejects(() => authService.issueAdminActionToken({ userId: ama.user.id, credential: `wrong-${i}` }), /Incorrect/);
  }
  await assert.rejects(
    () => authService.issueAdminActionToken({ userId: ama.user.id, credential: 'Str0ngPassw0rd' }),
    (error) => error.status === 429 && error.code === 'too_many_attempts',
  );
});
