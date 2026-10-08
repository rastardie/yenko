import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const migrationsDirectory = join(dirname(fileURLToPath(import.meta.url)), '../../db/migrations');

export async function runMigrations(pool, directory = migrationsDirectory) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name TEXT PRIMARY KEY,
      checksum TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  const names = (await readdir(directory)).filter((name) => name.endsWith('.sql')).sort();
  for (const name of names) {
    const sql = await readFile(join(directory, name), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const applied = await pool.query('SELECT checksum FROM schema_migrations WHERE name = $1', [name]);
    if (applied.rowCount) {
      if (applied.rows[0].checksum !== checksum) {
        throw new Error(`Migration ${name} has changed after being applied.`);
      }
      continue;
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)', [name, checksum]);
      await client.query('COMMIT');
      console.log(`Applied migration ${name}`);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}
