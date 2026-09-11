-- =============================================================================
-- Schema migration v0.9 -> v0.10
--   (1,2,3) Home page: admin-editable content blocks (intro, how-it-works,
--           rules) in English + Arabic per audience, plus an optional intro
--           video URL on platform settings.
--   (2)     Policy enforcement support:
--             * cancellations are attributed (member / coach / admin) so the
--               3-cancellations-per-package cap counts only the member's own;
--             * same-day coach cancellations create a coach penalty record.
-- =============================================================================

-- ---- Home / rules content ----------------------------------------------------
-- audience: 'member' | 'coach' | 'both'
-- kind:     'intro' (about the app) | 'step' (how it works) | 'rule'
CREATE TABLE IF NOT EXISTS content_blocks (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key        TEXT NOT NULL UNIQUE,
    audience   TEXT NOT NULL CHECK (audience IN ('member','coach','both')),
    kind       TEXT NOT NULL CHECK (kind IN ('intro','step','rule')),
    title_en   TEXT NOT NULL DEFAULT '',
    title_ar   TEXT NOT NULL DEFAULT '',
    body_en    TEXT NOT NULL DEFAULT '',
    body_ar    TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_content_audience ON content_blocks(audience, kind, sort_order);

-- Optional intro video shown on the home page (hidden while empty).
ALTER TABLE platform_settings ADD COLUMN IF NOT EXISTS intro_video_url TEXT NOT NULL DEFAULT '';

-- ---- Cancellation attribution ------------------------------------------------
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_by TEXT
    CHECK (cancelled_by IN ('member','coach','admin'));
UPDATE bookings
   SET cancelled_by = CASE
         WHEN rejection_reason = 'Package moved to another coach by admin' THEN 'admin'
         ELSE 'member' END
 WHERE status = 'cancelled' AND cancelled_by IS NULL;

-- ---- Coach penalties ---------------------------------------------------------
-- No payout ledger exists yet, so a same-day coach cancellation is recorded
-- here (one session owed) for the admin to settle manually.
CREATE TABLE IF NOT EXISTS coach_penalties (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id    UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    booking_id  UUID REFERENCES bookings(id) ON DELETE SET NULL,
    sessions    INTEGER NOT NULL DEFAULT 1,
    reason      TEXT NOT NULL,
    settled_at  TIMESTAMPTZ,
    settled_by  UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_penalty_coach ON coach_penalties(coach_id, created_at DESC);

-- ---- Seed home page + the published rules ------------------------------------
INSERT INTO content_blocks (key, audience, kind, title_en, title_ar, body_en, body_ar, sort_order) VALUES
('intro_main', 'both', 'intro',
 'Welcome to CoachlyJo', 'أهلاً بك في كوتشلي جو',
 'CoachlyJo connects you with verified fitness coaches in Amman. Browse coaches, buy a package of classes, and book sessions online or in person — all in one place.',
 'يربطك تطبيق كوتشلي جو بمدربي لياقة معتمدين في عمّان. تصفّح المدربين، اشترِ باقة حصص، واحجز جلساتك أونلاين أو حضورياً — كل ذلك في مكان واحد.',
 1),
('step_member_1', 'member', 'step', 'Find your coach', 'اختر مدربك',
 'Browse verified coaches, check their rating and experience, and pick the one that fits your goals.',
 'تصفّح المدربين المعتمدين، اطّلع على تقييمهم وخبرتهم، واختر الأنسب لأهدافك.', 1),
('step_member_2', 'member', 'step', 'Buy a package', 'اشترِ باقة',
 'Choose online or in-person, pick the number of classes, transfer the amount to the bank details shown, and upload your proof of payment.',
 'اختر أونلاين أو حضوري، حدّد عدد الحصص، حوّل المبلغ إلى الحساب البنكي الظاهر، وارفع إثبات الدفع.', 2),
('step_member_3', 'member', 'step', 'Book your sessions', 'احجز جلساتك',
 'Once the admin confirms your payment, book any open slot with your coach. Online sessions get a Zoom link automatically.',
 'بعد تأكيد الإدارة للدفع، احجز أي وقت متاح لدى مدربك. الجلسات الأونلاين تحصل على رابط زوم تلقائياً.', 3),
('step_coach_1', 'coach', 'step', 'Set your weekly hours', 'حدّد ساعاتك الأسبوعية',
 'Open the Availability tab, choose your session length and add the hours you work each day. Bookable slots are generated automatically.',
 'افتح صفحة الأوقات المتاحة، اختر مدة الجلسة وأضف ساعات عملك لكل يوم. تُنشأ الأوقات القابلة للحجز تلقائياً.', 1),
('step_coach_2', 'coach', 'step', 'Accept requests', 'اقبل الطلبات',
 'Members request your open slots. Accept to confirm the session and see their contact details and fitness questionnaire.',
 'يطلب الأعضاء الأوقات المتاحة لديك. اقبل الطلب لتأكيد الجلسة والاطلاع على بيانات التواصل واستبيان اللياقة.', 2),
('step_coach_3', 'coach', 'step', 'Complete the session', 'أكمل الجلسة',
 'After the session ends, mark it Completed — or report a no-show. This is what deducts the class from the member package.',
 'بعد انتهاء الجلسة، ضع علامة مكتمل — أو سجّل عدم الحضور. هذا ما يخصم الحصة من باقة العضو.', 3),
('rule_member_cancel', 'member', 'rule',
 'Session cancellation — by the client', 'إلغاء الجلسة — من قبل العميل',
 E'• If you cancel more than 24 hours before the scheduled time, no session is deducted.\n• If you cancel within 24 hours of the scheduled time, the session is deducted from your package.\n• You may cancel up to 3 sessions per package.',
 E'• إذا ألغيت الجلسة قبل أكثر من 24 ساعة من موعدها، لا يتم خصم أي حصة.\n• إذا ألغيت الجلسة خلال 24 ساعة من موعدها، يتم خصم الحصة من باقتك.\n• يُسمح لك بإلغاء 3 جلسات كحد أقصى لكل باقة.',
 1),
('rule_member_coach_cancel', 'member', 'rule',
 'Session cancellation — by the coach', 'إلغاء الجلسة — من قبل المدرب',
 E'• If your coach cancels a session, no class is deducted from your package.\n• If the coach cancels on the same day, a session is deducted from the coach.',
 E'• إذا ألغى مدربك الجلسة، لا يتم خصم أي حصة من باقتك.\n• إذا ألغى المدرب الجلسة في نفس اليوم، تُخصم جلسة من المدرب.',
 2),
('rule_coach_cancel', 'coach', 'rule',
 'Session cancellation — by the coach', 'إلغاء الجلسة — من قبل المدرب',
 E'• If you cancel a session on the same day as the appointment, one session is deducted from you.\n• If you cancel more than 24 hours before the scheduled time, no session is deducted.\n• The member is never charged a class for a session you cancel.',
 E'• إذا ألغيت الجلسة في نفس يوم الموعد، تُخصم منك جلسة واحدة.\n• إذا ألغيت الجلسة قبل أكثر من 24 ساعة من موعدها، لا يتم خصم أي جلسة.\n• لا تُخصم أي حصة من العضو عند إلغائك للجلسة.',
 1),
('rule_coach_reject', 'coach', 'rule',
 'Rejecting booking requests', 'رفض طلبات الحجز',
 E'• You may reject a client booking request up to 3 times per package.\n• A reason is required for every rejection.\n• After 3 rejections you must accept the request or cancel it (cancellation rules above apply).',
 E'• يمكنك رفض طلبات الحجز لكل عميل حتى 3 مرات لكل باقة.\n• يجب ذكر سبب لكل عملية رفض.\n• بعد 3 مرات، عليك قبول الطلب أو إلغاؤه (وتطبّق قواعد الإلغاء أعلاه).',
 2),
('rule_coach_client_cancel', 'coach', 'rule',
 'Cancellation by the client', 'الإلغاء من قبل العميل',
 E'• A client who cancels more than 24 hours ahead is not charged a class.\n• A client who cancels within 24 hours has the class deducted.\n• Clients may cancel up to 3 sessions per package.',
 E'• العميل الذي يلغي قبل أكثر من 24 ساعة لا تُخصم منه حصة.\n• العميل الذي يلغي خلال 24 ساعة تُخصم منه الحصة.\n• يُسمح للعملاء بإلغاء 3 جلسات كحد أقصى لكل باقة.',
 3)
ON CONFLICT (key) DO NOTHING;

INSERT INTO schema_meta (id, version) VALUES (1, 10)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 10);
