import { randomUUID } from 'node:crypto';

const copy = (value) => structuredClone(value);

export class InMemoryTripRepository {
  #trips = new Map();
  #reservationsByIdempotencyKey = new Map();
  #reservations = new Map();
  #notifications = [];

  constructor(seedTrips = []) {
    for (const trip of seedTrips) this.#trips.set(trip.id, copy(trip));
  }

  async listOpen({ womenOnly = false } = {}) {
    return [...this.#trips.values()]
      .filter((trip) => trip.status === 'open' && trip.seatsAvailable > 0)
      .filter((trip) => !womenOnly || trip.isWomenOnly)
      .sort((left, right) => left.departureAt.localeCompare(right.departureAt))
      .map(copy);
  }

  async create(trip) {
    this.#trips.set(trip.id, copy(trip));
    this.#createNotification({
      recipientId: trip.driver.id,
      type: 'trip.created',
      title: 'Trip published',
      body: `${trip.from} to ${trip.to} is now open for seat requests.`,
      tripId: trip.id,
    });
    return copy(trip);
  }

  async reserve({ tripId, passengerId, seats, idempotencyKey }) {
    const key = `${passengerId}:${tripId}:${idempotencyKey}`;
    const existing = this.#reservationsByIdempotencyKey.get(key);
    if (existing) return { reservation: copy(existing), replayed: true };

    const trip = this.#trips.get(tripId);
    if (!trip) return { reason: 'trip_not_found' };
    if (trip.status !== 'open') return { reason: 'trip_unavailable' };
    if (trip.driver.id === passengerId) return { reason: 'own_trip' };
    if (trip.seatsAvailable < seats) return { reason: 'insufficient_seats' };

    trip.seatsAvailable -= seats;
    const reservation = {
      id: randomUUID(),
      tripId,
      passengerId,
      seats,
      status: 'requested',
      createdAt: new Date().toISOString(),
    };
    this.#reservationsByIdempotencyKey.set(key, reservation);
    this.#reservations.set(reservation.id, reservation);
    this.#createNotification({
      recipientId: passengerId,
      type: 'reservation.requested',
      title: 'Seat request received',
      body: `${seats} seat request sent for ${trip.from} to ${trip.to}.`,
      tripId,
      reservationId: reservation.id,
    });
    this.#createNotification({
      recipientId: trip.driver.id,
      type: 'driver.reservation.requested',
      title: 'New seat request',
      body: `A passenger requested ${seats} seat for ${trip.from} to ${trip.to}.`,
      tripId,
      reservationId: reservation.id,
    });
    return { reservation: copy(reservation), replayed: false };
  }

  async cancelReservation({ reservationId, passengerId }) {
    const reservation = this.#reservations.get(reservationId);
    if (!reservation || reservation.passengerId !== passengerId) {
      return { reason: 'reservation_not_found' };
    }
    if (reservation.status === 'cancelled') {
      return { reservation: copy(reservation), replayed: true };
    }

    const trip = this.#trips.get(reservation.tripId);
    if (
      reservation.status !== 'requested' ||
      !trip ||
      trip.status !== 'open' ||
      new Date(trip.departureAt) <= new Date()
    ) {
      return { reason: 'reservation_not_cancellable' };
    }

    reservation.status = 'cancelled';
    trip.seatsAvailable += reservation.seats;
    this.#createNotification({
      recipientId: passengerId,
      type: 'reservation.cancelled',
      title: 'Seat request cancelled',
      body: `Your ${reservation.seats} seat request for ${trip.from} to ${trip.to} was cancelled.`,
      tripId: trip.id,
      reservationId,
    });
    return { reservation: copy(reservation), replayed: false };
  }

  async listBookings({ passengerId }) {
    return [...this.#reservations.values()]
      .filter((reservation) => reservation.passengerId === passengerId)
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
      .map((reservation) => ({ ...copy(reservation), trip: copy(this.#trips.get(reservation.tripId)) }));
  }

  async listNotifications({ recipientId }) {
    return this.#notifications
      .filter((notification) => notification.recipientId === recipientId)
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
      .map(({ recipientId: _recipientId, ...notification }) => copy(notification));
  }

  async markNotificationsRead({ recipientId }) {
    let updated = 0;
    for (const notification of this.#notifications) {
      if (notification.recipientId === recipientId && !notification.read) {
        notification.read = true;
        updated += 1;
      }
    }
    return updated;
  }

  async listDriverSummaries({ driverId }) {
    return [...this.#trips.values()]
      .filter((trip) => trip.driver.id === driverId)
      .sort((left, right) => left.departureAt.localeCompare(right.departureAt))
      .map((trip) => {
        const bookings = [...this.#reservations.values()].filter(
          (reservation) => reservation.tripId === trip.id && ['requested', 'confirmed'].includes(reservation.status),
        );
        return {
          trip: copy(trip),
          seatsBooked: bookings.reduce((total, reservation) => total + reservation.seats, 0),
          bookingCount: bookings.length,
        };
      });
  }

  /** Pending (status 'requested') reservations across every trip this driver owns. */
  async listDriverPendingReservations({ driverId }) {
    const ownTripIds = new Set(
      [...this.#trips.values()].filter((trip) => trip.driver.id === driverId).map((trip) => trip.id),
    );
    return [...this.#reservations.values()]
      .filter((reservation) => reservation.status === 'requested' && ownTripIds.has(reservation.tripId))
      .sort((left, right) => left.createdAt.localeCompare(right.createdAt))
      .map((reservation) => ({ ...copy(reservation), trip: copy(this.#trips.get(reservation.tripId)) }));
  }

  /**
   * Confirms a pending reservation, but only when its trip belongs to
   * [driverId] — the ownership check a driver needs that the admin
   * equivalent (which may act on anyone's booking) does not.
   */
  async confirmDriverReservation({ reservationId, driverId }) {
    const reservation = this.#reservations.get(reservationId);
    if (!reservation) return { reason: 'reservation_not_found' };
    const trip = this.#trips.get(reservation.tripId);
    if (!trip || trip.driver.id !== driverId) return { reason: 'reservation_not_found' };
    if (reservation.status === 'confirmed') return { reservation: copy(reservation), replayed: true };
    if (reservation.status !== 'requested' || trip.status !== 'open') {
      return { reason: 'reservation_not_pending' };
    }

    reservation.status = 'confirmed';
    this.#createNotification({
      recipientId: reservation.passengerId,
      type: 'reservation.confirmed',
      title: 'Seat confirmed',
      body: `Your ${reservation.seats} seat for ${trip.from} to ${trip.to} is confirmed.`,
      tripId: trip.id,
      reservationId,
    });
    return { reservation: copy(reservation), replayed: false };
  }

  /**
   * Declines (cancels) a pending reservation, but only when its trip
   * belongs to [driverId]. Releases the held seats back to the trip, same
   * as a passenger-initiated cancellation.
   */
  async declineDriverReservation({ reservationId, driverId }) {
    const reservation = this.#reservations.get(reservationId);
    if (!reservation) return { reason: 'reservation_not_found' };
    const trip = this.#trips.get(reservation.tripId);
    if (!trip || trip.driver.id !== driverId) return { reason: 'reservation_not_found' };
    if (reservation.status === 'cancelled') return { reservation: copy(reservation), replayed: true };
    if (reservation.status !== 'requested') return { reason: 'reservation_not_pending' };

    reservation.status = 'cancelled';
    trip.seatsAvailable += reservation.seats;
    this.#createNotification({
      recipientId: reservation.passengerId,
      type: 'reservation.declined',
      title: 'Seat request declined',
      body: `Your ${reservation.seats} seat request for ${trip.from} to ${trip.to} was declined by the driver.`,
      tripId: trip.id,
      reservationId,
    });
    return { reservation: copy(reservation), replayed: false };
  }

  #createNotification({ recipientId, type, title, body, tripId = null, reservationId = null }) {
    this.#notifications.push({
      id: randomUUID(), recipientId, type, title, body, tripId, reservationId,
      read: false, createdAt: new Date().toISOString(),
    });
  }
}
