-- =============================================================================
-- Schema migration v0.7 -> v0.8
-- v0.8 was a UI release (richer theme, settings hub) with no structural
-- changes; this migration only advances the version marker so /health/schema
-- reflects the deployed release.
--
-- NOTE (v0.10): this file was lost when the v0.9 file-rename pass renamed
-- *.sql migrations along with the source files. Migrations are versioned
-- history and are never renamed — the rename script now excludes them.
-- =============================================================================
INSERT INTO schema_meta (id, version) VALUES (1, 8)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 8);
