import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthService } from '../src/application/auth-service.js';
import { createApp } from '../src/app.js';
import { LocalAuthActorResolver } from '../src/infrastructure/local-auth-actor-resolver.js';
import { InMemoryTripRepository } from '../src/infrastructure/in-memory-trip-repository.js';
import { InMemoryUserRepository } from './fixtures/in-memory-user-repository.js';

/**
 * Full in-memory stack (no Postgres) exercising the direct driver-to-passenger
 * mobile money flow end to end: a driver registers a payout number, a
 * passenger books and the driver confirms, then both sides self-report the
 * payment. See migration 011 and HANDOVER.md — none of this verifies a real
 * mobile money transaction; it is an honesty-based confirmation flow only.
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
  const tripRepository = new InMemoryTripRepository([seedTrip()], {
    momoLookup: (driverId) => {
      const user = userRepository.peek(driverId);
      return user?.momo_number ? { momoNumber: user.momo_number, momoNetwork: user.momo_network } : null;
    },
  });
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

// Signs a user up directly against the trip's seed driver id, so the trip's
// driver_id (a fixed seed value, not generated at signup) matches the
// account whose token we use to call driver routes.
async function signUpAs({ userRepository, authService }, { id, displayName, phone, role }) {
  const bcrypt = (await import('bcryptjs')).default;
  await userRepository.createUser({ id, displayName, phone, pinHash: null, roles: [role] });
  const pinHash = await bcrypt.hash('1234', 4);
  await userRepository.setPinHash(id, pinHash);
  const session = await authService.login({ identity: phone, password: '1234' });
  return session.accessToken;
}

test('a driver can register and clear a direct mobile money payout number', async () => {
  await withStack(async (stack) => {
    const driverToken = await signUpAs(stack, {
      id: 'driver-kwame', displayName: 'Kwame Mensah', phone: '+233240000001', role: 'driver',
    });
    const driverAuth = { authorization: `Bearer ${driverToken}`, 'content-type': 'application/json' };

    const initial = await json(await fetch(`${stack.baseUrl}/v1/me/momo`, { headers: driverAuth }));
    assert.equal(initial.status, 200);
    assert.equal(initial.body.data.momoNumber, null);

    const invalid = await json(await fetch(`${stack.baseUrl}/v1/me/momo`, {
      method: 'PUT', headers: driverAuth,
      body: JSON.stringify({ momoNumber: 'nope', momoNetwork: 'mtn' }),
    }));
    assert.equal(invalid.status, 400);

    const set = await json(await fetch(`${stack.baseUrl}/v1/me/momo`, {
      method: 'PUT', headers: driverAuth,
      body: JSON.stringify({ momoNumber: '+233244000111', momoNetwork: 'mtn' }),
    }));
    assert.equal(set.status, 200);
    assert.equal(set.body.data.momoNumber, '+233244000111');

    const cleared = await json(await fetch(`${stack.baseUrl}/v1/me/momo`, {
      method: 'PUT', headers: driverAuth,
      body: JSON.stringify({ momoNumber: null, momoNetwork: null }),
    }));
    assert.equal(cleared.status, 200);
    assert.equal(cleared.body.data.momoNumber, null);

    const passengerToken = await signUpAs(stack, {
      id: 'passenger-ama', displayName: 'Ama Addo', phone: '+233240000002', role: 'passenger',
    });
    const passengerAttempt = await json(await fetch(`${stack.baseUrl}/v1/me/momo`, {
      method: 'PUT',
      headers: { authorization: `Bearer ${passengerToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ momoNumber: '+233244000111', momoNetwork: 'mtn' }),
    }));
    assert.equal(passengerAttempt.status, 403);
  });
});

test(
  'direct mobile money payment is a self-reported, two-sided confirmation with no money movement',
  async () => {
    await withStack(async (stack) => {
      const driverToken = await signUpAs(stack, {
        id: 'driver-kwame', displayName: 'Kwame Mensah', phone: '+233240000001', role: 'driver',
      });
      const driverAuth = { authorization: `Bearer ${driverToken}`, 'content-type': 'application/json' };
      await fetch(`${stack.baseUrl}/v1/me/momo`, {
        method: 'PUT', headers: driverAuth,
        body: JSON.stringify({ momoNumber: '+233244000111', momoNetwork: 'mtn' }),
      });

      const passengerToken = await signUpAs(stack, {
        id: 'passenger-ama', displayName: 'Ama Addo', phone: '+233240000002', role: 'passenger',
      });
      const passengerAuth = { authorization: `Bearer ${passengerToken}`, 'content-type': 'application/json' };

      const reservation = await json(await fetch(`${stack.baseUrl}/v1/trips/trip-kwame/reservations`, {
        method: 'POST',
        headers: { ...passengerAuth, 'idempotency-key': 'momo-flow-001' },
        body: JSON.stringify({ seats: 1 }),
      }));
      assert.equal(reservation.status, 201);
      const reservationId = reservation.body.data.id;

      // Cannot mark paid before the driver confirms the seat.
      const tooEarly = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/mark-paid`, {
        method: 'POST', headers: passengerAuth,
      }));
      assert.equal(tooEarly.status, 409);

      const confirm = await json(await fetch(
        `${stack.baseUrl}/v1/driver/reservations/${reservationId}/confirm`,
        { method: 'POST', headers: driverAuth },
      ));
      assert.equal(confirm.status, 200);

      // The driver's momo details are now visible on the passenger's booking,
      // but only because it is confirmed - not before.
      const bookings = await json(await fetch(`${stack.baseUrl}/v1/me/reservations`, { headers: passengerAuth }));
      assert.equal(bookings.body.data[0].driverMomo.momoNumber, '+233244000111');
      assert.equal(bookings.body.data[0].paymentStatus, 'unpaid');

      const markedPaid = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/mark-paid`, {
        method: 'POST', headers: passengerAuth,
      }));
      assert.equal(markedPaid.status, 200);
      assert.equal(markedPaid.body.data.paymentStatus, 'passenger_marked_paid');

      // Replaying the same mark-paid call is idempotent, not an error.
      const replay = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/mark-paid`, {
        method: 'POST', headers: passengerAuth,
      }));
      assert.equal(replay.status, 200);
      assert.equal(replay.body.data.idempotentReplay, true);

      const markedReceived = await json(await fetch(
        `${stack.baseUrl}/v1/driver/reservations/${reservationId}/mark-received`,
        { method: 'POST', headers: driverAuth },
      ));
      assert.equal(markedReceived.status, 200);
      assert.equal(markedReceived.body.data.paymentStatus, 'driver_confirmed_received');

      const confirmedList = await json(await fetch(
        `${stack.baseUrl}/v1/driver/reservations/confirmed`,
        { headers: driverAuth },
      ));
      assert.equal(confirmedList.body.data[0].paymentStatus, 'driver_confirmed_received');
    });
  },
);

test('only the booking\'s own passenger or trip\'s own driver may self-report payment on it', async () => {
  await withStack(async (stack) => {
    const driverToken = await signUpAs(stack, {
      id: 'driver-kwame', displayName: 'Kwame Mensah', phone: '+233240000001', role: 'driver',
    });
    const driverAuth = { authorization: `Bearer ${driverToken}`, 'content-type': 'application/json' };
    const passengerToken = await signUpAs(stack, {
      id: 'passenger-ama', displayName: 'Ama Addo', phone: '+233240000002', role: 'passenger',
    });
    const passengerAuth = { authorization: `Bearer ${passengerToken}`, 'content-type': 'application/json' };
    const otherPassengerToken = await signUpAs(stack, {
      id: 'passenger-kojo', displayName: 'Kojo B', phone: '+233240000003', role: 'passenger',
    });
    const otherPassengerAuth = { authorization: `Bearer ${otherPassengerToken}`, 'content-type': 'application/json' };
    const otherDriverToken = await signUpAs(stack, {
      id: 'driver-ama2', displayName: 'Ama Owusu', phone: '+233240000004', role: 'driver',
    });
    const otherDriverAuth = { authorization: `Bearer ${otherDriverToken}`, 'content-type': 'application/json' };

    const reservation = await json(await fetch(`${stack.baseUrl}/v1/trips/trip-kwame/reservations`, {
      method: 'POST',
      headers: { ...passengerAuth, 'idempotency-key': 'momo-ownership-001' },
      body: JSON.stringify({ seats: 1 }),
    }));
    const reservationId = reservation.body.data.id;
    await fetch(`${stack.baseUrl}/v1/driver/reservations/${reservationId}/confirm`, {
      method: 'POST', headers: driverAuth,
    });

    const wrongPassenger = await json(await fetch(`${stack.baseUrl}/v1/me/reservations/${reservationId}/mark-paid`, {
      method: 'POST', headers: otherPassengerAuth,
    }));
    assert.equal(wrongPassenger.status, 404);

    const wrongDriver = await json(await fetch(
      `${stack.baseUrl}/v1/driver/reservations/${reservationId}/mark-received`,
      { method: 'POST', headers: otherDriverAuth },
    ));
    assert.equal(wrongDriver.status, 404);
  });
});
