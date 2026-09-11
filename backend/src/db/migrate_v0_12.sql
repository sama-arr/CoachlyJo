-- =============================================================================
-- Schema migration v0.11 -> v0.12
-- Rebrand: the app is now "CoachlyJo". Content seeded by earlier migrations
-- mentions the old name, so update the stored copy in place (both languages).
--
-- Written to be IDEMPOTENT: it first normalises any already-renamed text back
-- to the base name, then renames. Running it twice (or running it on a fresh
-- database whose seed already carries the new name) cannot produce
-- "CoachlyJoJo".
-- =============================================================================

UPDATE content_blocks
   SET title_en   = REPLACE(REPLACE(title_en, 'CoachlyJo', 'Coachly'), 'Coachly', 'CoachlyJo'),
       body_en    = REPLACE(REPLACE(body_en,  'CoachlyJo', 'Coachly'), 'Coachly', 'CoachlyJo'),
       title_ar   = REPLACE(REPLACE(title_ar, 'كوتشلي جو', 'كوتشلي'), 'كوتشلي', 'كوتشلي جو'),
       body_ar    = REPLACE(REPLACE(body_ar,  'كوتشلي جو', 'كوتشلي'), 'كوتشلي', 'كوتشلي جو'),
       updated_at = now()
 WHERE title_en LIKE '%Coachly%' OR body_en LIKE '%Coachly%'
    OR title_ar LIKE '%كوتشلي%' OR body_ar LIKE '%كوتشلي%';

INSERT INTO schema_meta (id, version) VALUES (1, 12)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 12);
