import assert from 'node:assert/strict';
import test from 'node:test';

import { AdminService } from '../../src/application/admin-service.js';
import { AuthService } from '../../src/application/auth-service.js';
import { createApp } from '../../src/app.js';
import { LocalAuthActorResolver } from '../../src/infrastructure/local-auth-actor-resolver.js';
import { runMigrations } from '../../src/infrastructure/migrations.js';
import { createPostgresPool } from '../../src/infrastructure/postgres.js';
import { PostgresAdminRepository } from '../../src/infrastructure/postgres-admin-repository.js';
import { PostgresTripRepository } from '../../src/infrastructure/postgres-trip-repository.js';
import { PostgresUserRepository } from '../../src/infrastructure/postgres-user-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const isTestDatabase = databaseUrl && /(?:_|-)test(?:$|[?/#])/.test(new URL(databaseUrl).pathname);

if (!databaseUrl || !isTestDatabase) {
  test('Admin PostgreSQL integration suite requires a dedicated TEST_DATABASE_URL', { skip: true }, () => {});
} else {
  const password = 'Test-Passw0rd!';
  let pool;
  let server;
  let baseUrl;
  let authService;
  const tokens = new Map();
  /** Each system group's permissions exactly as the migrations leave them. */
  let defaultScopes;

  const actionTokens = new Map();

  /** Returns a fresh admin-action token for the bearer, as the app does after its password prompt. */
  const actionTokenFor = async (token) => {
    if (!actionTokens.has(token)) {
      const response = await fetch(`${baseUrl}/v1/auth/admin-action-token`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
        body: JSON.stringify({ password }),
      });
      const body = await response.json();
      assert.equal(response.status, 200, JSON.stringify(body));
      actionTokens.set(token, body.data.token);
    }
    return actionTokens.get(token);
  };

  /**
   * Admin writes need an x-admin-action token; it is added automatically unless
   * `headers['x-admin-action']` is supplied (use '' to send none).
   */
  const api = async (method, path, token, body, headers = {}) => {
    const needsAction = token && path.startsWith('/v1/admin/') && method !== 'GET' && !('x-admin-action' in headers);
    const extra = needsAction ? { 'x-admin-action': await actionTokenFor(token) } : {};
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: {
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...extra,
        ...Object.fromEntries(Object.entries(headers).filter(([, value]) => value !== '')),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() };
  };

  const groupId = async (name) =>
    (await pool.query('SELECT id FROM groups WHERE name = $1', [name])).rows[0].id;

  /** Creates an account, joins the named groups, logs in and remembers its token. */
  const makeUser = async (username, groups = []) => {
    const user = await authService.createAccount({ displayName: `User ${username}`, username, password });
    for (const name of groups) {
      await pool.query('INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [
        await groupId(name), user.id,
      ]);
    }
    const login = await api('POST', '/v1/auth/login', null, { identity: username, password });
    assert.equal(login.status, 200, JSON.stringify(login.body));
    tokens.set(username, login.body.data.accessToken);
    return { id: user.id, token: login.body.data.accessToken, session: login.body.data };
  };

  test.before(async () => {
    pool = createPostgresPool({ connectionString: databaseUrl, max: 4 });
    await runMigrations(pool);
    await pool.query(
      'TRUNCATE notifications, outbox_events, audit_events, idempotency_keys, reservations, trips, users CASCADE',
    );
    await pool.query("DELETE FROM groups WHERE NOT is_system");
    const scopes = await pool.query(
      `SELECT g.name, COALESCE(array_agg(p.resource || ':' || p.action ORDER BY p.resource, p.action)
                FILTER (WHERE p.id IS NOT NULL), '{}') AS permissions
         FROM groups g
         LEFT JOIN group_permissions gp ON gp.group_id = g.id
         LEFT JOIN permissions p ON p.id = gp.permission_id
        WHERE g.is_system GROUP BY g.name`,
    );
    defaultScopes = Object.fromEntries(scopes.rows.map((row) => [row.name, row.permissions]));
    // The staff groups below are not let into the Admin area by default. The
    // tests about their individual permissions act as an administrator who
    // has ticked "Open the Admin area" on each of them.
    await pool.query(
      `INSERT INTO group_permissions (group_id, permission_id)
       SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
        WHERE g.name IN ('Operators', 'Support Agents', 'Finance', 'Fleet Managers')
          AND (p.resource, p.action) = ('admin', 'access')
       ON CONFLICT DO NOTHING`,
    );
    const userRepository = new PostgresUserRepository({ pool });
    authService = new AuthService({ userRepository, jwtSecret: 'integration-test-secret-not-for-production' });
    server = createApp({
      environment: 'test',
      tripRepository: new PostgresTripRepository({ pool }),
      actorResolver: new LocalAuthActorResolver({ authService }),
      authService,
      adminService: new AdminService({
        adminRepository: new PostgresAdminRepository({ pool }),
        userRepository,
        authService,
      }),
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  test.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    await pool.end();
  });

  test('seeds the ride-hailing system groups and their permissions', async () => {
    const root = await makeUser('root', ['Super Admins']);
    const groups = await api('GET', '/v1/admin/groups', root.token);
    assert.equal(groups.status, 200);
    const byName = Object.fromEntries(groups.body.data.map((group) => [group.name, group]));
    for (const name of ['Super Admins', 'Admins', 'Operators', 'Support Agents', 'Fleet Managers', 'Finance', 'Drivers', 'Riders']) {
      assert.ok(byName[name], `missing system group ${name}`);
      assert.equal(byName[name].isSystem, true);
    }
    const permissions = await api('GET', '/v1/admin/permissions', root.token);
    assert.equal(byName['Super Admins'].permissions.length, permissions.body.data.length);
    assert.equal(byName.Admins.permissions.includes('audit:read'), false);
    assert.equal(byName.Admins.permissions.includes('users:create'), true);
    // Drivers and Riders carry the app-side scope.
    assert.deepEqual(byName.Drivers.permissions.sort(), ['trips:manage_own', 'trips:offer']);
    assert.deepEqual(byName.Riders.permissions.sort(), ['reservations:book', 'reservations:cancel_own', 'reservations:view_own']);
    assert.ok(root.session.user.permissions.includes('audit:read'));
    assert.equal(root.session.user.role, 'super_admin');
  });

  test('rejects unauthenticated callers and users without admin permissions', async () => {
    const rider = await makeUser('plain-rider');
    assert.equal((await api('GET', '/v1/admin/users', null)).status, 401);
    for (const path of ['/v1/admin/users', '/v1/admin/groups', '/v1/admin/trips', '/v1/admin/dashboard', '/v1/admin/audit-logs']) {
      const response = await api('GET', path, rider.token);
      assert.equal(response.status, 403, path);
    }
    const me = await api('GET', '/v1/me', rider.token);
    assert.equal(me.body.data.permissions.includes('admin:access'), false);
    assert.deepEqual(me.body.data.permissions.sort(), ['reservations:book', 'reservations:cancel_own', 'reservations:view_own']);
  });

  test('enforces per-permission access for operators', async () => {
    const operator = await makeUser('ops-1', ['Operators']);
    assert.equal((await api('GET', '/v1/admin/dashboard', operator.token)).status, 200);
    assert.equal((await api('GET', '/v1/admin/trips', operator.token)).status, 200);
    assert.equal((await api('GET', '/v1/admin/users', operator.token)).status, 200);
    assert.equal((await api('GET', '/v1/admin/audit-logs', operator.token)).status, 403);
    assert.equal((await api('POST', '/v1/admin/users', operator.token, { displayName: 'X', username: 'x-user' })).status, 403);
    assert.equal((await api('POST', '/v1/admin/groups', operator.token, { name: 'Nope' })).status, 403);
  });

  test('admin creates a user in a group, with a generated one-time password', async () => {
    const admin = await makeUser('admin-1', ['Admins']);
    const drivers = await groupId('Drivers');
    const created = await api('POST', '/v1/admin/users', admin.token, {
      displayName: 'New Driver', username: 'new-driver', groupIds: [drivers],
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    assert.deepEqual(created.body.data.roles.sort(), ['driver', 'passenger']);
    assert.match(created.body.data.temporaryPassword, /^[A-Za-z0-9]{12}$/);
    const login = await api('POST', '/v1/auth/login', null, {
      identity: 'new-driver', password: created.body.data.temporaryPassword,
    });
    assert.equal(login.status, 200);
    assert.equal(login.body.data.user.role, 'driver');
    const duplicate = await api('POST', '/v1/admin/users', admin.token, { displayName: 'Dup', username: 'new-driver' });
    assert.equal(duplicate.status, 409);
  });

  test('suspending a user revokes their session immediately and restoring re-enables login', async () => {
    const admin = await makeUser('admin-2', ['Admins']);
    const victim = await makeUser('victim');
    const suspended = await api('PATCH', `/v1/admin/users/${victim.id}`, admin.token, { status: 'suspended' });
    assert.equal(suspended.status, 200);
    assert.equal(suspended.body.data.status, 'suspended');
    assert.equal((await api('GET', '/v1/me', victim.token)).status, 401);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'victim', password })).status, 403);
    await api('PATCH', `/v1/admin/users/${victim.id}`, admin.token, { status: 'active' });
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'victim', password })).status, 200);
    assert.equal((await api('PATCH', `/v1/admin/users/${admin.id}`, admin.token, { status: 'suspended' })).status, 409);
  });

  test('protects super admins: only super admins manage them and the last one is kept', async () => {
    const root = (await pool.query("SELECT id FROM users WHERE username = 'root'")).rows[0].id;
    const admin = await makeUser('admin-3', ['Admins']);
    assert.equal((await api('PATCH', `/v1/admin/users/${root}`, admin.token, { status: 'suspended' })).status, 403);
    assert.equal((await api('POST', `/v1/admin/users/${root}/reset-password`, admin.token, {})).status, 403);
    const superAdmins = await groupId('Super Admins');
    assert.equal((await api('POST', `/v1/admin/groups/${superAdmins}/members`, admin.token, { userId: admin.id })).status, 403);

    const rootToken = tokens.get('root');
    // Cannot suspend self, and cannot drop the only active super admin.
    assert.equal((await api('PATCH', `/v1/admin/users/${root}`, rootToken, { status: 'suspended' })).status, 409);
    assert.equal((await api('DELETE', `/v1/admin/groups/${superAdmins}/members/${root}`, rootToken)).status, 409);
    assert.equal((await api('PUT', `/v1/admin/groups/${superAdmins}/permissions`, rootToken, { permissions: [] })).status, 409);
  });

  test('prevents privilege escalation through group membership and permissions', async () => {
    const root = tokens.get('root');
    // A delegated manager who can assign members and permissions but holds little else.
    const created = await api('POST', '/v1/admin/groups', root, {
      name: 'Delegates', description: 'Can manage membership only',
      permissions: ['admin:access', 'groups:read', 'groups:assign_members', 'groups:assign_permissions'],
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const delegate = await makeUser('delegate', ['Delegates']);
    const target = await makeUser('target');
    const admins = await groupId('Admins');
    const superAdmins = await groupId('Super Admins');
    assert.equal((await api('POST', `/v1/admin/groups/${admins}/members`, delegate.token, { userId: target.id })).status, 403);
    assert.equal((await api('POST', `/v1/admin/groups/${superAdmins}/members`, delegate.token, { userId: target.id })).status, 403);
    // May not grant a permission it does not hold itself ...
    const custom = (await api('POST', '/v1/admin/groups', root, { name: 'Viewers', permissions: [] })).body.data;
    assert.equal((await api('PUT', `/v1/admin/groups/${custom.id}/permissions`, delegate.token, { permissions: ['users:read'] })).status, 403);
    // ... but may grant one it holds.
    const granted = await api('PUT', `/v1/admin/groups/${custom.id}/permissions`, delegate.token, { permissions: ['groups:read'] });
    assert.equal(granted.status, 200);
    assert.deepEqual(granted.body.data.permissions, ['groups:read']);
    // Unknown permission keys are rejected.
    assert.equal((await api('PUT', `/v1/admin/groups/${custom.id}/permissions`, root, { permissions: ['nope:nothing'] })).status, 400);
    // A group cannot be created with permissions its creator lacks.
    assert.equal((await api('POST', '/v1/admin/groups', delegate.token, { name: 'Sneaky', permissions: ['audit:read'] })).status, 403);
  });

  test('custom group lifecycle; system groups are immutable', async () => {
    const root = tokens.get('root');
    const created = await api('POST', '/v1/admin/groups', root, { name: 'Campus Leads', permissions: ['trips:read'] });
    assert.equal(created.status, 201);
    assert.equal((await api('POST', '/v1/admin/groups', root, { name: 'campus leads' })).status, 409);
    const member = await makeUser('campus-lead');
    const added = await api('POST', `/v1/admin/groups/${created.body.data.id}/members`, root, { userId: member.id });
    assert.equal(added.body.data.memberCount, 1);
    // Effective permissions follow membership immediately (same token, next request).
    assert.ok((await api('GET', '/v1/me', member.token)).body.data.permissions.includes('trips:read'));
    assert.equal((await api('PATCH', `/v1/admin/groups/${created.body.data.id}`, root, { name: 'Campus Captains' })).status, 200);
    assert.equal((await api('DELETE', `/v1/admin/groups/${created.body.data.id}`, root)).status, 200);
    assert.equal((await api('GET', '/v1/me', member.token)).body.data.permissions.includes('trips:read'), false);

    const riders = await groupId('Riders');
    assert.equal((await api('DELETE', `/v1/admin/groups/${riders}`, root)).status, 409);
    assert.equal((await api('PATCH', `/v1/admin/groups/${riders}`, root, { name: 'Passengers' })).status, 409);
    assert.equal((await api('GET', '/v1/admin/groups/not-a-uuid', root)).status, 404);
  });

  test('operators cancel a trip, which cancels bookings and notifies both sides', async () => {
    const root = tokens.get('root');
    const operator = tokens.get('ops-1');
    const driver = await makeUser('trip-driver', ['Drivers']);
    const rider = await makeUser('trip-rider');
    const trip = await api('POST', '/v1/trips', driver.token, {
      from: 'Adenta', to: 'Circle', pickupJunction: '37 Station',
      departureAt: new Date(Date.now() + 3_600_000).toISOString(),
      seatsAvailable: 2, pricePerSeat: 15, isWomenOnly: false,
    });
    assert.equal(trip.status, 201, JSON.stringify(trip.body));
    const booked = await api('POST', `/v1/trips/${trip.body.data.id}/reservations`, rider.token, { seats: 1 }, {
      'idempotency-key': 'admin-cancel-test-001',
    });
    assert.equal(booked.status, 201, JSON.stringify(booked.body));

    const listed = await api('GET', '/v1/admin/trips?status=open', operator);
    const tripRow = listed.body.data.find((row) => row.id === trip.body.data.id);
    assert.equal(tripRow.bookingCount, 1);
    assert.equal(tripRow.driver.displayName, 'User trip-driver');

    const cancelled = await api('POST', `/v1/admin/trips/${trip.body.data.id}/cancel`, operator);
    assert.equal(cancelled.status, 200, JSON.stringify(cancelled.body));
    assert.equal(cancelled.body.data.status, 'cancelled');
    assert.equal(cancelled.body.data.reservations[0].status, 'cancelled');
    assert.equal((await api('POST', `/v1/admin/trips/${trip.body.data.id}/cancel`, operator)).status, 409);

    const riderInbox = await api('GET', '/v1/me/notifications', rider.token);
    assert.ok(riderInbox.body.data.some((note) => note.type === 'reservation.cancelled_by_staff'));
    const driverInbox = await api('GET', '/v1/me/notifications', driver.token);
    assert.ok(driverInbox.body.data.some((note) => note.type === 'trip.cancelled_by_staff'));
    assert.equal((await api('POST', `/v1/admin/trips/${trip.body.data.id}/cancel`, rider.token)).status, 403);

    const dashboard = await api('GET', '/v1/admin/dashboard', root);
    assert.equal(dashboard.body.data.trips.cancelled, 1);
    assert.equal(dashboard.body.data.reservations.cancelled, 1);
    assert.ok(dashboard.body.data.users.total >= 8);
    assert.ok(dashboard.body.data.groups.some((group) => group.name === 'Riders' && group.members >= 1));
  });

  test('resets a password, revokes old sessions and keeps secrets out of the audit trail', async () => {
    const admin = tokens.get('admin-1');
    const root = tokens.get('root');
    const subject = await makeUser('reset-me');
    const newPassword = 'Brand-New-Passw0rd';
    const reset = await api('POST', `/v1/admin/users/${subject.id}/reset-password`, admin, { password: newPassword });
    assert.equal(reset.status, 200);
    assert.equal('temporaryPassword' in reset.body.data, false);
    assert.equal((await api('GET', '/v1/me', subject.token)).status, 401);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'reset-me', password })).status, 401);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'reset-me', password: newPassword })).status, 200);
    assert.equal((await api('POST', `/v1/admin/users/${subject.id}/reset-password`, admin, { password: 'short' })).status, 400);

    const audit = await api('GET', '/v1/admin/audit-logs?limit=200', root);
    assert.equal(audit.status, 200);
    const actions = new Set(audit.body.data.map((event) => event.action));
    for (const action of ['admin.user.created', 'admin.user.suspended', 'admin.user.restored', 'admin.user.password_reset',
      'admin.group.created', 'admin.group.permissions_set', 'admin.trip.cancelled']) {
      assert.ok(actions.has(action), `audit trail is missing ${action}`);
    }
    const serialized = JSON.stringify(audit.body);
    assert.equal(serialized.includes(newPassword), false);
    assert.equal(serialized.includes(password), false);
    const filtered = await api('GET', '/v1/admin/audit-logs?action=admin.trip.cancelled', root);
    assert.equal(filtered.body.total, 1);
    assert.equal(filtered.body.data[0].actor.displayName, 'User ops-1');
  });

  test('lists and filters users with pagination and safe search', async () => {
    const admin = tokens.get('admin-1');
    const page = await api('GET', '/v1/admin/users?limit=2&offset=0', admin);
    assert.equal(page.body.data.length, 2);
    assert.ok(page.body.total > 2);
    const search = await api('GET', '/v1/admin/users?search=trip-driver', admin);
    assert.equal(search.body.data.length, 1);
    assert.deepEqual(search.body.data[0].roles.sort(), ['driver', 'passenger']);
    const wildcard = await api('GET', `/v1/admin/users?search=${encodeURIComponent('%')}`, admin);
    assert.equal(wildcard.body.data.length, 0, 'LIKE wildcards in search must be escaped');
    assert.equal((await api('GET', '/v1/admin/users?status=bogus', admin)).status, 400);
    assert.equal((await api('GET', '/v1/admin/users?limit=abc', admin)).status, 400);
    const byGroup = await api('GET', `/v1/admin/users?groupId=${await groupId('Drivers')}`, admin);
    assert.ok(byGroup.body.data.every((user) => user.roles.includes('driver')));
  });

  test('admin writes require a fresh re-authentication token', async () => {
    const admin = await makeUser('reauth-admin', ['Admins']);
    const target = await makeUser('reauth-target');
    const body = { displayName: 'Renamed' };
    // No token at all.
    const none = await api('PATCH', `/v1/admin/users/${target.id}`, admin.token, body, { 'x-admin-action': '' });
    assert.equal(none.status, 403);
    assert.equal(none.body.error.code, 'admin_action_required');
    // A garbage token and another account's token are both rejected.
    const garbage = await api('PATCH', `/v1/admin/users/${target.id}`, admin.token, body, { 'x-admin-action': 'nonsense' });
    assert.equal(garbage.body.error.code, 'admin_action_required');
    const other = await actionTokenFor(target.token);
    const borrowed = await api('PATCH', `/v1/admin/users/${target.id}`, admin.token, body, { 'x-admin-action': other });
    assert.equal(borrowed.body.error.code, 'admin_action_required');
    // A login access token is not an admin-action token.
    const login = await api('PATCH', `/v1/admin/users/${target.id}`, admin.token, body, { 'x-admin-action': admin.token });
    assert.equal(login.body.error.code, 'admin_action_required');
    // Without the permission the caller gets a plain 403, not a password prompt.
    const rider = await makeUser('reauth-rider');
    const denied = await api('PATCH', `/v1/admin/users/${target.id}`, rider.token, body, { 'x-admin-action': await actionTokenFor(rider.token) });
    assert.equal(denied.body.error.code, 'forbidden');
    // The real thing works.
    assert.equal((await api('PATCH', `/v1/admin/users/${target.id}`, admin.token, body)).status, 200);
    // Reads never need it.
    assert.equal((await api('GET', '/v1/admin/users', admin.token)).status, 200);
  });

  test('wrong passwords are rejected and repeated failures lock the prompt', async () => {
    const victim = await makeUser('lockout');
    const attempt = (credential) => api('POST', '/v1/auth/admin-action-token', victim.token, { password: credential });
    assert.equal((await attempt('wrong-1')).status, 401);
    // A PIN-style quick credential is accepted the same way login accepts one.
    assert.equal((await attempt('')).status, 400);
    for (let i = 0; i < 4; i += 1) assert.equal((await attempt(`wrong-${i + 2}`)).status, 401);
    const locked = await attempt(password);
    assert.equal(locked.status, 429, 'the right password is refused while locked');
    assert.equal(locked.body.error.code, 'too_many_attempts');
  });

  test('approves or denies accounts that are waiting for approval', async () => {
    const admin = tokens.get('admin-1');
    const approver = await makeUser('approver', ['Support Agents']);
    const pending = await authService.createAccount({ displayName: 'Pending Driver', username: 'pending-driver', password, status: 'pending' });
    const denied = await authService.createAccount({ displayName: 'Denied Person', username: 'denied-person', password, status: 'pending' });

    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'pending-driver', password })).status, 403);
    const list = await api('GET', '/v1/admin/users?status=pending', admin);
    assert.deepEqual(list.body.data.map((user) => user.username).sort(), ['denied-person', 'pending-driver']);
    assert.equal((await api('GET', '/v1/admin/summary', admin)).body.data.users.pending, 2);

    assert.equal((await api('POST', `/v1/admin/users/${pending.id}/approve`, approver.token)).status, 200);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'pending-driver', password })).status, 200);
    // Approving twice, or approving someone who is active, is a conflict.
    assert.equal((await api('POST', `/v1/admin/users/${pending.id}/approve`, approver.token)).status, 409);

    assert.equal((await api('POST', `/v1/admin/users/${denied.id}/deny`, approver.token)).status, 200);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'denied-person', password })).status, 401);
    // Support cannot delete accounts; it only holds users:approve.
    assert.equal((await api('DELETE', `/v1/admin/users/${pending.id}`, approver.token)).status, 403);
  });

  test('signup approval policy keeps new drivers out until approved', async () => {
    const policyAuth = new AuthService({
      userRepository: new PostgresUserRepository({ pool }),
      jwtSecret: 'integration-test-secret-not-for-production',
      signupApproval: 'drivers',
    });
    const driver = await policyAuth.signup({ displayName: 'New Driver', username: 'policy-driver', password, role: 'driver' });
    assert.equal(driver.pending, true);
    assert.equal('accessToken' in driver, false);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'policy-driver', password })).status, 403);
    const rider = await policyAuth.signup({ displayName: 'New Rider', username: 'policy-rider', password, role: 'passenger' });
    assert.ok(rider.accessToken, 'riders are not held back under the drivers policy');
  });

  test('soft-deletes an account only when nothing is left open, freeing its username', async () => {
    const admin = tokens.get('admin-1');
    const doomed = await makeUser('doomed', ['Drivers']);
    const trip = await api('POST', '/v1/trips', doomed.token, {
      from: 'Madina', to: 'Osu', pickupJunction: 'Madina Station',
      departureAt: new Date(Date.now() + 7_200_000).toISOString(), seatsAvailable: 2, pricePerSeat: 12, isWomenOnly: false,
    });
    assert.equal(trip.status, 201, JSON.stringify(trip.body));
    assert.equal((await api('DELETE', `/v1/admin/users/${doomed.id}`, admin)).status, 409);
    assert.equal((await api('POST', `/v1/admin/trips/${trip.body.data.id}/cancel`, admin)).status, 200);

    const adminId = (await pool.query("SELECT id FROM users WHERE username = 'admin-1'")).rows[0].id;
    assert.equal((await api('DELETE', `/v1/admin/users/${adminId}`, admin)).status, 409, 'self-delete is refused');
    assert.equal((await api('DELETE', `/v1/admin/users/${doomed.id}`, admin)).status, 200);

    assert.equal((await api('GET', '/v1/me', doomed.token)).status, 401);
    assert.equal((await api('POST', '/v1/auth/login', null, { identity: 'doomed', password })).status, 401);
    const listed = await api('GET', '/v1/admin/users?search=doomed', admin);
    assert.equal(listed.body.data.length, 0, 'deleted accounts are hidden from the default list');
    const row = (await pool.query('SELECT status, username, phone, password_hash, pin_hash, deleted_at FROM users WHERE id = $1', [doomed.id])).rows[0];
    assert.deepEqual([row.status, row.username, row.phone, row.password_hash, row.pin_hash], ['deleted', null, null, null, null]);
    assert.ok(row.deleted_at);
    assert.equal((await pool.query('SELECT 1 FROM group_members WHERE user_id = $1', [doomed.id])).rowCount, 0);
    // The username can be used again, and the audit trail remembers who it was.
    await makeUser('doomed');
    const root = tokens.get('root');
    const audit = await api('GET', '/v1/admin/audit-logs?action=admin.user.deleted', root);
    assert.ok(audit.body.data.some((event) => event.metadata.username === 'doomed'));
    assert.equal((await api('DELETE', `/v1/admin/users/${doomed.id}`, admin)).status, 404);
    assert.ok((await api('GET', '/v1/admin/audit-logs/actions', root)).body.data.includes('admin.user.deleted'));
  });

  test('operations: lists bookings with totals, then confirms and cancels them', async () => {
    const operator = tokens.get('ops-1');
    const driver = await makeUser('ops-driver', ['Drivers']);
    const rider = await makeUser('ops-rider');
    const trip = await api('POST', '/v1/trips', driver.token, {
      from: 'Kasoa', to: 'Circle', pickupJunction: 'Kasoa Market',
      departureAt: new Date(Date.now() + 10_800_000).toISOString(), seatsAvailable: 3, pricePerSeat: 20, isWomenOnly: false,
    });
    const tripId = trip.body.data.id;
    const booked = await api('POST', `/v1/trips/${tripId}/reservations`, rider.token, { seats: 2 }, { 'idempotency-key': 'ops-booking-0001' });
    assert.equal(booked.status, 201, JSON.stringify(booked.body));
    const bookingId = booked.body.data.id;

    const search = await api('GET', '/v1/admin/bookings?search=Kasoa', operator);
    assert.equal(search.status, 200);
    assert.equal(search.body.data.length, 1);
    assert.deepEqual(
      [search.body.data[0].status, search.body.data[0].seats, search.body.data[0].fare, search.body.data[0].passenger.displayName, search.body.data[0].driver.displayName],
      ['requested', 2, 40, 'User ops-rider', 'User ops-driver'],
    );
    assert.deepEqual(search.body.totals, { bookings: 1, requested: 1, confirmed: 0, cancelled: 0, seats: 2, fare: 40 });

    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/confirm`, operator)).status, 200);
    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/confirm`, operator)).status, 200, 'confirming twice is a no-op');
    const confirmed = await api('GET', '/v1/admin/bookings?status=confirmed&search=Kasoa', operator);
    assert.equal(confirmed.body.totals.confirmed, 1);
    assert.ok((await api('GET', '/v1/me/notifications', rider.token)).body.data.some((note) => note.type === 'reservation.confirmed'));

    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/cancel`, operator)).status, 200);
    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/cancel`, operator)).status, 200, 'cancelling twice is a no-op');
    assert.equal((await pool.query('SELECT seats_available FROM trips WHERE id = $1', [tripId])).rows[0].seats_available, 3, 'seats are returned');
    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/confirm`, operator)).status, 409, 'a cancelled booking cannot be confirmed');
    const inbox = (await api('GET', '/v1/me/notifications', driver.token)).body.data;
    assert.ok(inbox.some((note) => note.type === 'driver.reservation.cancelled_by_staff'));

    // Filters are validated; riders cannot reach any of it.
    assert.equal((await api('GET', '/v1/admin/bookings?status=bogus', operator)).status, 400);
    assert.equal((await api('GET', '/v1/admin/bookings?from=yesterday', operator)).status, 400);
    assert.equal((await api('GET', '/v1/admin/bookings', rider.token)).status, 403);
    assert.equal((await api('POST', `/v1/admin/bookings/${bookingId}/cancel`, rider.token)).status, 403);
    assert.equal((await api('POST', '/v1/admin/bookings/not-a-uuid/cancel', operator)).status, 404);
  });

  test('reports need reports:read and metrics follow the chosen period', async () => {
    const operator = tokens.get('ops-1');
    const fleet = await makeUser('fleet-1', ['Fleet Managers']);
    const report = await api('GET', '/v1/admin/reports/bookings?limit=1000', operator);
    assert.equal(report.status, 200);
    assert.ok(report.body.totals.bookings >= 1);
    assert.equal((await api('GET', '/v1/admin/reports/bookings', fleet.token)).status, 200);
    const plain = await makeUser('report-rider');
    assert.equal((await api('GET', '/v1/admin/reports/bookings', plain.token)).status, 403);

    const month = await api('GET', '/v1/admin/metrics?period=month', operator);
    assert.equal(month.status, 200);
    for (const key of ['trips', 'bookings', 'users', 'drivers', 'daily']) assert.ok(key in month.body.data, key);
    assert.equal(month.body.data.period, 'month');
    const today = await api('GET', '/v1/admin/metrics?period=today', operator);
    assert.ok(today.body.data.trips.total <= month.body.data.trips.total);
    const custom = await api('GET', '/v1/admin/metrics?period=custom&from=2020-01-01&to=2020-01-31', operator);
    assert.equal(custom.body.data.trips.total, 0);
    assert.equal(custom.body.data.trips.utilizationPct, 0);
    assert.equal((await api('GET', '/v1/admin/metrics?period=custom&from=2020-02-01&to=2020-01-01', operator)).status, 400);
    assert.equal((await api('GET', '/v1/admin/metrics?period=custom&from=2020-01-01&to=2022-01-01', operator)).status, 400);
    assert.equal((await api('GET', '/v1/admin/metrics?period=decade', operator)).status, 400);
    assert.equal((await api('GET', '/v1/admin/metrics', plain.token)).status, 403);
  });

  test('the admin home summary only includes sections the caller may see', async () => {
    const operator = tokens.get('ops-1');
    const summary = await api('GET', '/v1/admin/summary', operator);
    assert.equal(summary.status, 200);
    assert.ok(summary.body.data.users && summary.body.data.trips && summary.body.data.bookings);
    assert.equal('groups' in summary.body.data, false, 'operators hold no groups:read');
    assert.equal((await api('GET', '/v1/admin/summary', tokens.get('plain-rider'))).status, 403);
  });
  test('every system group has a defined permission scope and only the Admin groups open the Admin area', async () => {
    const everything = (await pool.query("SELECT resource || ':' || action AS key FROM permissions ORDER BY 1")).rows.map((row) => row.key);
    assert.deepEqual(defaultScopes['Super Admins'], everything, 'Super Admins hold every permission');
    assert.deepEqual(
      defaultScopes.Admins,
      everything.filter((key) => key !== 'audit:read'),
      'Admins hold everything but the audit trail',
    );
    for (const [name, permissions] of Object.entries(defaultScopes)) {
      assert.ok(permissions.length > 0, `${name} has an empty scope`);
      const opensAdmin = permissions.includes('admin:access');
      assert.equal(opensAdmin, name === 'Super Admins' || name === 'Admins', `${name} admin:access`);
    }
    for (const name of ['Operators', 'Support Agents', 'Finance', 'Fleet Managers']) {
      assert.equal(defaultScopes[name].includes('dashboard:read'), true, `${name} keeps its scope`);
    }
    // Rider and driver scopes stay out of the admin catalog.
    assert.deepEqual(defaultScopes.Drivers, ['trips:manage_own', 'trips:offer']);
    assert.deepEqual(defaultScopes.Riders, ['reservations:book', 'reservations:cancel_own', 'reservations:view_own']);
  });

  test('a group without admin:access is kept out of the Admin area until an administrator opens it', async () => {
    const root = await makeUser('gate-root', ['Super Admins']);
    const created = await api('POST', '/v1/admin/groups', root.token, { name: 'Auditors', description: 'Read only' });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const groupKey = created.body.data.id;
    const grant = await api('PUT', `/v1/admin/groups/${groupKey}/permissions`, root.token, {
      permissions: ['users:read', 'groups:read', 'dashboard:read'],
    });
    assert.equal(grant.status, 200, JSON.stringify(grant.body));
    const auditor = await makeUser('gate-auditor', ['Auditors']);
    assert.ok(auditor.session.user.permissions.includes('users:read'));

    for (const path of ['/v1/admin/users', '/v1/admin/groups', '/v1/admin/summary']) {
      const response = await api('GET', path, auditor.token);
      assert.equal(response.status, 403, path);
      assert.match(response.body.error.message, /Admins group/);
    }

    const open = await api('PUT', `/v1/admin/groups/${groupKey}/permissions`, root.token, {
      permissions: ['admin:access', 'users:read', 'groups:read', 'dashboard:read'],
    });
    assert.equal(open.status, 200, JSON.stringify(open.body));
    assert.equal((await api('GET', '/v1/admin/users', auditor.token)).status, 200);
    // ...and the new scope still stops short of writes.
    assert.equal((await api('POST', '/v1/admin/groups', auditor.token, { name: 'Nope' })).status, 403);
  });

  test('Super Admins keep admin:access: the group cannot be edited, even by an Admin', async () => {
    const admin = await makeUser('gate-admin', ['Admins']);
    assert.ok(admin.session.user.permissions.includes('admin:access'));
    const superGroup = await groupId('Super Admins');
    const stripped = await api('PUT', `/v1/admin/groups/${superGroup}/permissions`, admin.token, { permissions: ['users:read'] });
    assert.ok([403, 409].includes(stripped.status), `status ${stripped.status}`);
    const after = await api('GET', '/v1/me', (await makeUser('gate-root-2', ['Super Admins'])).token);
    assert.ok(after.body.data.permissions.includes('admin:access'));
  });

  test('riders and drivers can only do what their groups grant', async () => {
    const rider = await makeUser('scope-rider', ['Riders']);
    assert.deepEqual(rider.session.user.permissions.sort(), ['reservations:book', 'reservations:cancel_own', 'reservations:view_own']);
    assert.equal((await api('GET', '/v1/me/reservations', rider.token)).status, 200);
    // Take the booking-list permission away from Riders: the API now refuses.
    await pool.query(
      `DELETE FROM group_permissions WHERE group_id = (SELECT id FROM groups WHERE name = 'Riders')
         AND permission_id = (SELECT id FROM permissions WHERE resource = 'reservations' AND action = 'view_own')`,
    );
    try {
      const refused = await api('GET', '/v1/me/reservations', rider.token);
      assert.equal(refused.status, 403);
      assert.match(refused.body.error.message, /reservations:view_own/);
    } finally {
      await pool.query(
        `INSERT INTO group_permissions (group_id, permission_id)
         SELECT g.id, p.id FROM groups g, permissions p
          WHERE g.name = 'Riders' AND p.resource = 'reservations' AND p.action = 'view_own'`,
      );
    }
    assert.equal((await api('GET', '/v1/me/reservations', rider.token)).status, 200);
  });

}
