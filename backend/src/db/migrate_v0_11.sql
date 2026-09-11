-- =============================================================================
-- Schema migration v0.10 -> v0.11
--   (1) Package definitions can be deleted (when never purchased) or archived
--       (when purchases exist, so history and reports stay intact).
--   (2) Notification centre: the notifications table has existed since v0.1
--       but nothing wrote to it. This migration opens up the type list and
--       adds de-duplication so scheduled reminders can run every 15 minutes
--       without ever sending twice.
-- =============================================================================

-- ---- (1) Archive flag for package definitions --------------------------------
-- Archived = hidden from the member catalogue forever, but existing purchases
-- (which reference this row) keep working.
ALTER TABLE package_definitions ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;

-- ---- (2) Notifications -------------------------------------------------------
-- The v0.1 enum only covered 7 events; v0.11 sends ~20. Move to TEXT with a
-- CHECK so new event types are a one-line change instead of an enum migration
-- (ALTER TYPE ... ADD VALUE cannot be used freely inside a transaction).
ALTER TABLE notifications ALTER COLUMN type TYPE TEXT USING type::TEXT;

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
    -- member
    'package_activated', 'package_payment_rejected', 'package_expiring', 'package_expired',
    'package_finished', 'package_adjusted', 'package_moved', 'package_cancelled',
    'booking_accepted', 'booking_rejected', 'booking_cancelled_by_coach',
    'no_show_recorded', 'zoom_link',
    -- coach
    'coach_approved', 'coach_rejected', 'booking_requested',
    'booking_cancelled_by_member', 'penalty_recorded', 'new_client',
    -- both
    'session_reminder',
    -- admin
    'admin_new_coach', 'admin_new_package_request', 'admin_coach_same_day_cancel'
));

-- De-duplication: one row per logical event. Scheduled reminders use a key
-- like 'reminder:<bookingId>:24h', so re-running the job is harmless.
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS dedupe_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_dedupe
    ON notifications(dedupe_key) WHERE dedupe_key IS NOT NULL;

-- Email delivery bookkeeping (sent only when SMTP is configured).
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS emailed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_notif_user_created ON notifications(user_id, created_at DESC);

INSERT INTO schema_meta (id, version) VALUES (1, 11)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 11);
