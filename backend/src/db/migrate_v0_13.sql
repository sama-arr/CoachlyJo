-- =============================================================================
-- Schema migration v0.12 -> v0.13  (App Store / Play Store compliance)
--
--   (1) Account deletion. Both stores require an in-app path to delete an
--       account and its data (Apple: in-app; Google: in-app AND a web link).
--       Personal data is erased; the financial record of a purchase is kept in
--       anonymised form, which both stores permit when disclosed in the
--       privacy policy (we disclose it in the seeded policy text below).
--
--   (2) Legal content: privacy policy and terms, admin-editable in English and
--       Arabic, reachable BEFORE login (reviewers check this) and linkable as
--       the public privacy-policy URL both stores require.
-- =============================================================================

-- ---- (1) Soft-delete marker on users ----------------------------------------
-- Deleting an account erases the phone number, so the column must accept NULL.
-- Registration still requires one (validated in the auth route), and the
-- UNIQUE index continues to work because Postgres allows multiple NULLs.
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
-- The row survives (foreign keys from financial records point at it) but every
-- identifying field is overwritten at deletion time.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_users_deleted ON users(deleted_at) WHERE deleted_at IS NOT NULL;

-- Audit trail of deletions (no personal data — just who/when/why, for support
-- and for proving compliance if a store or a user asks).
CREATE TABLE IF NOT EXISTS account_deletions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    role         TEXT NOT NULL,
    requested_by TEXT NOT NULL CHECK (requested_by IN ('user', 'admin', 'web')),
    reason       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Web deletion requests (Google Play requires a route that does not need the
-- app installed). The admin verifies and completes these from the console.
CREATE TABLE IF NOT EXISTS deletion_requests (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email        TEXT NOT NULL,
    note         TEXT,
    status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done', 'rejected')),
    handled_by   UUID REFERENCES users(id),
    handled_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_deletion_requests_status ON deletion_requests(status, created_at DESC);

-- ---- (2) Legal content -------------------------------------------------------
-- Reuse content_blocks: add the 'legal' kind and a 'public' audience so the
-- policy can be fetched without a session.
ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_kind_check;
ALTER TABLE content_blocks ADD CONSTRAINT content_blocks_kind_check
    CHECK (kind IN ('intro', 'step', 'rule', 'legal'));
ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_audience_check;
ALTER TABLE content_blocks ADD CONSTRAINT content_blocks_audience_check
    CHECK (audience IN ('member', 'coach', 'both', 'public'));

INSERT INTO content_blocks (key, audience, kind, title_en, title_ar, body_en, body_ar, sort_order) VALUES
('legal_privacy', 'public', 'legal', 'Privacy Policy', 'سياسة الخصوصية',
E'STARTER TEXT — have a lawyer review before publishing.\n\nWho we are\nCoachlyJo is a fitness coaching platform operating in Amman, Jordan.\n\nWhat we collect\n• Account details: name, email, phone number, date of birth, nationality and the area of Amman you select.\n• Fitness questionnaire: the goals, activity level and any injuries or conditions you choose to share with your coach.\n• Payment proof: the image you upload showing your bank transfer.\n• Coach documents: certificates and experience proof uploaded by coaches for verification.\n• Usage data: your bookings, sessions, cancellations and package history.\n\nWhy we collect it\nTo create your account, match you with a coach, run and confirm your sessions, verify your payments, and send you the notifications you expect (booking updates and session reminders).\n\nWho can see it\n• Your coach sees your contact details and your fitness questionnaire once you have a booking or a package with them.\n• Our administrators see account and payment information to run the service.\n• We do not sell your data, and we do not share it for advertising.\n\nSensitive information\nThe fitness questionnaire may include health-related answers such as injuries. Share only what you are comfortable sharing with your coach. You can leave any question blank.\n\nDeleting your account\nYou can delete your account at any time from Settings, or by requesting deletion at the web address listed on our store page. When you delete your account we erase your name, contact details, questionnaire answers, uploaded documents and payment-proof images, and we cancel your upcoming sessions. We keep an anonymised record of completed purchases where we are required to for accounting and tax purposes; that record cannot identify you.\n\nData retention\nWe keep your data while your account is active, and for as long as the law requires after deletion for the anonymised financial records described above.\n\nSecurity\nData is transmitted over encrypted connections and passwords are stored hashed. No system is perfectly secure, and we will tell you promptly if a breach affects your data.\n\nChildren\nCoachlyJo is not intended for anyone under 16.\n\nContact\nFor any privacy question, or to request your data, contact us at the support email on our store listing.',
E'نص مبدئي — يرجى مراجعته من قبل محامٍ قبل النشر.\n\nمن نحن\nكوتشلي جو منصة تدريب لياقة بدنية تعمل في عمّان، الأردن.\n\nما الذي نجمعه\n• بيانات الحساب: الاسم، البريد الإلكتروني، رقم الهاتف، تاريخ الميلاد، الجنسية والمنطقة التي تختارها في عمّان.\n• استبيان اللياقة: أهدافك ومستوى نشاطك وأي إصابات أو حالات تختار مشاركتها مع مدربك.\n• إثبات الدفع: الصورة التي ترفعها للحوالة البنكية.\n• مستندات المدربين: الشهادات وإثباتات الخبرة التي يرفعها المدربون للتحقق.\n• بيانات الاستخدام: حجوزاتك وجلساتك وعمليات الإلغاء وسجل باقاتك.\n\nلماذا نجمعها\nلإنشاء حسابك، ولربطك بمدرب مناسب، ولتشغيل جلساتك وتأكيدها، وللتحقق من مدفوعاتك، ولإرسال الإشعارات المتوقعة (تحديثات الحجز وتذكير الجلسات).\n\nمن يمكنه الاطلاع عليها\n• يرى مدربك بيانات التواصل واستبيان اللياقة بعد وجود حجز أو باقة معه.\n• يرى المشرفون لدينا بيانات الحساب والدفع لتشغيل الخدمة.\n• لا نبيع بياناتك ولا نشاركها لأغراض إعلانية.\n\nالمعلومات الحساسة\nقد يتضمن استبيان اللياقة إجابات متعلقة بالصحة مثل الإصابات. شارك فقط ما ترتاح لمشاركته مع مدربك، ويمكنك ترك أي سؤال فارغاً.\n\nحذف حسابك\nيمكنك حذف حسابك في أي وقت من الإعدادات، أو بطلب الحذف عبر الرابط المذكور في صفحة المتجر. عند الحذف نمسح اسمك وبيانات التواصل وإجابات الاستبيان والمستندات وصور إثبات الدفع، ونلغي جلساتك القادمة. نحتفظ بسجل مجهول الهوية لعمليات الشراء المكتملة عند الحاجة لأغراض محاسبية وضريبية، ولا يمكن لهذا السجل التعرف عليك.\n\nمدة الاحتفاظ\nنحتفظ ببياناتك طالما كان حسابك فعالاً، وبعد الحذف للمدة التي يفرضها القانون بالنسبة للسجلات المالية مجهولة الهوية المذكورة أعلاه.\n\nالأمان\nتُنقل البيانات عبر اتصالات مشفّرة وتُخزَّن كلمات المرور مشفّرة. لا يوجد نظام آمن بشكل مطلق، وسنخبرك فوراً إذا تأثرت بياناتك بأي اختراق.\n\nالأطفال\nكوتشلي جو غير مخصص لمن هم دون 16 عاماً.\n\nللتواصل\nلأي استفسار يتعلق بالخصوصية أو لطلب بياناتك، تواصل معنا عبر بريد الدعم المذكور في صفحة المتجر.',
1),

('legal_terms', 'public', 'legal', 'Terms of Service', 'شروط الاستخدام',
E'STARTER TEXT — have a lawyer review before publishing.\n\nWhat CoachlyJo is\nCoachlyJo connects members with verified one-to-one fitness coaches in Amman. Sessions are delivered online or in person by the coach, not by CoachlyJo.\n\nYour account\nYou must be at least 16 and provide accurate details. Keep your password to yourself; you are responsible for activity on your account.\n\nPackages and payment\nPackages are prepaid one-to-one training sessions bought for one specific coach. You pay by bank transfer and upload proof; an administrator confirms it before the package becomes usable. Prices are shown in Jordanian Dinars and are captured at the time of purchase.\n\nBooking and cancellation\n• Cancelling more than 24 hours before a session costs you nothing.\n• Cancelling within 24 hours deducts that session from your package.\n• You may cancel up to 3 sessions per package.\n• If a coach cancels, you are never charged for that session.\n• If you do not attend, your coach may record a no-show and the session is deducted.\nThe full rules are shown on the Home tab in the app and may be updated there.\n\nPackage validity\nEach package has a validity period shown at purchase. Sessions not used within that period expire.\n\nRefunds\nRefund requests are handled case by case by the CoachlyJo team. Contact support using the email on our store listing.\n\nCoach responsibilities\nCoaches must hold the qualifications they present, attend confirmed sessions, and treat members professionally. CoachlyJo may suspend or remove a coach who does not.\n\nHealth disclaimer\nCoachlyJo is not a medical service. Consult a doctor before starting any exercise programme, and tell your coach about injuries or conditions. You train at your own risk.\n\nEnding your account\nYou may delete your account at any time from Settings. We may suspend accounts that breach these terms.\n\nChanges\nWe may update these terms; the current version is always available in the app.',
E'نص مبدئي — يرجى مراجعته من قبل محامٍ قبل النشر.\n\nما هو كوتشلي جو\nيربط كوتشلي جو الأعضاء بمدربي لياقة معتمدين للتدريب الفردي في عمّان. تُقدَّم الجلسات أونلاين أو حضورياً من قبل المدرب وليس من قبل كوتشلي جو.\n\nحسابك\nيجب أن يكون عمرك 16 عاماً على الأقل وأن تقدم بيانات صحيحة. حافظ على سرية كلمة المرور؛ أنت مسؤول عن النشاط على حسابك.\n\nالباقات والدفع\nالباقات هي جلسات تدريب فردية مدفوعة مسبقاً وتُشترى لمدرب محدد. تدفع عبر حوالة بنكية وترفع الإثبات، ويقوم المشرف بتأكيده قبل تفعيل الباقة. الأسعار بالدينار الأردني وتُثبَّت وقت الشراء.\n\nالحجز والإلغاء\n• الإلغاء قبل أكثر من 24 ساعة لا يكلفك شيئاً.\n• الإلغاء خلال 24 ساعة يخصم الجلسة من باقتك.\n• يمكنك إلغاء 3 جلسات كحد أقصى لكل باقة.\n• إذا ألغى المدرب الجلسة، لا تُخصم منك أي حصة.\n• إذا لم تحضر، يمكن للمدرب تسجيل عدم الحضور وتُخصم الجلسة.\nتظهر القواعد الكاملة في صفحة الرئيسية داخل التطبيق وقد يتم تحديثها هناك.\n\nصلاحية الباقة\nلكل باقة مدة صلاحية تظهر عند الشراء، وتنتهي الجلسات غير المستخدمة بانتهائها.\n\nالاسترجاع\nتُعالج طلبات الاسترجاع حالة بحالة من قبل فريق كوتشلي جو. تواصل مع الدعم عبر البريد المذكور في صفحة المتجر.\n\nمسؤوليات المدرب\nعلى المدرب أن يمتلك المؤهلات التي يعرضها، وأن يحضر الجلسات المؤكدة، وأن يتعامل باحترافية. يحق لكوتشلي جو إيقاف أو إزالة أي مدرب لا يلتزم.\n\nإخلاء مسؤولية صحية\nكوتشلي جو ليس خدمة طبية. استشر طبيبك قبل بدء أي برنامج رياضي، وأبلغ مدربك بأي إصابات أو حالات صحية. التمرين يتم على مسؤوليتك.\n\nإنهاء الحساب\nيمكنك حذف حسابك في أي وقت من الإعدادات. ويحق لنا إيقاف الحسابات المخالفة لهذه الشروط.\n\nالتغييرات\nقد نقوم بتحديث هذه الشروط، وتتوفر النسخة الحالية دائماً داخل التطبيق.',
2)
ON CONFLICT (key) DO NOTHING;

INSERT INTO schema_meta (id, version) VALUES (1, 13)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 13);
