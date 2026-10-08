import { randomUUID } from 'node:crypto';

const rolesForUser = async (pool, userId) => {
  const result = await pool.query(
    `SELECT DISTINCT g.role FROM group_members gm JOIN groups g ON g.id = gm.group_id
     WHERE gm.user_id = $1 AND g.role IS NOT NULL`,
    [userId],
  );
  return result.rows.map((row) => row.role);
};

const permissionsForUser = async (pool, userId) => {
  const result = await pool.query(
    `SELECT DISTINCT p.resource || ':' || p.action AS key
     FROM group_members gm
     JOIN group_permissions gp ON gp.group_id = gm.group_id
     JOIN permissions p ON p.id = gp.permission_id
     WHERE gm.user_id = $1
     ORDER BY key`,
    [userId],
  );
  return result.rows.map((row) => row.key);
};

/** Persists users, group membership, sessions, and OTP codes behind simple parameterized SQL. */
export class PostgresUserRepository {
  constructor({ pool }) {
    this.pool = pool;
  }

  async findByPhone(phone) {
    const result = await this.pool.query('SELECT * FROM users WHERE phone = $1', [phone]);
    return result.rows[0] ?? null;
  }

  async findByUsername(username) {
    const result = await this.pool.query('SELECT * FROM users WHERE username = $1', [username]);
    return result.rows[0] ?? null;
  }

  async findByEmail(email) {
    const result = await this.pool.query('SELECT * FROM users WHERE email = $1', [email]);
    return result.rows[0] ?? null;
  }

  async findIdentity(provider, providerUid) {
    const result = await this.pool.query(
      'SELECT * FROM auth_identities WHERE provider = $1 AND provider_uid = $2',
      [provider, providerUid],
    );
    return result.rows[0] ?? null;
  }

  async createIdentity({ userId, provider, providerUid, email = null, emailVerified = false }) {
    await this.pool.query(
      `INSERT INTO auth_identities (user_id, provider, provider_uid, email, email_verified)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (provider, provider_uid) DO NOTHING`,
      [userId, provider, providerUid, email, emailVerified],
    );
  }

  async markEmailVerified(userId) {
    await this.pool.query('UPDATE users SET email_verified = true WHERE id = $1', [userId]);
  }

  async findById(id) {
    const result = await this.pool.query('SELECT * FROM users WHERE id = $1', [id]);
    return result.rows[0] ?? null;
  }

  async rolesForUser(userId) {
    return rolesForUser(this.pool, userId);
  }

  async permissionsForUser(userId) {
    return permissionsForUser(this.pool, userId);
  }

  async setPasswordHash(userId, passwordHash) {
    await this.pool.query(
      `UPDATE users SET password_hash = $2, auth_version = auth_version + 1, updated_at = now()
       WHERE id = $1`,
      [userId, passwordHash],
    );
  }

  async createUser({
    id = randomUUID(),
    displayName,
    phone,
    username,
    email,
    passwordHash,
    pinHash,
    homeArea,
    legalSurname = null,
    legalGivenNames = null,
    legalNameSource = 'self_attested',
    emailVerified = false,
    identity = null,
    roles = ['passenger'],
    status = 'active',
  }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO users (id, display_name, phone, username, email, password_hash, pin_hash, home_area,
                            legal_surname, legal_given_names, legal_name_source, email_verified, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
        [
          id,
          displayName,
          phone ?? null,
          username ?? null,
          email ?? null,
          passwordHash ?? null,
          pinHash ?? null,
          homeArea ?? null,
          legalSurname,
          legalGivenNames,
          legalNameSource,
          emailVerified,
          status,
        ],
      );
      // Every signup is at least a rider (anyone can request a seat), plus any
      // additional role chosen at signup (e.g. driver). System groups are
      // unique per role, so they are looked up by role rather than by name.
      const uniqueRoles = new Set(['passenger', ...roles]);
      for (const role of uniqueRoles) {
        const group = await client.query(
          'SELECT id FROM groups WHERE role = $1 AND is_system',
          [role],
        );
        if (!group.rowCount) continue;
        await client.query(
          `INSERT INTO group_members (group_id, user_id) VALUES ($1, $2)
           ON CONFLICT DO NOTHING`,
          [group.rows[0].id, id],
        );
      }
      if (identity) {
        await client.query(
          `INSERT INTO auth_identities (user_id, provider, provider_uid, email, email_verified)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (provider, provider_uid) DO NOTHING`,
          [id, identity.provider, identity.providerUid, identity.email ?? null, identity.emailVerified ?? false],
        );
      }
      await client.query('COMMIT');
      return this.findById(id);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async setPinHash(userId, pinHash) {
    await this.pool.query(
      `UPDATE users SET pin_hash = $2, must_change_pin = false, auth_version = auth_version + 1
       WHERE id = $1`,
      [userId, pinHash],
    );
  }

  async markPhoneVerified(userId) {
    await this.pool.query('UPDATE users SET phone_verified = true WHERE id = $1', [userId]);
  }

  /**
   * Sets or clears the mobile money payout number a driver's confirmed
   * passengers should pay directly (outside the app — see migration 011).
   * Passing null for both clears the registration.
   */
  async setMomoDetails(userId, { momoNumber, momoNetwork }) {
    await this.pool.query(
      `UPDATE users SET momo_number = $2, momo_network = $3, updated_at = now() WHERE id = $1`,
      [userId, momoNumber ?? null, momoNetwork ?? null],
    );
  }

  async bumpAuthVersion(userId) {
    await this.pool.query('UPDATE users SET auth_version = auth_version + 1 WHERE id = $1', [userId]);
  }

  async createSession({ userId, expiresAt }) {
    const result = await this.pool.query(
      `INSERT INTO auth_sessions (user_id, expires_at) VALUES ($1, $2) RETURNING id`,
      [userId, expiresAt],
    );
    return result.rows[0].id;
  }

  async findSession(sessionId) {
    const result = await this.pool.query('SELECT * FROM auth_sessions WHERE id = $1', [sessionId]);
    return result.rows[0] ?? null;
  }

  async touchSession(sessionId) {
    await this.pool.query('UPDATE auth_sessions SET last_activity_at = now() WHERE id = $1', [sessionId]);
  }

  async revokeSession(sessionId) {
    await this.pool.query('UPDATE auth_sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL', [
      sessionId,
    ]);
  }

  async createOtpCode({ userId, purpose, codeHash, expiresAt }) {
    const result = await this.pool.query(
      `INSERT INTO otp_codes (user_id, purpose, code_hash, expires_at) VALUES ($1, $2, $3, $4) RETURNING id`,
      [userId, purpose, codeHash, expiresAt],
    );
    return result.rows[0].id;
  }

  async findActiveOtpCode({ userId, purpose }) {
    const result = await this.pool.query(
      `SELECT * FROM otp_codes
       WHERE user_id = $1 AND purpose = $2 AND consumed_at IS NULL AND expires_at > now()
       ORDER BY created_at DESC LIMIT 1`,
      [userId, purpose],
    );
    return result.rows[0] ?? null;
  }

  async incrementOtpAttempts(otpId) {
    await this.pool.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1', [otpId]);
  }

  async consumeOtpCode(otpId) {
    await this.pool.query('UPDATE otp_codes SET consumed_at = now() WHERE id = $1', [otpId]);
  }

  async close() {
    await this.pool.end();
  }
}
