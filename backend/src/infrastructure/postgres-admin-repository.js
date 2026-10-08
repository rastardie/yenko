import { randomUUID } from 'node:crypto';

/**
 * PostgreSQL persistence for the admin console: user and group management,
 * permissions, cross-cutting trip views, dashboard aggregates and the audit
 * trail. Every mutation writes its `audit_events` row in the same transaction.
 * All SQL is parameterized.
 */

const escapeLike = (value) => value.replace(/[\\%_]/g, (character) => `\\${character}`);

const toGroupRef = (group) => ({ id: group.id, name: group.name, role: group.role });

const toUser = (row) => ({
  id: row.id,
  displayName: row.display_name,
  username: row.username,
  phone: row.phone,
  status: row.status,
  homeArea: row.home_area,
  phoneVerified: row.phone_verified,
  createdAt: new Date(row.created_at).toISOString(),
  groups: (row.groups ?? []).map(toGroupRef),
  roles: [...new Set((row.groups ?? []).map((group) => group.role).filter(Boolean))],
});

const userSelect = `
  SELECT u.id, u.display_name, u.username, u.phone, u.status, u.home_area,
         u.phone_verified, u.created_at,
         COALESCE(
           json_agg(json_build_object('id', g.id, 'name', g.name, 'role', g.role) ORDER BY g.name)
             FILTER (WHERE g.id IS NOT NULL),
           '[]'::json
         ) AS groups
  FROM users u
  LEFT JOIN group_members gm ON gm.user_id = u.id
  LEFT JOIN groups g ON g.id = gm.group_id
`;

const toGroup = (row) => ({
  id: row.id,
  name: row.name,
  role: row.role,
  description: row.description,
  isSystem: row.is_system,
  memberCount: row.member_count,
  permissions: row.permissions ?? [],
});

const groupSelect = `
  SELECT g.id, g.name, g.role, g.description, g.is_system,
         (SELECT count(*)::int FROM group_members gm WHERE gm.group_id = g.id) AS member_count,
         COALESCE(
           (SELECT array_agg(p.resource || ':' || p.action ORDER BY p.resource, p.action)
            FROM group_permissions gp JOIN permissions p ON p.id = gp.permission_id
            WHERE gp.group_id = g.id),
           ARRAY[]::text[]
         ) AS permissions
  FROM groups g
`;

const toTrip = (row) => ({
  id: row.id,
  driver: { id: row.driver_id, displayName: row.driver_display_name },
  from: row.origin_name,
  to: row.destination_name,
  pickupJunction: row.pickup_junction,
  departureAt: new Date(row.departure_at).toISOString(),
  seatsAvailable: row.seats_available,
  pricePerSeat: row.price_per_seat,
  isWomenOnly: row.is_women_only,
  status: row.status,
  seatsBooked: row.seats_booked ?? 0,
  bookingCount: row.booking_count ?? 0,
  createdAt: new Date(row.created_at).toISOString(),
});

const tripSelect = `
  SELECT t.id, t.driver_id, u.display_name AS driver_display_name,
         t.origin_name, t.destination_name, t.pickup_junction, t.departure_at,
         t.seats_available, t.price_per_seat, t.is_women_only, t.status, t.created_at,
         COALESCE(r.seats_booked, 0)::int AS seats_booked,
         COALESCE(r.booking_count, 0)::int AS booking_count
  FROM trips t
  JOIN users u ON u.id = t.driver_id
  LEFT JOIN (
    SELECT trip_id, SUM(seats)::int AS seats_booked, COUNT(*)::int AS booking_count
    FROM reservations WHERE status IN ('requested', 'confirmed') GROUP BY trip_id
  ) r ON r.trip_id = t.id
`;

async function insertAudit(client, audit, aggregateType, aggregateId, extraMetadata = {}) {
  await client.query(
    `INSERT INTO audit_events (actor_id, action, aggregate_type, aggregate_id, metadata)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [audit.actorId, audit.action, aggregateType, String(aggregateId), JSON.stringify({ ...audit.metadata, ...extraMetadata })],
  );
}

async function createNotification(client, { recipientId, type, title, body, tripId = null, reservationId = null }) {
  const result = await client.query(
    `INSERT INTO notifications (recipient_id, type, title, body, trip_id, reservation_id)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [recipientId, type, title, body, tripId, reservationId],
  );
  await client.query(
    `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
     VALUES ('notification.created', 'notification', $1, $2::jsonb)`,
    [result.rows[0].id, JSON.stringify({ notificationId: result.rows[0].id, recipientId, type })],
  );
}

export class PostgresAdminRepository {
  constructor({ pool }) {
    this.pool = pool;
  }

  async #inTransaction(work) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  // ----- Dashboard -----

  async dashboard() {
    const [users, trips, reservations, groups] = await Promise.all([
      this.pool.query(`
        SELECT count(*)::int AS total,
               count(*) FILTER (WHERE status = 'active')::int AS active,
               count(*) FILTER (WHERE status = 'suspended')::int AS suspended,
               count(*) FILTER (WHERE status = 'pending')::int AS pending,
               count(*) FILTER (WHERE created_at > now() - interval '7 days')::int AS new_last_7_days
        FROM users`),
      this.pool.query(`
        SELECT count(*)::int AS total,
               count(*) FILTER (WHERE status = 'open')::int AS open,
               count(*) FILTER (WHERE status = 'open' AND departure_at > now() AND seats_available > 0)::int AS bookable,
               count(*) FILTER (WHERE status = 'cancelled')::int AS cancelled,
               count(*) FILTER (WHERE status = 'completed')::int AS completed,
               COALESCE(SUM(seats_available) FILTER (WHERE status = 'open' AND departure_at > now()), 0)::int AS open_seats,
               count(*) FILTER (WHERE created_at > now() - interval '7 days')::int AS created_last_7_days
        FROM trips`),
      this.pool.query(`
        SELECT count(*)::int AS total,
               count(*) FILTER (WHERE status = 'requested')::int AS requested,
               count(*) FILTER (WHERE status = 'confirmed')::int AS confirmed,
               count(*) FILTER (WHERE status = 'cancelled')::int AS cancelled,
               COALESCE(SUM(seats) FILTER (WHERE status IN ('requested', 'confirmed')), 0)::int AS seats_booked,
               count(*) FILTER (WHERE created_at > now() - interval '7 days')::int AS created_last_7_days
        FROM reservations`),
      this.pool.query(`
        SELECT g.id, g.name, g.role, count(gm.user_id)::int AS members
        FROM groups g LEFT JOIN group_members gm ON gm.group_id = g.id
        GROUP BY g.id ORDER BY g.is_system DESC, g.name`),
    ]);
    const u = users.rows[0];
    const t = trips.rows[0];
    const r = reservations.rows[0];
    return {
      generatedAt: new Date().toISOString(),
      users: {
        total: u.total, active: u.active, suspended: u.suspended,
        pending: u.pending, newLast7Days: u.new_last_7_days,
      },
      trips: {
        total: t.total, open: t.open, bookable: t.bookable, cancelled: t.cancelled,
        completed: t.completed, openSeats: t.open_seats, createdLast7Days: t.created_last_7_days,
      },
      reservations: {
        total: r.total, requested: r.requested, confirmed: r.confirmed,
        cancelled: r.cancelled, seatsBooked: r.seats_booked, createdLast7Days: r.created_last_7_days,
      },
      groups: groups.rows.map((row) => ({
        id: row.id, name: row.name, role: row.role, members: row.members,
      })),
    };
  }


  // ----- Summary and metrics -----

  /** Cheap counts for the admin home screen. */
  async summary() {
    const [users, trips, bookings, groups] = await Promise.all([
      this.pool.query(`SELECT count(*) FILTER (WHERE status = 'active')::int AS active,
                              count(*) FILTER (WHERE status = 'pending')::int AS pending
                       FROM users`),
      this.pool.query(`SELECT count(*) FILTER (WHERE status = 'open')::int AS open FROM trips`),
      this.pool.query(`SELECT count(*) FILTER (WHERE status = 'requested')::int AS requested FROM reservations`),
      this.pool.query('SELECT count(*)::int AS total FROM groups'),
    ]);
    return {
      users: { active: users.rows[0].active, pending: users.rows[0].pending },
      trips: { open: trips.rows[0].open },
      bookings: { requested: bookings.rows[0].requested },
      groups: { total: groups.rows[0].total },
    };
  }

  /**
   * Operational metrics for trips departing in [from, to). All day bucketing is
   * UTC, which equals Africa/Accra (GMT, no daylight saving).
   */
  async metrics({ from, to }) {
    const range = [from, to];
    const scoped = `
      FROM trips t
      LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(r.seats), 0)::int AS reserved
        FROM reservations r WHERE r.trip_id = t.id AND r.status IN ('requested', 'confirmed')
      ) res ON true
      WHERE t.departure_at >= $1 AND t.departure_at < $2`;
    const [trips, bookings, drivers, daily, users] = await Promise.all([
      this.pool.query(
        `SELECT count(*)::int AS total,
                count(*) FILTER (WHERE t.status = 'open')::int AS open,
                count(*) FILTER (WHERE t.status = 'cancelled')::int AS cancelled,
                count(*) FILTER (WHERE t.status = 'completed')::int AS completed,
                COALESCE(SUM(t.seats_available + res.reserved) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS capacity,
                COALESCE(SUM(res.reserved) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS reserved,
                COALESCE(SUM(res.reserved * t.price_per_seat) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS fare_value
         ${scoped}`,
        range,
      ),
      this.pool.query(
        `SELECT count(*)::int AS total,
                count(*) FILTER (WHERE r.status = 'requested')::int AS requested,
                count(*) FILTER (WHERE r.status = 'confirmed')::int AS confirmed,
                count(*) FILTER (WHERE r.status = 'cancelled')::int AS cancelled,
                COALESCE(SUM(r.seats) FILTER (WHERE r.status = 'cancelled'), 0)::int AS cancelled_seats,
                count(*) FILTER (WHERE t.is_women_only)::int AS women_only
         FROM reservations r JOIN trips t ON t.id = r.trip_id
         WHERE t.departure_at >= $1 AND t.departure_at < $2`,
        range,
      ),
      this.pool.query(
        `SELECT t.driver_id, u.display_name,
                count(*)::int AS trips,
                count(*) FILTER (WHERE t.status = 'cancelled')::int AS cancelled_trips,
                COALESCE(SUM(t.seats_available + res.reserved) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS capacity,
                COALESCE(SUM(res.reserved) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS reserved
         ${scoped.replace('FROM trips t', 'FROM trips t JOIN users u ON u.id = t.driver_id')}
         GROUP BY t.driver_id, u.display_name
         ORDER BY reserved DESC, trips DESC, u.display_name
         LIMIT 10`,
        range,
      ),
      this.pool.query(
        `SELECT to_char(date_trunc('day', t.departure_at AT TIME ZONE 'UTC'), 'YYYY-MM-DD') AS day,
                count(*)::int AS trips,
                COALESCE(SUM(res.reserved) FILTER (WHERE t.status <> 'cancelled'), 0)::int AS reserved
         ${scoped}
         GROUP BY 1 ORDER BY 1`,
        range,
      ),
      this.pool.query(
        `SELECT count(*) FILTER (WHERE status = 'active')::int AS active,
                count(*) FILTER (WHERE status = 'pending')::int AS pending,
                count(*) FILTER (WHERE status = 'suspended')::int AS suspended,
                count(*) FILTER (WHERE status <> 'deleted' AND created_at >= $1 AND created_at < $2)::int AS joined,
                count(*) FILTER (WHERE status = 'active' AND EXISTS (
                  SELECT 1 FROM group_members gm JOIN groups g ON g.id = gm.group_id
                  WHERE gm.user_id = users.id AND g.role = 'driver' AND g.is_system))::int AS drivers
         FROM users`,
        range,
      ),
    ]);
    const t = trips.rows[0];
    const b = bookings.rows[0];
    const u = users.rows[0];
    return {
      range: { from: from.toISOString(), to: to.toISOString() },
      trips: {
        total: t.total, open: t.open, cancelled: t.cancelled, completed: t.completed,
        capacity: t.capacity, reserved: t.reserved,
        utilizationPct: t.capacity > 0 ? Math.round((t.reserved / t.capacity) * 100) : 0,
        fareValue: t.fare_value,
      },
      bookings: {
        total: b.total, requested: b.requested, confirmed: b.confirmed, cancelled: b.cancelled,
        cancelledSeats: b.cancelled_seats, womenOnly: b.women_only,
      },
      users: { active: u.active, pending: u.pending, suspended: u.suspended, joined: u.joined, drivers: u.drivers },
      drivers: drivers.rows.map((row) => ({
        id: row.driver_id,
        displayName: row.display_name,
        trips: row.trips,
        cancelledTrips: row.cancelled_trips,
        capacity: row.capacity,
        reserved: row.reserved,
        utilizationPct: row.capacity > 0 ? Math.round((row.reserved / row.capacity) * 100) : 0,
      })),
      daily: daily.rows.map((row) => ({ day: row.day, trips: row.trips, reserved: row.reserved })),
    };
  }

  // ----- Bookings and reports -----

  #bookingFilter(filters) {
    return {
      where: `
        WHERE ($1::timestamptz IS NULL OR t.departure_at >= $1)
          AND ($2::timestamptz IS NULL OR t.departure_at < $2)
          AND ($3::text IS NULL OR r.status = $3)
          AND ($4::boolean IS NULL OR t.is_women_only = $4)
          AND ($5::text IS NULL OR p.display_name ILIKE $5 OR p.username ILIKE $5
               OR d.display_name ILIKE $5 OR t.origin_name ILIKE $5 OR t.destination_name ILIKE $5)`,
      params: [
        filters.from ?? null,
        filters.to ?? null,
        filters.status ?? null,
        filters.womenOnly ?? null,
        filters.search ? `%${escapeLike(filters.search)}%` : null,
      ],
    };
  }

  async listBookings(filters) {
    const { where, params } = this.#bookingFilter(filters);
    const from = `
      FROM reservations r
      JOIN trips t ON t.id = r.trip_id
      JOIN users p ON p.id = r.passenger_id
      JOIN users d ON d.id = t.driver_id`;
    const [rows, totals] = await Promise.all([
      this.pool.query(
        `SELECT r.id, r.seats, r.status, r.created_at,
                t.id AS trip_id, t.origin_name, t.destination_name, t.pickup_junction,
                t.departure_at, t.status AS trip_status, t.is_women_only, t.price_per_seat,
                p.id AS passenger_id, p.display_name AS passenger_name, p.username AS passenger_username,
                d.id AS driver_id, d.display_name AS driver_name
         ${from} ${where}
         ORDER BY t.departure_at DESC, r.created_at DESC, r.id
         LIMIT $6 OFFSET $7`,
        [...params, filters.limit, filters.offset],
      ),
      this.pool.query(
        `SELECT count(*)::int AS bookings,
                count(*) FILTER (WHERE r.status = 'requested')::int AS requested,
                count(*) FILTER (WHERE r.status = 'confirmed')::int AS confirmed,
                count(*) FILTER (WHERE r.status = 'cancelled')::int AS cancelled,
                COALESCE(SUM(r.seats) FILTER (WHERE r.status IN ('requested', 'confirmed')), 0)::int AS seats,
                COALESCE(SUM(r.seats * t.price_per_seat) FILTER (WHERE r.status IN ('requested', 'confirmed')), 0)::int AS fare
         ${from} ${where}`,
        params,
      ),
    ]);
    const total = totals.rows[0];
    return {
      items: rows.rows.map((row) => ({
        id: row.id,
        seats: row.seats,
        status: row.status,
        fare: row.seats * row.price_per_seat,
        createdAt: new Date(row.created_at).toISOString(),
        trip: {
          id: row.trip_id,
          from: row.origin_name,
          to: row.destination_name,
          pickupJunction: row.pickup_junction,
          departureAt: new Date(row.departure_at).toISOString(),
          status: row.trip_status,
          isWomenOnly: row.is_women_only,
        },
        passenger: { id: row.passenger_id, displayName: row.passenger_name, username: row.passenger_username },
        driver: { id: row.driver_id, displayName: row.driver_name },
      })),
      total: total.bookings,
      totals: {
        bookings: total.bookings, requested: total.requested, confirmed: total.confirmed,
        cancelled: total.cancelled, seats: total.seats, fare: total.fare,
      },
    };
  }

  async confirmBooking(id, audit) {
    return this.#inTransaction(async (client) => {
      const locked = await client.query(
        `SELECT r.id, r.status, r.seats, r.passenger_id, r.trip_id,
                t.status AS trip_status, t.origin_name, t.destination_name
         FROM reservations r JOIN trips t ON t.id = r.trip_id
         WHERE r.id = $1 FOR UPDATE OF r, t`,
        [id],
      );
      if (!locked.rowCount) return { reason: 'booking_not_found' };
      const booking = locked.rows[0];
      if (booking.status === 'confirmed') return { replayed: true };
      if (booking.status !== 'requested') return { reason: 'booking_not_pending' };
      if (booking.trip_status !== 'open') return { reason: 'trip_not_open' };
      await client.query(`UPDATE reservations SET status = 'confirmed', updated_at = now() WHERE id = $1`, [id]);
      await createNotification(client, {
        recipientId: booking.passenger_id,
        type: 'reservation.confirmed',
        title: 'Seat confirmed',
        body: `Your ${booking.seats} seat for ${booking.origin_name} to ${booking.destination_name} is confirmed.`,
        tripId: booking.trip_id,
        reservationId: id,
      });
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('reservation.confirmed', 'reservation', $1, $2::jsonb)`,
        [id, JSON.stringify({ reservationId: id, tripId: booking.trip_id })],
      );
      await insertAudit(client, audit, 'reservation', id, { tripId: booking.trip_id });
      return { replayed: false };
    });
  }

  async cancelBooking(id, audit) {
    return this.#inTransaction(async (client) => {
      const locked = await client.query(
        `SELECT r.id, r.status, r.seats, r.passenger_id, r.trip_id,
                t.status AS trip_status, t.driver_id, t.origin_name, t.destination_name
         FROM reservations r JOIN trips t ON t.id = r.trip_id
         WHERE r.id = $1 FOR UPDATE OF r, t`,
        [id],
      );
      if (!locked.rowCount) return { reason: 'booking_not_found' };
      const booking = locked.rows[0];
      if (booking.status === 'cancelled') return { replayed: true };
      if (!['requested', 'confirmed'].includes(booking.status)) return { reason: 'booking_not_cancellable' };
      await client.query(`UPDATE reservations SET status = 'cancelled', updated_at = now() WHERE id = $1`, [id]);
      // Only an open trip gets its seats back; a cancelled trip has no inventory.
      if (booking.trip_status === 'open') {
        await client.query(
          'UPDATE trips SET seats_available = seats_available + $1, updated_at = now() WHERE id = $2',
          [booking.seats, booking.trip_id],
        );
      }
      const route = `${booking.origin_name} to ${booking.destination_name}`;
      await createNotification(client, {
        recipientId: booking.passenger_id,
        type: 'reservation.cancelled_by_staff',
        title: 'Booking cancelled',
        body: `Your ${booking.seats} seat for ${route} was cancelled by YɛnKɔ.`,
        tripId: booking.trip_id,
        reservationId: id,
      });
      await createNotification(client, {
        recipientId: booking.driver_id,
        type: 'driver.reservation.cancelled_by_staff',
        title: 'Booking cancelled',
        body: `A rider's ${booking.seats} seat for ${route} was cancelled by YɛnKɔ.`,
        tripId: booking.trip_id,
        reservationId: id,
      });
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('reservation.cancelled', 'reservation', $1, $2::jsonb)`,
        [id, JSON.stringify({ reservationId: id, tripId: booking.trip_id, seats: booking.seats })],
      );
      await insertAudit(client, audit, 'reservation', id, { tripId: booking.trip_id, seats: booking.seats });
      return { replayed: false };
    });
  }

  // ----- Approval and deletion -----

  async approveUser(id, audit) {
    return this.#inTransaction(async (client) => {
      const result = await client.query(
        `UPDATE users SET status = 'active', updated_at = now() WHERE id = $1 AND status = 'pending'`,
        [id],
      );
      if (!result.rowCount) return { reason: 'not_pending' };
      await insertAudit(client, audit, 'user', id);
      return {};
    });
  }

  async openCommitments(userId) {
    const { rows } = await this.pool.query(
      `SELECT (SELECT count(*) FROM trips WHERE driver_id = $1 AND status = 'open')::int AS open_trips,
              (SELECT count(*) FROM reservations r JOIN trips t ON t.id = r.trip_id
               WHERE r.passenger_id = $1 AND r.status IN ('requested', 'confirmed') AND t.status = 'open')::int AS open_bookings`,
      [userId],
    );
    return { openTrips: rows[0].open_trips, openBookings: rows[0].open_bookings };
  }

  /**
   * Soft delete: the account can no longer sign in and its username, phone and
   * credentials are cleared (so they can be reused), but the id and display
   * name remain so trips, bookings and the audit trail keep making sense.
   */
  async deleteUser(id, audit) {
    await this.#inTransaction(async (client) => {
      const before = await client.query('SELECT username FROM users WHERE id = $1 FOR UPDATE', [id]);
      await client.query(
        `UPDATE users SET status = 'deleted', deleted_at = now(), username = NULL, phone = NULL,
                password_hash = NULL, pin_hash = NULL, auth_version = auth_version + 1, updated_at = now()
         WHERE id = $1`,
        [id],
      );
      await client.query('UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [id]);
      await client.query('DELETE FROM group_members WHERE user_id = $1', [id]);
      await client.query('DELETE FROM otp_codes WHERE user_id = $1', [id]);
      await insertAudit(client, audit, 'user', id, { username: before.rows[0]?.username ?? null });
    });
  }

  // ----- Users -----

  async listUsers({ search, status, groupId, limit, offset }) {
    const params = [status ?? null, search ? `%${escapeLike(search)}%` : null, groupId ?? null];
    const where = `
      WHERE (($1::text IS NULL AND u.status <> 'deleted') OR u.status = $1)
        AND ($2::text IS NULL OR u.display_name ILIKE $2 OR u.username ILIKE $2 OR u.phone ILIKE $2)
        AND ($3::uuid IS NULL OR EXISTS (
          SELECT 1 FROM group_members x WHERE x.user_id = u.id AND x.group_id = $3))`;
    const [rows, count] = await Promise.all([
      this.pool.query(
        `${userSelect} ${where} GROUP BY u.id ORDER BY u.created_at DESC, u.id LIMIT $4 OFFSET $5`,
        [...params, limit, offset],
      ),
      this.pool.query(`SELECT count(*)::int AS total FROM users u ${where}`, params),
    ]);
    return { items: rows.rows.map(toUser), total: count.rows[0].total };
  }

  async getUser(id) {
    const { rows } = await this.pool.query(`${userSelect} WHERE u.id = $1 GROUP BY u.id`, [id]);
    if (!rows.length) return null;
    const user = toUser(rows[0]);
    const permissions = await this.pool.query(
      `SELECT DISTINCT p.resource || ':' || p.action AS key
       FROM group_members gm
       JOIN group_permissions gp ON gp.group_id = gm.group_id
       JOIN permissions p ON p.id = gp.permission_id
       WHERE gm.user_id = $1 ORDER BY key`,
      [id],
    );
    return { ...user, permissions: permissions.rows.map((row) => row.key) };
  }

  async updateUser(id, { displayName, homeArea }, audit) {
    await this.#inTransaction(async (client) => {
      await client.query(
        `UPDATE users SET display_name = COALESCE($2, display_name),
                          home_area = CASE WHEN $3::boolean THEN $4 ELSE home_area END,
                          updated_at = now()
         WHERE id = $1`,
        [id, displayName ?? null, homeArea !== undefined, homeArea ?? null],
      );
      await insertAudit(client, audit, 'user', id);
    });
  }

  /** Suspending bumps auth_version so every existing token stops working immediately. */
  async setUserStatus(id, status, audit) {
    await this.#inTransaction(async (client) => {
      await client.query(
        `UPDATE users SET status = $2, auth_version = auth_version + 1, updated_at = now() WHERE id = $1`,
        [id, status],
      );
      if (status !== 'active') {
        await client.query(
          'UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
          [id],
        );
      }
      await insertAudit(client, audit, 'user', id, { status });
    });
  }

  async recordUserAudit(id, audit) {
    await insertAudit(this.pool, audit, 'user', id);
  }

  // ----- Groups -----

  async listGroups() {
    const { rows } = await this.pool.query(`${groupSelect} ORDER BY g.is_system DESC, g.name`);
    return rows.map(toGroup);
  }

  async getGroup(id) {
    const { rows } = await this.pool.query(`${groupSelect} WHERE g.id = $1`, [id]);
    if (!rows.length) return null;
    const members = await this.pool.query(
      `SELECT u.id, u.display_name, u.username, u.status
       FROM group_members gm JOIN users u ON u.id = gm.user_id
       WHERE gm.group_id = $1 ORDER BY u.display_name, u.id`,
      [id],
    );
    return {
      ...toGroup(rows[0]),
      members: members.rows.map((row) => ({
        id: row.id, displayName: row.display_name, username: row.username, status: row.status,
      })),
    };
  }

  async findGroupByName(name) {
    const { rows } = await this.pool.query('SELECT id FROM groups WHERE lower(name) = lower($1)', [name]);
    return rows[0] ?? null;
  }

  async createGroup({ name, description, permissions }, audit) {
    const id = randomUUID();
    await this.#inTransaction(async (client) => {
      await client.query(
        `INSERT INTO groups (id, name, role, description, is_system) VALUES ($1, $2, NULL, $3, false)`,
        [id, name, description],
      );
      await this.#replacePermissions(client, id, permissions);
      await insertAudit(client, audit, 'group', id, { name, permissions });
    });
    return this.getGroup(id);
  }

  async updateGroup(id, { name, description }, audit) {
    await this.#inTransaction(async (client) => {
      await client.query(
        `UPDATE groups SET name = COALESCE($2, name), description = COALESCE($3, description) WHERE id = $1`,
        [id, name ?? null, description ?? null],
      );
      await insertAudit(client, audit, 'group', id);
    });
  }

  async deleteGroup(id, audit) {
    await this.#inTransaction(async (client) => {
      await client.query('DELETE FROM groups WHERE id = $1', [id]);
      await insertAudit(client, audit, 'group', id);
    });
  }

  async addMember(groupId, userId, audit) {
    await this.#inTransaction(async (client) => {
      await client.query(
        'INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [groupId, userId],
      );
      await insertAudit(client, audit, 'group', groupId, { userId });
    });
  }

  async removeMember(groupId, userId, audit) {
    await this.#inTransaction(async (client) => {
      await client.query('DELETE FROM group_members WHERE group_id = $1 AND user_id = $2', [groupId, userId]);
      await insertAudit(client, audit, 'group', groupId, { userId });
    });
  }

  async isMember(groupId, userId) {
    const { rowCount } = await this.pool.query(
      'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, userId],
    );
    return rowCount > 0;
  }

  /** Active members of the system group for a role; used to protect the last super admin. */
  async countActiveMembersOfRole(role) {
    const { rows } = await this.pool.query(
      `SELECT count(DISTINCT u.id)::int AS total
       FROM groups g
       JOIN group_members gm ON gm.group_id = g.id
       JOIN users u ON u.id = gm.user_id AND u.status = 'active'
       WHERE g.role = $1 AND g.is_system`,
      [role],
    );
    return rows[0].total;
  }

  async userIsInSystemRole(userId, role) {
    const { rowCount } = await this.pool.query(
      `SELECT 1 FROM group_members gm JOIN groups g ON g.id = gm.group_id
       WHERE gm.user_id = $1 AND g.role = $2 AND g.is_system`,
      [userId, role],
    );
    return rowCount > 0;
  }

  async setGroupPermissions(groupId, permissions, audit) {
    await this.#inTransaction(async (client) => {
      await this.#replacePermissions(client, groupId, permissions);
      await insertAudit(client, audit, 'group', groupId, { permissions });
    });
  }

  async #replacePermissions(client, groupId, keys) {
    await client.query('DELETE FROM group_permissions WHERE group_id = $1', [groupId]);
    if (!keys.length) return;
    await client.query(
      `INSERT INTO group_permissions (group_id, permission_id)
       SELECT $1, p.id FROM permissions p WHERE p.resource || ':' || p.action = ANY($2::text[])`,
      [groupId, keys],
    );
  }

  async listPermissions() {
    const { rows } = await this.pool.query(
      'SELECT resource, action, description FROM permissions ORDER BY resource, action',
    );
    return rows.map((row) => ({
      key: `${row.resource}:${row.action}`,
      resource: row.resource,
      action: row.action,
      description: row.description,
    }));
  }

  // ----- Trips -----

  async listTrips({ status, limit, offset }) {
    const params = [status ?? null];
    const [rows, count] = await Promise.all([
      this.pool.query(
        `${tripSelect} WHERE ($1::text IS NULL OR t.status = $1)
         ORDER BY t.departure_at DESC, t.id LIMIT $2 OFFSET $3`,
        [...params, limit, offset],
      ),
      this.pool.query('SELECT count(*)::int AS total FROM trips t WHERE ($1::text IS NULL OR t.status = $1)', params),
    ]);
    return { items: rows.rows.map(toTrip), total: count.rows[0].total };
  }

  async getTrip(id, { includeReservations }) {
    const { rows } = await this.pool.query(`${tripSelect} WHERE t.id = $1`, [id]);
    if (!rows.length) return null;
    const trip = toTrip(rows[0]);
    if (!includeReservations) return trip;
    const reservations = await this.pool.query(
      `SELECT r.id, r.seats, r.status, r.created_at, r.passenger_id, u.display_name
       FROM reservations r JOIN users u ON u.id = r.passenger_id
       WHERE r.trip_id = $1 ORDER BY r.created_at`,
      [id],
    );
    return {
      ...trip,
      reservations: reservations.rows.map((row) => ({
        id: row.id,
        seats: row.seats,
        status: row.status,
        createdAt: new Date(row.created_at).toISOString(),
        passenger: { id: row.passenger_id, displayName: row.display_name },
      })),
    };
  }

  /**
   * Cancels an open trip and every pending/confirmed booking on it, notifying
   * the driver and each affected rider, atomically.
   */
  async cancelTrip(id, audit) {
    return this.#inTransaction(async (client) => {
      const locked = await client.query(
        'SELECT id, driver_id, status, origin_name, destination_name FROM trips WHERE id = $1 FOR UPDATE',
        [id],
      );
      if (!locked.rowCount) return { reason: 'trip_not_found' };
      const trip = locked.rows[0];
      if (trip.status !== 'open') return { reason: 'trip_not_open' };

      await client.query(`UPDATE trips SET status = 'cancelled', updated_at = now() WHERE id = $1`, [id]);
      const affected = await client.query(
        `UPDATE reservations SET status = 'cancelled', updated_at = now()
         WHERE trip_id = $1 AND status IN ('requested', 'confirmed')
         RETURNING id, passenger_id`,
        [id],
      );
      const route = `${trip.origin_name} to ${trip.destination_name}`;
      await createNotification(client, {
        recipientId: trip.driver_id,
        type: 'trip.cancelled_by_staff',
        title: 'Trip cancelled by YɛnKɔ',
        body: `Your trip ${route} was cancelled by YɛnKɔ operations.`,
        tripId: id,
      });
      for (const reservation of affected.rows) {
        await createNotification(client, {
          recipientId: reservation.passenger_id,
          type: 'reservation.cancelled_by_staff',
          title: 'Trip cancelled',
          body: `The trip ${route} was cancelled by YɛnKɔ. Please choose another ride.`,
          tripId: id,
          reservationId: reservation.id,
        });
      }
      await client.query(
        `INSERT INTO outbox_events (event_type, aggregate_type, aggregate_id, payload)
         VALUES ('trip.cancelled', 'trip', $1, $2::jsonb)`,
        [id, JSON.stringify({ tripId: id, cancelledReservations: affected.rowCount })],
      );
      await insertAudit(client, audit, 'trip', id, { cancelledReservations: affected.rowCount });
      return { cancelledReservations: affected.rowCount };
    });
  }

  // ----- Audit -----

  async auditActions() {
    const { rows } = await this.pool.query('SELECT DISTINCT action FROM audit_events ORDER BY action');
    return rows.map((row) => row.action);
  }

  async listAudit({ action, actorId, limit, offset }) {
    const params = [action ?? null, actorId ?? null];
    const where = `WHERE ($1::text IS NULL OR a.action = $1) AND ($2::text IS NULL OR a.actor_id = $2)`;
    const [rows, count] = await Promise.all([
      this.pool.query(
        `SELECT a.id, a.actor_id, u.display_name AS actor_name, a.action, a.aggregate_type,
                a.aggregate_id, a.metadata, a.created_at
         FROM audit_events a LEFT JOIN users u ON u.id = a.actor_id
         ${where} ORDER BY a.created_at DESC, a.id LIMIT $3 OFFSET $4`,
        [...params, limit, offset],
      ),
      this.pool.query(`SELECT count(*)::int AS total FROM audit_events a ${where}`, params),
    ]);
    return {
      items: rows.rows.map((row) => ({
        id: row.id,
        actor: row.actor_id ? { id: row.actor_id, displayName: row.actor_name } : null,
        action: row.action,
        aggregateType: row.aggregate_type,
        aggregateId: row.aggregate_id,
        metadata: row.metadata,
        createdAt: new Date(row.created_at).toISOString(),
      })),
      total: count.rows[0].total,
    };
  }
}
