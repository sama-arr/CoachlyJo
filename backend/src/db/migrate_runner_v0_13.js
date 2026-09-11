// Applies the schema to the configured database. Usage: npm run migrate
//
// v0.4 hardening: the baseline schema.sql is NOT idempotent (CREATE TYPE /
// CREATE TABLE without guards), so on an existing database the runner used to
// fail at the first file and later migrations never applied — the same
// stale-schema class of bug the version marker was added to catch. Now the
// runner detects whether the baseline exists and only applies what's needed.
// The incremental migrations (v0_2..v0_4) are all idempotent and always run.
const fs = require('fs');
const path = require('path');
const { pool } = require('./pool_v0_13');

const BASELINE = 'schema.sql';
const INCREMENTALS = ['migrate_v0_2.sql', 'migrate_v0_3.sql', 'migrate_v0_4.sql', 'migrate_v0_5.sql', 'migrate_v0_6.sql', 'migrate_v0_7.sql', 'migrate_v0_8.sql', 'migrate_v0_9.sql', 'migrate_v0_10.sql', 'migrate_v0_11.sql', 'migrate_v0_12.sql', 'migrate_v0_13.sql'];

async function baselineApplied() {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users'`
  );
  return r.rowCount > 0;
}

async function migrate() {
  try {
    const hasBaseline = await baselineApplied();
    const files = hasBaseline ? INCREMENTALS : [BASELINE, ...INCREMENTALS];
    if (hasBaseline) console.log('Baseline schema already present — applying incremental migrations only.');
    for (const f of files) {
      const p = path.join(__dirname, f);
      if (!fs.existsSync(p)) { console.error('missing', f); process.exit(1); }
      console.log('Applying', f, '...');
      await pool.query(fs.readFileSync(p, 'utf8'));
    }
    console.log('Schema applied successfully (v0.13).');
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

migrate();
