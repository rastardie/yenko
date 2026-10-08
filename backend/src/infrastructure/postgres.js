import pg from 'pg';

const { Pool } = pg;

export function createPostgresPool({ connectionString, max = 10 } = {}) {
  if (!connectionString) throw new Error('DATABASE_URL is required for PostgreSQL.');
  return new Pool({ connectionString, max, idleTimeoutMillis: 10_000 });
}
