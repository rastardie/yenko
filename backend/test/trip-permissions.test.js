import assert from 'node:assert/strict';
import test from 'node:test';

import { TripService } from '../src/application/trip-service.js';

const repository = {
  listBookings: async () => [],
  listDriverSummaries: async () => [],
  cancelReservation: async () => ({ reason: 'reservation_not_found' }),
};
const service = new TripService({ tripRepository: repository });

const rider = (permissions) => ({ subject: 'rider-1', role: 'passenger', ...(permissions ? { permissions } : {}) });
const driver = (permissions) => ({ subject: 'driver-1', role: 'driver', ...(permissions ? { permissions } : {}) });

test('rider actions need both the passenger role and the matching group permission', async () => {
  await assert.rejects(service.listBookings({ actor: rider(['reservations:book']) }), /reservations:view_own/);
  assert.deepEqual(await service.listBookings({ actor: rider(['reservations:view_own']) }), []);
  await assert.rejects(
    service.cancelBooking({ actor: rider(['reservations:view_own']), reservationId: 'x' }),
    /reservations:cancel_own/,
  );
  await assert.rejects(
    service.requestSeat({ actor: rider([]), tripId: 't', input: { seats: 1 }, idempotencyKey: 'abcdefgh' }),
    /reservations:book/,
  );
});

test('driver actions need the driver role and the matching group permission', async () => {
  await assert.rejects(service.listDriverSummaries({ actor: driver(['trips:offer']) }), /trips:manage_own/);
  assert.deepEqual(await service.listDriverSummaries({ actor: driver(['trips:manage_own']) }), []);
  await assert.rejects(service.postTrip({ actor: driver(['trips:manage_own']), input: {} }), /trips:offer/);
});

test('the role is still required even when the permission is held', async () => {
  await assert.rejects(
    service.listDriverSummaries({ actor: { subject: 'x', role: 'passenger', permissions: ['trips:manage_own'] } }),
    /driver role is required/,
  );
});

test('development actors without a permission list are checked by role only', async () => {
  assert.deepEqual(await service.listBookings({ actor: rider() }), []);
  assert.deepEqual(await service.listDriverSummaries({ actor: driver() }), []);
});
