import { randomUUID } from 'node:crypto';

import { badRequest, conflict, forbidden, notFound } from '../domain/errors.js';
import { toPublicTrip, validateSeatRequest, validateTripDraft } from '../domain/trip.js';

const requireActor = (actor) => {
  if (!actor || !actor.subject) throw forbidden('An authenticated actor is required.');
};

// The account's role says which hat it wears; its groups' permissions say
// whether that hat may do this. Development actors carry no permission list,
// so only accounts resolved from the database are checked against groups.
const requireRole = (actor, role, permission) => {
  requireActor(actor);
  if (actor.role !== role) throw forbidden(`The ${role} role is required for this action.`);
  if (Array.isArray(actor.permissions) && !actor.permissions.includes(permission)) {
    throw forbidden(`Your groups do not grant ${permission}.`);
  }
};

const toBookingResponse = (booking) => ({
  id: booking.id,
  tripId: booking.tripId,
  seats: booking.seats,
  status: booking.status,
  createdAt: booking.createdAt,
  ...(booking.trip ? { trip: toPublicTrip(booking.trip) } : {}),
});

export class TripService {
  constructor({ tripRepository, clock = () => new Date() }) {
    this.tripRepository = tripRepository;
    this.clock = clock;
  }

  async listTrips({ womenOnly }) {
    const trips = await this.tripRepository.listOpen({ womenOnly });
    return trips.map(toPublicTrip);
  }

  async postTrip({ actor, input }) {
    requireRole(actor, 'driver', 'trips:offer');
    const draft = validateTripDraft(input);
    const trip = {
      id: randomUUID(),
      driver: {
        id: actor.subject,
        displayName: actor.displayName,
        rating: 0,
        completedTrips: 0,
        verificationStatus: 'pending',
      },
      vehicle: {
        description: 'Vehicle details pending verification',
        verificationStatus: 'pending',
      },
      ...draft,
      status: 'open',
      createdAt: this.clock().toISOString(),
    };
    return toPublicTrip(await this.tripRepository.create(trip));
  }

  async requestSeat({ actor, tripId, input, idempotencyKey }) {
    requireRole(actor, 'passenger', 'reservations:book');
    if (typeof idempotencyKey !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(idempotencyKey)) {
      throw badRequest('Idempotency-Key must contain 8–128 URL-safe characters.');
    }
    const { seats } = validateSeatRequest(input);
    const result = await this.tripRepository.reserve({
      tripId,
      passengerId: actor.subject,
      seats,
      idempotencyKey,
    });
    if (result.reason === 'trip_not_found') throw notFound('Trip not found.');
    if (result.reason === 'own_trip') throw conflict('A driver cannot reserve their own trip.');
    if (result.reason === 'trip_unavailable') throw conflict('This trip is no longer available.');
    if (result.reason === 'insufficient_seats') {
      throw conflict('The requested seats are no longer available.', { available: 'fewer_than_requested' });
    }
    return result;
  }

  async cancelBooking({ actor, reservationId }) {
    requireRole(actor, 'passenger', 'reservations:cancel_own');
    const result = await this.tripRepository.cancelReservation({
      reservationId,
      passengerId: actor.subject,
    });
    if (result.reason === 'reservation_not_found') throw notFound('Booking not found.');
    if (result.reason === 'reservation_not_cancellable') {
      throw conflict('Only a pending seat request for an open, future trip can be cancelled.');
    }
    return result;
  }

  async listBookings({ actor }) {
    requireRole(actor, 'passenger', 'reservations:view_own');
    const bookings = await this.tripRepository.listBookings({ passengerId: actor.subject });
    return bookings.map(toBookingResponse);
  }

  async listNotifications({ actor }) {
    requireActor(actor);
    return this.tripRepository.listNotifications({ recipientId: actor.subject });
  }

  async markNotificationsRead({ actor }) {
    requireActor(actor);
    return this.tripRepository.markNotificationsRead({ recipientId: actor.subject });
  }

  async listDriverSummaries({ actor }) {
    requireRole(actor, 'driver', 'trips:manage_own');
    const summaries = await this.tripRepository.listDriverSummaries({ driverId: actor.subject });
    return summaries.map((summary) => ({
      trip: toPublicTrip(summary.trip),
      seatsBooked: summary.seatsBooked,
      bookingCount: summary.bookingCount,
    }));
  }
}
