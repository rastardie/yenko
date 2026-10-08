import { randomUUID } from 'node:crypto';

const clone = (value) => structuredClone(value);

const selectTrip = `
  SELECT t.id, t.driver_id, u.display_name AS driver_display_name,
         t.driver_rating, t.driver_completed_trips, t.driver_verification_status,
         t.vehicle_description, t.vehicle_verification_status,
         t.origin_name, t.destination_name, t.pickup_junction, t.departure_at,
         t.seats_available, t.price_per_seat, t.is_women_only, t.status, t.created_at
  FROM trips t
  JOIN users u ON u.id = t.driver_id
`;

const tripJson = `jsonb_build_object(
  'id', t.id,
  'driver', jsonb_build_object(
    'id', t.driver_id,
    'displayName', u.display_name,
    'rating', t.driver_rating,
    'completedTrips', t.driver_completed_trips,
    'verificationStatus', t.driver_verification_status
  ),
  'vehicle', jsonb_build_object(
    'description', t.vehicle_description,
    'verificationStatus', t.vehicle_verification_status
  ),
  'from', t.origin_name,
  'to', t.destination_name,
  'pickupJunction', t.pickup_junction,
  'departureAt', t.departure_at,
  'seatsAvailable', t.seats_available,
  'pricePerSeat', t.price_per_seat,
  'isWomenOnly', t.is_women_only,
  'status', t.status,
  'createdAt', t.created_at
)`;

function toTrip(row) {
  return {
    id: row.id,
    driver: {
      id: row.driver_id,
      displayName: row.driver_display_name,
      rating: Number(row.driver_rating),
      completedTrips: row.driver_completed_trips,
      verificationStatus: row.driver_verification_status,
    },
    vehicle: {
      description: row.vehicle_description,
      verificationStatus: row.vehicle_verification_status,
    },
    from: row.origin_name,
    to: row.destination_name,
    pickupJunction: row.pickup_junction,
    departureAt: new Date(row.departure_at).toISOString(),
    seatsAvailable: row.seats_available,
    pricePerSeat: row.price_per_seat,
    isWomenOnly: row.is_women_only,
    status: row.status,
    createdAt: new Date(row.created_at).toISOString(),
  };
}

function toBooking(row) {
  return {
    id: row.id,
    tripId: row.trip_id,
    seats: row.seats,
    status: row.status,
    createdAt: new Date(row.created_at).toISOString(),
    trip: row.trip,
  };
}

function toNotification(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    tripId: row.trip_id,
    reservationId: row.reservation_id,
    read: row.read_at !== null,
    createdAt: new Date(row.created_at).toISOString(),
  };
}

async function upsertUser(client, { id, displayName }) {
  await client.query(
    `INSERT INTO users (id, display_name) VALUES ($1, $2)
     ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, updated_at = now()`,
    [id, displayName],
  );
}

/**
 * Makes sure a users row exists for the actor without touching an existing one.
 * (Booking a seat used to overwrite the rider's real name with a placeholder.)
 */
async function ensureUser(client, { id, displayName }) {
  await client.query(
    'INSERT INTO users (id, display_name) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING',
    [id, displayName],
  );
}

async function createNotification(client, { recipientId, type, title, body, tripId = null, reservationId = null }) {
  const result = await client.query(
    `INSERT INTO notifications (recipient_id, type, title, body, trip_id, reservation_id)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [recipientId, type, title, body, tripId, reservationId],
  );
  await client.query(
    `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
     VALUES ('notification.created', 'notification', $1, $2::jsonb)`,
    [result.rows[0].id, JSON.stringify({ notificationId: result.rows[0].id, recipientId, type })],
  );
}

export class PostgresTripRepository {
  constructor({ pool }) {
    this.pool = pool;
  }

  async close() {
    await this.pool.end();
  }

  async listOpen({ womenOnly = false } = {}) {
    const { rows } = await this.pool.query(
      `${selectTrip}
       WHERE t.status = 'open' AND t.seats_available > 0 AND t.departure_at > now()
         AND ($1::boolean = false OR t.is_women_only = true)
       ORDER BY t.departure_at ASC`,
      [womenOnly],
    );
    return rows.map(toTrip);
  }

  async create(trip) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await upsertUser(client, { id: trip.driver.id, displayName: trip.driver.displayName });
      await client.query(
        `INSERT INTO trips (
          id, driver_id, driver_rating, driver_completed_trips, driver_verification_status,
          vehicle_description, vehicle_verification_status, origin_name, destination_name,
          pickup_junction, departure_at, seats_available, price_per_seat, is_women_only, status
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
        )`,
        [
          trip.id, trip.driver.id, trip.driver.rating, trip.driver.completedTrips,
          trip.driver.verificationStatus, trip.vehicle.description, trip.vehicle.verificationStatus,
          trip.from, trip.to, trip.pickupJunction, trip.departureAt, trip.seatsAvailable,
          trip.pricePerSeat, trip.isWomenOnly, trip.status,
        ],
      );
      const inserted = await client.query(`${selectTrip} WHERE t.id = $1`, [trip.id]);
      await client.query(
        `INSERT INTO audit_events (actor_id, action, aggregate_type, aggregate_id, metadata)
         VALUES ($1, 'trip.created', 'trip', $2, $3::jsonb)`,
        [trip.driver.id, trip.id, JSON.stringify({ isWomenOnly: trip.isWomenOnly })],
      );
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('trip.created', 'trip', $1, $2::jsonb)`,
        [trip.id, JSON.stringify({ tripId: trip.id })],
      );
      await createNotification(client, {
        recipientId: trip.driver.id,
        type: 'trip.created',
        title: 'Trip published',
        body: `${trip.from} to ${trip.to} is now open for seat requests.`,
        tripId: trip.id,
      });
      await client.query('COMMIT');
      return toTrip(inserted.rows[0]);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async reserve({ tripId, passengerId, seats, idempotencyKey }) {
    const client = await this.pool.connect();
    const route = `/v1/trips/${tripId}/reservations`;
    try {
      await client.query('BEGIN');
      const replay = await client.query(
        `SELECT r.id, r.trip_id, r.seats, r.status, r.created_at
         FROM idempotency_keys i JOIN reservations r ON r.id = i.reservation_id
         WHERE i.actor_id = $1 AND i.route = $2 AND i.key = $3`,
        [passengerId, route, idempotencyKey],
      );
      if (replay.rowCount) {
        await client.query('COMMIT');
        return { reservation: this.#toReservation(replay.rows[0]), replayed: true };
      }

      const lockedTrip = await client.query(`${selectTrip} WHERE t.id = $1 FOR UPDATE`, [tripId]);
      if (!lockedTrip.rowCount) {
        await client.query('ROLLBACK');
        return { reason: 'trip_not_found' };
      }
      const trip = toTrip(lockedTrip.rows[0]);
      if (trip.status !== 'open' || new Date(trip.departureAt) <= new Date()) {
        await client.query('ROLLBACK');
        return { reason: 'trip_unavailable' };
      }
      if (trip.driver.id === passengerId) {
        await client.query('ROLLBACK');
        return { reason: 'own_trip' };
      }
      if (trip.seatsAvailable < seats) {
        await client.query('ROLLBACK');
        return { reason: 'insufficient_seats' };
      }

      await ensureUser(client, { id: passengerId, displayName: 'YɛnKɔ passenger' });
      const reservationId = randomUUID();
      const reservationResult = await client.query(
        `INSERT INTO reservations (id, trip_id, passenger_id, seats, status)
         VALUES ($1, $2, $3, $4, 'requested')
         RETURNING id, trip_id, seats, status, created_at`,
        [reservationId, tripId, passengerId, seats],
      );
      await client.query('UPDATE trips SET seats_available = seats_available - $1, updated_at = now() WHERE id = $2', [seats, tripId]);
      await client.query(
        `INSERT INTO idempotency_keys (actor_id, route, key, reservation_id)
         VALUES ($1, $2, $3, $4)`,
        [passengerId, route, idempotencyKey, reservationId],
      );
      await client.query(
        `INSERT INTO audit_events (actor_id, action, aggregate_type, aggregate_id, metadata)
         VALUES ($1, 'reservation.requested', 'reservation', $2, $3::jsonb)`,
        [passengerId, reservationId, JSON.stringify({ tripId, seats })],
      );
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('reservation.requested', 'reservation', $1, $2::jsonb)`,
        [reservationId, JSON.stringify({ reservationId, tripId, seats })],
      );
      await createNotification(client, {
        recipientId: passengerId,
        type: 'reservation.requested',
        title: 'Seat request received',
        body: `${seats} seat request sent for ${trip.from} to ${trip.to}.`,
        tripId,
        reservationId,
      });
      await createNotification(client, {
        recipientId: trip.driver.id,
        type: 'driver.reservation.requested',
        title: 'New seat request',
        body: `A passenger requested ${seats} seat for ${trip.from} to ${trip.to}.`,
        tripId,
        reservationId,
      });
      await client.query('COMMIT');
      return { reservation: this.#toReservation(reservationResult.rows[0]), replayed: false };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async cancelReservation({ reservationId, passengerId }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const lockedReservation = await client.query(
        `SELECT r.id, r.trip_id, r.passenger_id, r.seats, r.status, r.created_at,
                t.status AS trip_status, t.departure_at, t.driver_id,
                t.origin_name, t.destination_name
         FROM reservations r
         JOIN trips t ON t.id = r.trip_id
         WHERE r.id = $1 AND r.passenger_id = $2
         FOR UPDATE OF r, t`,
        [reservationId, passengerId],
      );
      if (!lockedReservation.rowCount) {
        await client.query('ROLLBACK');
        return { reason: 'reservation_not_found' };
      }

      const reservation = lockedReservation.rows[0];
      if (reservation.status === 'cancelled') {
        await client.query('COMMIT');
        return { reservation: this.#toReservation(reservation), replayed: true };
      }
      if (
        reservation.status !== 'requested' ||
        reservation.trip_status !== 'open' ||
        new Date(reservation.departure_at) <= new Date()
      ) {
        await client.query('ROLLBACK');
        return { reason: 'reservation_not_cancellable' };
      }

      const cancelled = await client.query(
        `UPDATE reservations SET status = 'cancelled', updated_at = now()
         WHERE id = $1
         RETURNING id, trip_id, seats, status, created_at`,
        [reservationId],
      );
      await client.query(
        'UPDATE trips SET seats_available = seats_available + $1, updated_at = now() WHERE id = $2',
        [reservation.seats, reservation.trip_id],
      );
      await client.query(
        `INSERT INTO audit_events (actor_id, action, aggregate_type, aggregate_id, metadata)
         VALUES ($1, 'reservation.cancelled', 'reservation', $2, $3::jsonb)`,
        [passengerId, reservationId, JSON.stringify({ tripId: reservation.trip_id, seats: reservation.seats })],
      );
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('reservation.cancelled', 'reservation', $1, $2::jsonb)`,
        [reservationId, JSON.stringify({ reservationId, tripId: reservation.trip_id, seats: reservation.seats })],
      );
      await createNotification(client, {
        recipientId: passengerId,
        type: 'reservation.cancelled',
        title: 'Seat request cancelled',
        body: `Your ${reservation.seats} seat request for ${reservation.origin_name} to ${reservation.destination_name} was cancelled.`,
        tripId: reservation.trip_id,
        reservationId,
      });
      await createNotification(client, {
        recipientId: reservation.driver_id,
        type: 'driver.reservation.cancelled',
        title: 'Seat request cancelled',
        body: `A passenger cancelled ${reservation.seats} requested seat for ${reservation.origin_name} to ${reservation.destination_name}.`,
        tripId: reservation.trip_id,
        reservationId,
      });
      await client.query('COMMIT');
      return { reservation: this.#toReservation(cancelled.rows[0]), replayed: false };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async listBookings({ passengerId }) {
    const { rows } = await this.pool.query(
      `SELECT r.id, r.trip_id, r.seats, r.status, r.created_at, ${tripJson} AS trip
       FROM reservations r
       JOIN trips t ON t.id = r.trip_id
       JOIN users u ON u.id = t.driver_id
       WHERE r.passenger_id = $1
       ORDER BY r.created_at DESC`,
      [passengerId],
    );
    return rows.map(toBooking);
  }

  async listNotifications({ recipientId }) {
    const { rows } = await this.pool.query(
      `SELECT id, type, title, body, trip_id, reservation_id, read_at, created_at
       FROM notifications WHERE recipient_id = $1 ORDER BY created_at DESC`,
      [recipientId],
    );
    return rows.map(toNotification);
  }

  async markNotificationsRead({ recipientId }) {
    const result = await this.pool.query(
      'UPDATE notifications SET read_at = now() WHERE recipient_id = $1 AND read_at IS NULL',
      [recipientId],
    );
    return result.rowCount;
  }

  async listDriverSummaries({ driverId }) {
    const { rows } = await this.pool.query(
      `SELECT ${tripJson} AS trip,
              COALESCE(totals.seats_booked, 0)::int AS seats_booked,
              COALESCE(totals.booking_count, 0)::int AS booking_count
       FROM trips t
       JOIN users u ON u.id = t.driver_id
       LEFT JOIN (
         SELECT trip_id, SUM(seats)::int AS seats_booked, COUNT(*)::int AS booking_count
         FROM reservations WHERE status IN ('requested', 'confirmed') GROUP BY trip_id
       ) totals ON totals.trip_id = t.id
       WHERE t.driver_id = $1
       ORDER BY t.departure_at ASC`,
      [driverId],
    );
    return rows.map((row) => ({
      trip: row.trip,
      seatsBooked: row.seats_booked,
      bookingCount: row.booking_count,
    }));
  }

  #toReservation(row) {
    return clone({
      id: row.id,
      tripId: row.trip_id,
      seats: row.seats,
      status: row.status,
      createdAt: new Date(row.created_at).toISOString(),
    });
  }
}
