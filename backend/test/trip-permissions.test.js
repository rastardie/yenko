import assert from 'node:assert/strict';
import test from 'node:test';

import { TripService } from '../src/application/trip-service.js';

const repository = {
  listBookings: async () => [],
  listDriverSummaries: async () => [],
  listDriverPendingReservations: async () => [],
  listDriverConfirmedReservations: async () => [],
  cancelReservation: async () => ({ reason: 'reservation_not_found' }),
  confirmDriverReservation: async () => ({ reason: 'reservation_not_found' }),
  declineDriverReservation: async () => ({ reason: 'reservation_not_found' }),
  markPaymentSent: async () => ({ reason: 'reservation_not_found' }),
  markPaymentReceived: async () => ({ reason: 'reservation_not_found' }),
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

test('driver reservation accept/decline need the driver role and trips:manage_own', async () => {
  await assert.rejects(
    service.listDriverReservations({ actor: driver(['trips:offer']) }),
    /trips:manage_own/,
  );
  assert.deepEqual(await service.listDriverReservations({ actor: driver(['trips:manage_own']) }), []);
  await assert.rejects(
    service.confirmReservation({ actor: driver(['trips:offer']), reservationId: 'r-1' }),
    /trips:manage_own/,
  );
  await assert.rejects(
    service.declineReservation({ actor: driver(['trips:offer']), reservationId: 'r-1' }),
    /trips:manage_own/,
  );
  await assert.rejects(
    service.confirmReservation({ actor: rider(['trips:manage_own']), reservationId: 'r-1' }),
    /driver role is required/,
  );
});

test('the role is still required even when the permission is held', async () => {
  await assert.rejects(
    service.listDriverSummaries({ actor: { subject: 'x', role: 'passenger', permissions: ['trips:manage_own'] } }),
    /driver role is required/,
  );
});

test('payment self-report needs the matching role and permission on each side', async () => {
  await assert.rejects(
    service.markPaymentSent({ actor: rider(['reservations:book']), reservationId: 'r-1' }),
    /reservations:report_payment/,
  );
  await assert.rejects(
    service.markPaymentSent({ actor: driver(['reservations:report_payment']), reservationId: 'r-1' }),
    /passenger role is required/,
  );
  await assert.rejects(
    service.markPaymentReceived({ actor: driver(['trips:manage_own']), reservationId: 'r-1' }),
    /trips:confirm_payment/,
  );
  await assert.rejects(
    service.markPaymentReceived({ actor: rider(['trips:confirm_payment']), reservationId: 'r-1' }),
    /driver role is required/,
  );
  await assert.rejects(
    service.listDriverConfirmedReservations({ actor: driver(['trips:offer']) }),
    /trips:manage_own/,
  );
});

test('development actors without a permission list are checked by role only', async () => {
  assert.deepEqual(await service.listBookings({ actor: rider() }), []);
  assert.deepEqual(await service.listDriverSummaries({ actor: driver() }), []);
});
