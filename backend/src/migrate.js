import { createPostgresPool } from './infrastructure/postgres.js';
import { runMigrations } from './infrastructure/migrations.js';

const pool = createPostgresPool({ connectionString: process.env.DATABASE_URL });
try {
  await runMigrations(pool);
} finally {
  await pool.end();
}
