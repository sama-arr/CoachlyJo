-- =============================================================================
-- Schema migration v0.14 -> v0.15
--
-- Fixes a live operational hazard found while testing v0.14: running
-- `npm run seed` twice DUPLICATED the whole package catalogue. The seed used
-- `ON CONFLICT DO NOTHING` but there was no unique constraint for it to act
-- on, so every re-seed inserted another eight package definitions and members
-- saw each package listed twice.
--
-- This migration removes the duplicates it can remove safely and adds the
-- constraint the seed needed all along.
-- =============================================================================

-- 1. Delete duplicate definitions that nobody has purchased, keeping the
--    earliest row of each name. Definitions with purchases are never touched —
--    a member_packages row points at them and carries real money.
DELETE FROM package_definitions pd
 WHERE EXISTS (
         SELECT 1 FROM package_definitions keep
          WHERE keep.name_en = pd.name_en
            AND keep.ctid < pd.ctid)
   AND NOT EXISTS (
         SELECT 1 FROM member_packages mp WHERE mp.package_def_id = pd.id);

-- 2. Add the unique constraint, but only if the data now allows it. If a
--    duplicate survived because it has purchases, the index is skipped and the
--    seed guard below still prevents further duplication.
DO $$
BEGIN
  IF NOT EXISTS (
        SELECT 1 FROM package_definitions
         GROUP BY name_en HAVING COUNT(*) > 1)
  THEN
    CREATE UNIQUE INDEX IF NOT EXISTS uq_package_def_name ON package_definitions(name_en);
  ELSE
    RAISE NOTICE 'Duplicate package names still exist (they have purchases); unique index skipped.';
  END IF;
END $$;

INSERT INTO schema_meta (id, version) VALUES (1, 15)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 15);
