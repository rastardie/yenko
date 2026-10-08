import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthService } from '../../src/application/auth-service.js';
import { createApp } from '../../src/app.js';
import { LocalAuthActorResolver } from '../../src/infrastructure/local-auth-actor-resolver.js';
import { runMigrations } from '../../src/infrastructure/migrations.js';
import { createPostgresPool } from '../../src/infrastructure/postgres.js';
import { PostgresTripRepository } from '../../src/infrastructure/postgres-trip-repository.js';
import { PostgresUserRepository } from '../../src/infrastructure/postgres-user-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const isTestDatabase = databaseUrl && /(?:_|-)test(?:$|[?/#])/.test(new URL(databaseUrl).pathname);

if (!databaseUrl || !isTestDatabase) {
  test('Email/social integration suite requires a dedicated TEST_DATABASE_URL', { skip: true }, () => {});
} else {
  let pool;
  let server;
  let baseUrl;

  // A fake Google provider so the social flow is exercised without a network.
  // The returned profile varies by token so different tokens are different users.
  const profilesByToken = {
    opaque: { providerUid: 'g-123', email: 'kojo@example.com', emailVerified: true, displayName: 'Kojo B' },
    fresh: { providerUid: 'g-999', email: null, emailVerified: false, displayName: null },
  };
  const socialProviders = {
    get() {
      return {
        async verify(token) {
          return { provider: 'google', ...(profilesByToken[token] ?? profilesByToken.opaque) };
        },
      };
    },
  };

  const request = async (path, body, token) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body ?? {}),
    });
    return { status: response.status, body: await response.json() };
  };

  test.before(async () => {
    pool = createPostgresPool({ connectionString: databaseUrl, max: 2 });
    await runMigrations(pool);
    await pool.query('TRUNCATE auth_identities, notifications, outbox_events, audit_events, idempotency_keys, reservations, trips, users CASCADE');
    const userRepository = new PostgresUserRepository({ pool });
    const authService = new AuthService({
      userRepository,
      jwtSecret: 'integration-secret-at-least-this-long',
      socialProviders,
    });
    server = createApp({
      environment: 'test',
      tripRepository: new PostgresTripRepository({ pool }),
      authService,
      actorResolver: new LocalAuthActorResolver({ authService }),
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  test.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    await pool.end();
  });

  test('email signup, verify and login end to end', async () => {
    const signup = await request('/v1/auth/email/signup', {
      email: 'ama@example.com',
      password: 'Str0ngPassw0rd',
      displayName: 'Ama',
      legalSurname: 'Owusu',
      legalGivenNames: 'Ama Serwaa',
    });
    assert.equal(signup.status, 201, JSON.stringify(signup.body));
    const { accessToken, devCode } = signup.body.data;
    assert.equal(typeof accessToken, 'string');
    assert.equal(typeof devCode, 'string');

    const confirm = await request('/v1/auth/email-verification/confirm', { code: devCode }, accessToken);
    assert.equal(confirm.status, 200, JSON.stringify(confirm.body));
    assert.equal(confirm.body.data.verified, true);

    const login = await request('/v1/auth/login', { identity: 'ama@example.com', password: 'Str0ngPassw0rd' });
    assert.equal(login.status, 200, JSON.stringify(login.body));
    assert.equal(login.body.data.user.email, 'ama@example.com');
    assert.equal(login.body.data.user.emailVerified, true);
  });

  test('social signup then returning social login', async () => {
    const first = await request('/v1/auth/social', {
      provider: 'google',
      token: 'opaque',
      username: 'kojo',
      legalSurname: 'Boateng',
      legalGivenNames: 'Kojo',
    });
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.data.user.username, 'kojo');

    const again = await request('/v1/auth/social', { provider: 'google', token: 'opaque' });
    assert.equal(again.status, 200, JSON.stringify(again.body));
    assert.equal(again.body.data.user.id, first.body.data.user.id);
  });

  test('rejects a social signup without a legal name', async () => {
    const result = await request('/v1/auth/social', { provider: 'google', token: 'fresh', username: 'noname' });
    assert.equal(result.status, 400, JSON.stringify(result.body));
    assert.match(result.body.error.message, /full legal name/);
  });
}
