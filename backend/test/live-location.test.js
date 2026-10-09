import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthService } from '../src/application/auth-service.js';
import { createApp } from '../src/app.js';
import { LocalAuthActorResolver } from '../src/infrastructure/local-auth-actor-resolver.js';
import { InMemoryTripRepository } from '../src/infrastructure/in-memory-trip-repository.js';
import { InMemoryUserRepository } from './fixtures/in-memory-user-repository.js';

/**
 * Full in-memory stack (no Postgres) exercising live GPS location sharing:
 * a driver posts a fix while a trip has a confirmed booking, and the
 * passenger on that booking can read it back. See migration 013 and
 * HANDOVER.md — there is no websocket layer, the rider polls, same as onb.
 */

const seedTrip = (now = new Date()) => ({
  id: 'trip-kwame',
  driver: { id: 'driver-kwame', displayName: 'Kwame Mensah', rating: 4.8, completedTrips: 32, verificationStatus: 'demo' },
  vehicle: { description: 'Toyota Corolla', verificationStatus: 'demo' },
  from: 'East Legon Hills', to: 'Circle', pickupJunction: 'Madina Market junction',
  departureAt: new Date(now.getTime() + 18 * 60_000).toISOString(), seatsAvailable: 3,
  pricePerSeat: 15, isWomenOnly: false, status: 'open', createdAt: now.toISOString(),
});

async function withStack(run) {
  const userRepository = new InMemoryUserRepository();
  const authService = new AuthService({ userRepository, jwtSecret: 'test-secret-at-least-this-long' });
  const tripRepository = new InMemoryTripRepository([seedTrip()]);
  const server = createApp({
    environment: 'test',
    tripRepository,
    authService,
    actorResolver: new LocalAuthActorResolver({ authService }),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  try {
    await run({ baseUrl, userRepository, authService });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
}

const json = async (response) => ({ status: response.status, body: await response.json() });

async function signUpAs({ userRepository, authService }, { id, displayName, phone, role }) {
  const bcrypt = (await import('bcryptjs')).default;
  await userRepository.createUser({ id, displayName, phone, pinHash: null, roles: [role] });
  const pinHash = await bcrypt.hash('1234', 4);
  await userRepository.setPinHash(id, pinHash);
  const session = await authService.login({ identity: phone, password: '1234' });
  return session.accessToken;
}

test('a driver can share live location on a trip with a confirmed booking, and the rider can read it', async () => {
  await withStack(async (stack) => {
    const driverToken = await signUpAs(stack, {
      id: 'driver-kwame', displayName: 'Kwame Mensah', phone: '+233240000001', role: 'driver',
    });
    const driverAuth = { authorization: `Bearer ${driverToken}`, 'content-type': 'application/json' };

    const passengerToken = await signUpAs(stack, {
      id: 'passenger-ama', displayName: 'Ama Addo', phone: '+233240000002', role: 'passenger',
    });
    const passengerAuth = { authorization: `Bearer ${passengerToken}`, 'content-type': 'application/json' };

    const reservation = await json(await fetch(`${stack.baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerAuth, 'idempotency-key': 'live-location-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    assert.equal(reservation.status, 201);
    const reservationId = reservation.body.data.id;

    // Nothing to report yet — the trip has no confirmed booking.
    const tooEarly = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST', headers: driverAuth,
      body: JSON.stringify({ latitude: 5.65, longitude: -0.19, speedKmh: 32, heading: 90 }),
    }));
    assert.equal(tooEarly.status, 409);

    await fetch(`${stack.baseUrl}/v1/driver/reservations/${reservationId}/confirm`, {
      method: 'POST', headers: driverAuth,
    });

    // No fix yet — the rider sees nulls, not an error.
    const beforeFix = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/location`, {
      headers: passengerAuth,
    }));
    assert.equal(beforeFix.status, 200);
    assert.equal(beforeFix.body.data.latitude, null);
    assert.equal(beforeFix.body.data.updatedAt, null);

    const posted = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST', headers: driverAuth,
      body: JSON.stringify({ latitude: 5.65, longitude: -0.19, speedKmh: 32, heading: 90 }),
    }));
    assert.equal(posted.status, 200);
    assert.deepEqual(posted.body.data.updatedReservationIds, [reservationId]);

    const afterFix = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/location`, {
      headers: passengerAuth,
    }));
    assert.equal(afterFix.status, 200);
    assert.equal(afterFix.body.data.latitude, 5.65);
    assert.equal(afterFix.body.data.longitude, -0.19);
    assert.equal(afterFix.body.data.speedKmh, 32);
    assert.equal(afterFix.body.data.heading, 90);
    assert.ok(afterFix.body.data.updatedAt);

    // A different driver cannot post location onto someone else's trip.
    const otherDriverToken = await signUpAs(stack, {
      id: 'driver-other', displayName: 'Yaw Boateng', phone: '+233240000003', role: 'driver',
    });
    const otherDriverAttempt = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST',
      headers: { authorization: `Bearer ${otherDriverToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ latitude: 5.66, longitude: -0.2 }),
    }));
    assert.equal(otherDriverAttempt.status, 404);

    // A different passenger cannot read this booking's location.
    const otherPassengerToken = await signUpAs(stack, {
      id: 'passenger-other', displayName: 'Esi Mensah', phone: '+233240000004', role: 'passenger',
    });
    const otherPassengerAttempt = await json(await fetch(
      `${stack.baseUrl}/v1/me/reservations/${reservationId}/location`,
      { headers: { authorization: `Bearer ${otherPassengerToken}` } },
    ));
    assert.equal(otherPassengerAttempt.status, 404);
  });
});

test('out-of-range coordinates are rejected before touching the repository', async () => {
  await withStack(async (stack) => {
    const driverToken = await signUpAs(stack, {
      id: 'driver-kwame', displayName: 'Kwame Mensah', phone: '+233240000001', role: 'driver',
    });
    const driverAuth = { authorization: `Bearer ${driverToken}`, 'content-type': 'application/json' };

    const badLatitude = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST', headers: driverAuth,
      body: JSON.stringify({ latitude: 95, longitude: -0.19 }),
    }));
    assert.equal(badLatitude.status, 400);

    const missingLongitude = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST', headers: driverAuth,
      body: JSON.stringify({ latitude: 5.65 }),
    }));
    assert.equal(missingLongitude.status, 400);
  });
});

test('only a driver with trips:share_location may post location', async () => {
  await withStack(async (stack) => {
    const passengerToken = await signUpAs(stack, {
      id: 'passenger-ama', displayName: 'Ama Addo', phone: '+233240000002', role: 'passenger',
    });
    const attempt = await json(await fetch(`${stack.baseUrl}/v1/driver/trips/trip-kwame/location`, {
      method: 'POST',
      headers: { authorization: `Bearer ${passengerToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ latitude: 5.65, longitude: -0.19 }),
    }));
    assert.equal(attempt.status, 403);
  });
});
