-- =============================================================================
-- Schema migration v0.5 -> v0.6
-- v0.6 is a UI/API-behavior release (archives, open-slot filters, CoachlyJo
-- theme). No structural changes — this migration only advances the version
-- marker so /health/schema tracks the deployed release.
-- =============================================================================
INSERT INTO schema_meta (id, version) VALUES (1, 6)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 6);
