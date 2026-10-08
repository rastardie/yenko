import assert from 'node:assert/strict';
import test from 'node:test';

import { createApp } from '../../src/app.js';
import { runMigrations } from '../../src/infrastructure/migrations.js';
import { createPostgresPool } from '../../src/infrastructure/postgres.js';
import { PostgresTripRepository } from '../../src/infrastructure/postgres-trip-repository.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
const isTestDatabase = databaseUrl && /(?:_|-)test(?:$|[?/#])/.test(new URL(databaseUrl).pathname);

if (!databaseUrl || !isTestDatabase) {
  test('PostgreSQL integration suite requires a dedicated TEST_DATABASE_URL', { skip: true }, () => {});
} else {
  let pool;
  let server;
  let baseUrl;

  const request = async (path, options) => {
    const response = await fetch(`${baseUrl}${path}`, options);
    return { status: response.status, body: await response.json() };
  };

  test.before(async () => {
    pool = createPostgresPool({ connectionString: databaseUrl, max: 2 });
    await runMigrations(pool);
    await pool.query('TRUNCATE notifications, outbox_events, audit_events, idempotency_keys, reservations, trips, users CASCADE');
    server = createApp({
      environment: 'test',
      tripRepository: new PostgresTripRepository({ pool }),
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  test.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await pool.end();
  });

  test('persists a trip and creates exactly one transactional, idempotent reservation', async () => {
    const driverHeaders = {
      'content-type': 'application/json',
      'x-yenko-actor-id': 'driver-integration-001',
      'x-yenko-role': 'driver',
      'x-yenko-display-name': 'Integration Driver',
    };
    const tripResponse = await request('/v1/trips', {
      method: 'POST', headers: driverHeaders,
      body: JSON.stringify({
        from: 'Adenta', to: 'Circle', pickupJunction: '37 Station',
        departureAt: new Date(Date.now() + 60 * 60_000).toISOString(),
        seatsAvailable: 2, pricePerSeat: 15, isWomenOnly: false,
      }),
    });
    assert.equal(tripResponse.status, 201);
    const tripId = tripResponse.body.data.id;

    const reservationHeaders = {
      'content-type': 'application/json',
      'x-yenko-actor-id': 'passenger-integration-001',
      'x-yenko-role': 'passenger',
      'idempotency-key': 'postgres-reservation-001',
    };
    const first = await request(`/v1/trips/${tripId}/reservations`, {
      method: 'POST', headers: reservationHeaders, body: JSON.stringify({ seats: 1 }),
    });
    const replay = await request(`/v1/trips/${tripId}/reservations`, {
      method: 'POST', headers: reservationHeaders, body: JSON.stringify({ seats: 1 }),
    });

    assert.equal(first.status, 201);
    assert.equal(replay.status, 200);
    assert.equal(first.body.data.id, replay.body.data.id);
    assert.equal(replay.body.data.idempotentReplay, true);
    const trip = await pool.query('SELECT seats_available FROM trips WHERE id = $1', [tripId]);
    const reservations = await pool.query('SELECT count(*)::int AS count FROM reservations WHERE trip_id = $1', [tripId]);
    const outbox = await pool.query("SELECT count(*)::int AS count FROM outbox_events WHERE event_type = 'reservation.requested'");
    const cancellation = await request(`/v1/me/reservations/${first.body.data.id}`, {
      method: 'DELETE', headers: reservationHeaders,
    });
    const cancellationReplay = await request(`/v1/me/reservations/${first.body.data.id}`, {
      method: 'DELETE', headers: reservationHeaders,
    });
    assert.equal(cancellation.status, 200);
    assert.equal(cancellation.body.data.status, 'cancelled');
    assert.equal(cancellationReplay.body.data.idempotentReplay, true);

    const restoredTrip = await pool.query('SELECT seats_available FROM trips WHERE id = $1', [tripId]);
    const cancelledReservation = await pool.query('SELECT status FROM reservations WHERE id = $1', [first.body.data.id]);
    const cancellationOutbox = await pool.query("SELECT count(*)::int AS count FROM outbox_events WHERE event_type = 'reservation.cancelled'");
    assert.equal(restoredTrip.rows[0].seats_available, 2);
    assert.equal(cancelledReservation.rows[0].status, 'cancelled');
    assert.equal(cancellationOutbox.rows[0].count, 1);
  });
}
