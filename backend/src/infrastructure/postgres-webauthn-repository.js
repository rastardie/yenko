import { randomUUID } from 'node:crypto';

/** Persists WebAuthn credentials and short-lived ceremony challenges. */
export class PostgresWebAuthnRepository {
  constructor({ pool }) {
    this.pool = pool;
  }

  async listCredentialsForUser(userId) {
    const result = await this.pool.query(
      `SELECT id, user_id, public_key, counter, device_type, backed_up, transports,
              device_label, created_at, last_used_at
       FROM webauthn_credentials WHERE user_id = $1 ORDER BY created_at DESC`,
      [userId],
    );
    return result.rows;
  }

  async findCredentialById(credentialId) {
    const result = await this.pool.query(
      `SELECT id, user_id, public_key, counter, device_type, backed_up, transports,
              device_label, created_at, last_used_at
       FROM webauthn_credentials WHERE id = $1`,
      [credentialId],
    );
    return result.rows[0] ?? null;
  }

  async createCredential({
    id,
    userId,
    publicKey,
    counter,
    deviceType,
    backedUp,
    transports,
    deviceLabel = null,
  }) {
    await this.pool.query(
      `INSERT INTO webauthn_credentials
         (id, user_id, public_key, counter, device_type, backed_up, transports, device_label)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [id, userId, publicKey, counter, deviceType, backedUp, transports, deviceLabel],
    );
  }

  async updateCounter(credentialId, counter) {
    await this.pool.query(
      `UPDATE webauthn_credentials SET counter = $2, last_used_at = now(), updated_at = now()
       WHERE id = $1`,
      [credentialId, counter],
    );
  }

  async deleteCredential({ credentialId, userId }) {
    const result = await this.pool.query(
      'DELETE FROM webauthn_credentials WHERE id = $1 AND user_id = $2',
      [credentialId, userId],
    );
    return result.rowCount > 0;
  }

  async createChallenge({ userId = null, challenge, purpose, expiresAt }) {
    const id = randomUUID();
    await this.pool.query(
      `INSERT INTO webauthn_challenges (id, user_id, challenge, purpose, expires_at)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, userId, challenge, purpose, expiresAt],
    );
    return id;
  }

  /** Consumes (marks used) the most recent unexpired, unconsumed challenge matching the filter. */
  async consumeChallenge({ userId = null, purpose, challenge }) {
    const result = await this.pool.query(
      `UPDATE webauthn_challenges SET consumed_at = now()
       WHERE id = (
         SELECT id FROM webauthn_challenges
         WHERE purpose = $1 AND challenge = $2
           AND consumed_at IS NULL AND expires_at > now()
           AND ($3::text IS NULL OR user_id = $3)
         ORDER BY created_at DESC LIMIT 1
       )
       RETURNING id`,
      [purpose, challenge, userId],
    );
    return result.rowCount > 0;
  }
}
