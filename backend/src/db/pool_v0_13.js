const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  database: process.env.PGDATABASE || 'fitness',
  user: process.env.PGUSER || 'fitapp',
  password: process.env.PGPASSWORD || 'fitpass',
  max: 10,
});

pool.on('error', (err) => {
  console.error('Unexpected PG pool error:', err);
});

// Helper that runs a function inside a single transaction.
// Used by booking flows so counter moves are atomic (spec §7).
async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, withTransaction };
