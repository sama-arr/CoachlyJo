// The schema version this code expects. migrate_v0_4.sql writes this into
// schema_meta. The server checks it at startup (see server.js) and refuses to
// serve if the DB is older — this is what prevents the "column does not exist"
// class of bug from a half-applied migration.
module.exports = { EXPECTED_SCHEMA_VERSION: 14 };
