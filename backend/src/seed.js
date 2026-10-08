import { createPostgresPool } from './infrastructure/postgres.js';
import { runMigrations } from './infrastructure/migrations.js';
import { PostgresTripRepository } from './infrastructure/postgres-trip-repository.js';
import { PostgresUserRepository } from './infrastructure/postgres-user-repository.js';
import { AuthService } from './application/auth-service.js';

const seedTripId = '11111111-1111-4111-8111-111111111111';
const seedDriverId = 'demo-driver-kwame';
const jwtSecret = process.env.JWT_SECRET ?? 'yenko-local-development-only-secret-do-not-use-in-production';
const pool = createPostgresPool({ connectionString: process.env.DATABASE_URL });

/** Ensures a user is in the system group for a role (looked up by role), idempotently. */
async function ensureGroupMembership(userId, role) {
  const group = await pool.query('SELECT id FROM groups WHERE role = $1 AND is_system', [role]);
  if (!group.rowCount) throw new Error(`System group for role "${role}" is missing; run migrations first.`);
  await pool.query(
    'INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
    [group.rows[0].id, userId],
  );
}

try {
  await runMigrations(pool);

  const userRepository = new PostgresUserRepository({ pool });
  const authService = new AuthService({ userRepository, jwtSecret });

  // Seed login accounts for local testing. Interactive sign-in uses the
  // username + password; the numeric quickPin is stored separately. Idempotent
  // and self-healing: rerunning updates credentials in place on existing rows
  // (including the pre-auth `demo-driver-kwame` row) rather than duplicating
  // users. These credentials are well-known and must never exist outside local/dev.
  const bcrypt = (await import('bcryptjs')).default;
  const seedAccounts = [
    { id: seedDriverId, displayName: 'Kwame Mensah', username: 'tst-driver', password: 'DRPassw0rd02', quickPin: '246800', role: 'driver' },
    { displayName: 'Test Rider', username: 'tst-rider', password: 'RIPasswo0rd02', quickPin: '246800', role: 'passenger' },
    { displayName: 'YɛnKɔ Admin', username: 'ladmin', password: 'Etsh1$@ydc', quickPin: '693058', role: 'super_admin' },
  ];
  for (const account of seedAccounts) {
    let userId;
    const passwordHash = await bcrypt.hash(account.password, 10);
    const quickPinHash = await bcrypt.hash(account.quickPin, 10);
    const existingByUsername = await userRepository.findByUsername(account.username);
    const existingById = account.id ? await userRepository.findById(account.id) : null;
    const existing = existingByUsername ?? existingById;

    if (existing) {
      // Update credentials in place so pre-existing rows pick up the primary
      // password without requiring a database reset.
      userId = existing.id;
      await pool.query(
        'UPDATE users SET username = $2, password_hash = $3, pin_hash = $4 WHERE id = $1',
        [userId, account.username, passwordHash, quickPinHash],
      );
      await ensureGroupMembership(userId, 'passenger');
      console.log(`Updated ${account.role} account ${account.username} (password + quick PIN).`);
    } else {
      const result = await authService.signup({
        id: account.id,
        displayName: account.displayName,
        username: account.username,
        password: account.password,
        quickPin: account.quickPin,
        role: account.role,
      });
      userId = result.user.id;
      console.log(`Seeded ${account.role} account ${account.username} (password + quick PIN).`);
    }
    // Runs every time so a prior partial run can heal its role-group assignment.
    await ensureGroupMembership(userId, account.role);
    if (account.role === 'super_admin') {
      // The seeded administrator is a Super Admin (as in Onboard) rather than a
      // plain Admin; drop the earlier plain-admin membership this account had.
      await pool.query(
        `DELETE FROM group_members WHERE user_id = $1
         AND group_id IN (SELECT id FROM groups WHERE role = 'admin' AND is_system)`,
        [userId],
      );
    }
  }

  const existingTrip = await pool.query('SELECT 1 FROM trips WHERE id = $1', [seedTripId]);
  if (existingTrip.rowCount) {
    // Keep the demo trip bookable: once its departure has passed, move it to
    // later today so a fresh rider always has something to find.
    const refreshed = await pool.query(
      `UPDATE trips SET departure_at = now() + interval '2 hours', updated_at = now()
       WHERE id = $1 AND status = 'open' AND departure_at < now()`,
      [seedTripId],
    );
    console.log(refreshed.rowCount ? 'Refreshed the development seed trip departure.' : 'Development seed trip already exists.');
  } else {
    const repository = new PostgresTripRepository({ pool });
    await repository.create({
      id: seedTripId,
      driver: {
        id: seedDriverId, displayName: 'Kwame Mensah', rating: 4.8,
        completedTrips: 32, verificationStatus: 'demo',
      },
      vehicle: { description: 'Toyota Corolla', verificationStatus: 'demo' },
      from: 'East Legon Hills', to: 'Circle', pickupJunction: 'Madina Market junction',
      departureAt: new Date(Date.now() + 30 * 60_000).toISOString(),
      seatsAvailable: 3, pricePerSeat: 15, isWomenOnly: false, status: 'open',
    });
    console.log('Inserted development-only seed trip.');
  }
} finally {
  await pool.end();
}
