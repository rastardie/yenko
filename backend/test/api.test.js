import assert from 'node:assert/strict';
import test from 'node:test';

import { createApp } from '../src/app.js';

async function withServer(run) {
  const server = createApp({ environment: 'test' });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
}

const json = async (response) => ({ status: response.status, body: await response.json() });

const passengerHeaders = {
  'content-type': 'application/json',
  'x-yenko-actor-id': 'passenger-001',
  'x-yenko-role': 'passenger',
};

test('lists privacy-minimized, women-only-filterable trips', async () => {
  await withServer(async (baseUrl) => {
    const response = await json(await fetch(`${baseUrl}/v1/trips?womenOnly=true`));
    assert.equal(response.status, 200);
    assert.equal(response.body.data.length, 1);
    assert.equal(response.body.data[0].driver.displayName, 'Ama Owusu');
    assert.equal('plateNumber' in response.body.data[0], false);
    assert.equal('id' in response.body.data[0].driver, false);
  });
});

test('requires a role and validates trip drafts', async () => {
  await withServer(async (baseUrl) => {
    const noActor = await json(await fetch(`${baseUrl}/v1/trips`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    }));
    assert.equal(noActor.status, 401);

    const invalid = await json(await fetch(`${baseUrl}/v1/trips`, {
      method: 'POST',
      headers: { ...passengerHeaders, 'x-yenko-role': 'driver' },
      body: JSON.stringify({
        from: 'Adenta', to: 'Circle', pickupJunction: '37 Station',
        departureAt: '2020-01-01T10:00:00.000Z', seatsAvailable: 5,
        pricePerSeat: 12, isWomenOnly: false,
      }),
    }));
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.error.code, 'invalid_request');
  });
});

test('creates an idempotent seat request and decrements inventory once', async () => {
  await withServer(async (baseUrl) => {
    const headers = { ...passengerHeaders, 'idempotency-key': 'reservation-001' };
    const first = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST', headers, body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(first.status, 201);
    assert.equal(first.body.data.status, 'requested');
    assert.equal(first.body.data.idempotentReplay, false);

    const replay = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST', headers, body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(replay.status, 200);
    assert.equal(replay.body.data.id, first.body.data.id);
    assert.equal(replay.body.data.idempotentReplay, true);

    const trips = await json(await fetch(`${baseUrl}/v1/trips`));
    assert.equal(trips.body.data.find((trip) => trip.id === 'trip-kwame').seatsAvailable, 2);
  });
});

test('returns a passenger booking history, notification inbox, and driver summary', async () => {
  await withServer(async (baseUrl) => {
    const reservation = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerHeaders, 'idempotency-key': 'reservation-history-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(reservation.status, 201);

    const bookings = await json(await fetch(`${baseUrl}/v1/me/reservations`, { headers: passengerHeaders }));
    assert.equal(bookings.status, 200);
    assert.equal(bookings.body.data.length, 1);
    assert.equal(bookings.body.data[0].trip.id, 'trip-kwame');
    assert.equal('id' in bookings.body.data[0].trip.driver, false);

    const inbox = await json(await fetch(`${baseUrl}/v1/me/notifications`, { headers: passengerHeaders }));
    assert.equal(inbox.status, 200);
    assert.equal(inbox.body.data.length, 1);
    assert.equal(inbox.body.data[0].read, false);

    const markRead = await json(await fetch(`${baseUrl}/v1/me/notifications/read`, {
      method: 'POST', headers: passengerHeaders,
    }));
    assert.equal(markRead.status, 200);
    assert.equal(markRead.body.data.markedRead, 1);

    const driverSummary = await json(await fetch(`${baseUrl}/v1/driver/trips`, {
      headers: { ...passengerHeaders, 'x-yenko-actor-id': 'driver-kwame', 'x-yenko-role': 'driver' },
    }));
    assert.equal(driverSummary.status, 200);
    assert.equal(driverSummary.body.data[0].trip.id, 'trip-kwame');
    assert.equal(driverSummary.body.data[0].seatsBooked, 1);
  });
});

test('cancels a requested booking, restores seats, and excludes it from driver totals', async () => {
  await withServer(async (baseUrl) => {
    const reservation = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerHeaders, 'idempotency-key': 'reservation-cancel-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(reservation.status, 201);

    const cancellation = await json(await fetch(`${baseUrl}/v1/me/reservations/${reservation.body.data.id}`, {
      method: 'DELETE', headers: passengerHeaders,
    }));
    assert.equal(cancellation.status, 200);
    assert.equal(cancellation.body.data.status, 'cancelled');
    assert.equal(cancellation.body.data.idempotentReplay, false);

    const replay = await json(await fetch(`${baseUrl}/v1/me/reservations/${reservation.body.data.id}`, {
      method: 'DELETE', headers: passengerHeaders,
    }));
    assert.equal(replay.status, 200);
    assert.equal(replay.body.data.idempotentReplay, true);

    const trips = await json(await fetch(`${baseUrl}/v1/trips`));
    assert.equal(trips.body.data.find((trip) => trip.id === 'trip-kwame').seatsAvailable, 3);
    const bookings = await json(await fetch(`${baseUrl}/v1/me/reservations`, { headers: passengerHeaders }));
    assert.equal(bookings.body.data[0].status, 'cancelled');
    const summaries = await json(await fetch(`${baseUrl}/v1/driver/trips`, {
      headers: { ...passengerHeaders, 'x-yenko-actor-id': 'driver-kwame', 'x-yenko-role': 'driver' },
    }));
    assert.equal(summaries.body.data[0].seatsBooked, 0);
  });
});

test('refuses production startup without PostgreSQL persistence and OIDC', () => {
  assert.throws(() => createApp({ environment: 'production' }), /Production requires/);
});

test('a driver can list, confirm and decline pending seat requests on their own trips', async () => {
  await withServer(async (baseUrl) => {
    const driverHeaders = {
      'content-type': 'application/json',
      'x-yenko-actor-id': 'driver-kwame',
      'x-yenko-role': 'driver',
    };

    const toConfirm = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerHeaders, 'idempotency-key': 'driver-flow-confirm-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(toConfirm.status, 201);

    const toDecline = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: {
        ...passengerHeaders,
        'x-yenko-actor-id': 'passenger-002',
        'idempotency-key': 'driver-flow-decline-001',
      },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(toDecline.status, 201);

    const pending = await json(await fetch(`${baseUrl}/v1/driver/reservations`, { headers: driverHeaders }));
    assert.equal(pending.status, 200);
    assert.equal(pending.body.data.length, 2);
    assert.ok(pending.body.data.every((reservation) => reservation.status === 'requested'));

    const confirm = await json(await fetch(
      `${baseUrl}/v1/driver/reservations/${toConfirm.body.data.id}/confirm`,
      { method: 'POST', headers: driverHeaders },
    ));
    assert.equal(confirm.status, 200);
    assert.equal(confirm.body.data.status, 'confirmed');
    assert.equal(confirm.body.data.idempotentReplay, false);

    const decline = await json(await fetch(
      `${baseUrl}/v1/driver/reservations/${toDecline.body.data.id}/decline`,
      { method: 'POST', headers: driverHeaders },
    ));
    assert.equal(decline.status, 200);
    assert.equal(decline.body.data.status, 'cancelled');

    // Declining released the seat; confirming did not change seat inventory
    // (it was already decremented when the seat was requested).
    const trips = await json(await fetch(`${baseUrl}/v1/trips`));
    assert.equal(trips.body.data.find((trip) => trip.id === 'trip-kwame').seatsAvailable, 2);

    const stillPending = await json(await fetch(`${baseUrl}/v1/driver/reservations`, { headers: driverHeaders }));
    assert.equal(stillPending.body.data.length, 0);
  });
});

test('a driver cannot confirm or decline another driver\'s reservation', async () => {
  await withServer(async (baseUrl) => {
    const reservation = await json(await fetch(`${baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerHeaders, 'idempotency-key': 'driver-ownership-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(reservation.status, 201);

    const otherDriverHeaders = {
      'content-type': 'application/json',
      'x-yenko-actor-id': 'driver-ama',
      'x-yenko-role': 'driver',
    };

    const confirmAttempt = await json(await fetch(
      `${baseUrl}/v1/driver/reservations/${reservation.body.data.id}/confirm`,
      { method: 'POST', headers: otherDriverHeaders },
    ));
    assert.equal(confirmAttempt.status, 404);

    const declineAttempt = await json(await fetch(
      `${baseUrl}/v1/driver/reservations/${reservation.body.data.id}/decline`,
      { method: 'POST', headers: otherDriverHeaders },
    ));
    assert.equal(declineAttempt.status, 404);

    // A passenger (even the one who made the request) cannot use the
    // driver-only confirm/decline routes at all.
    const passengerAttempt = await json(await fetch(
      `${baseUrl}/v1/driver/reservations/${reservation.body.data.id}/confirm`,
      { method: 'POST', headers: passengerHeaders },
    ));
    assert.equal(passengerAttempt.status, 403);
  });
});
