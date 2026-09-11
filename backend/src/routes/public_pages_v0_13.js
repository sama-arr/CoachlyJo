// =============================================================================
// Public web pages (v0.13).
//
// Two store requirements are satisfied here, both without the app installed:
//   * a public Privacy Policy URL   -> /privacy   (Apple + Google listing field)
//   * a web account-deletion route  -> /delete-account  (Google Play policy:
//     "a web resource must be available to request account and data deletion
//     without having to reinstall the app")
//
// The text comes from the same admin-editable content blocks the app shows, so
// there is one copy to maintain and it is already bilingual.
// =============================================================================
const express = require('express');
const { pool } = require('../db/pool_v0_13');

const router = express.Router();

const BRAND = 'CoachlyJo';

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function page({ title, bodyHtml, dir = 'ltr' }) {
  return `<!doctype html>
<html lang="${dir === 'rtl' ? 'ar' : 'en'}" dir="${dir}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} — ${BRAND}</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; background:#0A0A0E; color:#EDEDF2;
         font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         line-height:1.65; }
  .wrap { max-width: 760px; margin: 0 auto; padding: 32px 20px 64px; }
  .brand { font-size: 30px; font-weight: 800; letter-spacing:-0.5px;
           background: linear-gradient(90deg,#F20FB6,#FF770F);
           -webkit-background-clip: text; background-clip: text; color: transparent; }
  h1 { font-size: 22px; margin: 26px 0 6px; }
  .rule { width:52px; height:3px; border-radius:2px; background:linear-gradient(90deg,#C91E97,#D9700F); }
  pre.body { white-space: pre-wrap; font: inherit; color:#CFCFDA; margin: 14px 0 0; }
  .card { background:#15151B; border:1px solid #23232C; border-radius:16px; padding:20px; margin-top:20px; }
  label { display:block; font-size:13px; color:#9A9AA6; margin: 14px 0 6px; }
  input, textarea { width:100%; box-sizing:border-box; background:#0F0F14; color:#EDEDF2;
                    border:1px solid #3A3A46; border-radius:10px; padding:11px 12px; font: inherit; }
  button { margin-top:18px; width:100%; padding:13px; border:0; border-radius:10px;
           font-weight:700; font-size:15px; color:#fff; cursor:pointer;
           background: linear-gradient(90deg,#C91E97,#D9700F); }
  .muted { color:#9A9AA6; font-size:13px; }
  .ok { background:#12301F; border:1px solid #2F6B47; color:#9BE7C0;
        padding:12px 14px; border-radius:10px; margin-top:16px; }
  .err { background:#3A1220; border:1px solid #7A2340; color:#FFB3C4;
         padding:12px 14px; border-radius:10px; margin-top:16px; }
  a { color:#FF9D4D; }
  .langs { margin-top: 10px; font-size: 13px; }
</style>
<div class="wrap">
  <div class="brand">${BRAND}</div>
  ${bodyHtml}
</div>
</html>`;
}

async function legalBlocks() {
  const r = await pool.query(
    `SELECT key, title_en, title_ar, body_en, body_ar, sort_order, updated_at
       FROM content_blocks WHERE kind='legal' AND is_active=TRUE ORDER BY sort_order`);
  return r.rows;
}

function renderLegal(row, lang) {
  const ar = lang === 'ar';
  const title = ar && row.title_ar ? row.title_ar : row.title_en;
  const body = ar && row.body_ar ? row.body_ar : row.body_en;
  return `<h1>${escapeHtml(title)}</h1><div class="rule"></div><pre class="body">${escapeHtml(body)}</pre>`;
}

// ---- Privacy policy (the URL you put on both store listings) ----------------
router.get('/privacy', async (req, res) => {
  const lang = req.query.lang === 'ar' ? 'ar' : 'en';
  const rows = await legalBlocks();
  const row = rows.find((r) => r.key === 'legal_privacy');
  if (!row) return res.status(404).send('Privacy policy not published yet.');
  const other = lang === 'ar' ? 'en' : 'ar';
  res.type('html').send(page({
    title: lang === 'ar' ? row.title_ar : row.title_en,
    dir: lang === 'ar' ? 'rtl' : 'ltr',
    bodyHtml: `<div class="langs"><a href="/privacy?lang=${other}">${other === 'ar' ? 'العربية' : 'English'}</a>
      &nbsp;·&nbsp; <a href="/terms?lang=${lang}">${lang === 'ar' ? 'شروط الاستخدام' : 'Terms of Service'}</a>
      &nbsp;·&nbsp; <a href="/delete-account?lang=${lang}">${lang === 'ar' ? 'حذف الحساب' : 'Delete my account'}</a></div>
      ${renderLegal(row, lang)}`,
  }));
});

router.get('/terms', async (req, res) => {
  const lang = req.query.lang === 'ar' ? 'ar' : 'en';
  const rows = await legalBlocks();
  const row = rows.find((r) => r.key === 'legal_terms');
  if (!row) return res.status(404).send('Terms not published yet.');
  const other = lang === 'ar' ? 'en' : 'ar';
  res.type('html').send(page({
    title: lang === 'ar' ? row.title_ar : row.title_en,
    dir: lang === 'ar' ? 'rtl' : 'ltr',
    bodyHtml: `<div class="langs"><a href="/terms?lang=${other}">${other === 'ar' ? 'العربية' : 'English'}</a>
      &nbsp;·&nbsp; <a href="/privacy?lang=${lang}">${lang === 'ar' ? 'سياسة الخصوصية' : 'Privacy Policy'}</a></div>
      ${renderLegal(row, lang)}`,
  }));
});

// ---- Web account-deletion request (Google Play requirement) -----------------
const COPY = {
  en: {
    dir: 'ltr',
    h: 'Delete my account',
    intro: 'You can delete your CoachlyJo account and its data from the app under Settings → Delete account. '
      + 'If you no longer have the app installed, submit the form below and our team will delete the account and confirm by email within 30 days.',
    what: 'What gets deleted: your name, email, phone number, date of birth, the area you selected, your fitness questionnaire answers, '
      + 'any documents or payment-proof images you uploaded, and your notifications. Upcoming sessions are cancelled. '
      + 'We keep an anonymised record of completed purchases where accounting law requires it; that record cannot identify you.',
    email: 'The email address on your account',
    note: 'Anything you want us to know (optional)',
    submit: 'Request deletion',
    thanks: 'Your deletion request has been received. We will process it and confirm by email within 30 days.',
    bad: 'Please enter a valid email address.',
    privacy: 'Privacy Policy',
  },
  ar: {
    dir: 'rtl',
    h: 'حذف حسابي',
    intro: 'يمكنك حذف حسابك في كوتشلي جو وبياناته من داخل التطبيق عبر الإعدادات ← حذف الحساب. '
      + 'وإذا لم يعد التطبيق مثبتاً لديك، أرسل النموذج أدناه وسيقوم فريقنا بحذف الحساب وتأكيد ذلك عبر البريد خلال 30 يوماً.',
    what: 'ما الذي يتم حذفه: اسمك وبريدك الإلكتروني ورقم هاتفك وتاريخ ميلادك والمنطقة التي اخترتها وإجابات استبيان اللياقة '
      + 'وأي مستندات أو صور إثبات دفع رفعتها وإشعاراتك. كما تُلغى جلساتك القادمة. '
      + 'نحتفظ بسجل مجهول الهوية لعمليات الشراء المكتملة عند اشتراط القانون المحاسبي ذلك، ولا يمكن لهذا السجل التعرف عليك.',
    email: 'البريد الإلكتروني المسجل في حسابك',
    note: 'أي ملاحظة تود إخبارنا بها (اختياري)',
    submit: 'إرسال طلب الحذف',
    thanks: 'تم استلام طلب الحذف. سنقوم بمعالجته وتأكيده عبر البريد خلال 30 يوماً.',
    bad: 'يرجى إدخال بريد إلكتروني صحيح.',
    privacy: 'سياسة الخصوصية',
  },
};

function deletionPage(lang, state) {
  const c = COPY[lang];
  const other = lang === 'ar' ? 'en' : 'ar';
  const banner = state === 'ok' ? `<div class="ok">${c.thanks}</div>`
    : state === 'bad' ? `<div class="err">${c.bad}</div>` : '';
  return page({
    title: c.h,
    dir: c.dir,
    bodyHtml: `
      <div class="langs"><a href="/delete-account?lang=${other}">${other === 'ar' ? 'العربية' : 'English'}</a>
        &nbsp;·&nbsp; <a href="/privacy?lang=${lang}">${c.privacy}</a></div>
      <h1>${c.h}</h1><div class="rule"></div>
      <p class="muted" style="margin-top:14px">${c.intro}</p>
      <p class="muted">${c.what}</p>
      ${banner}
      <div class="card">
        <form method="POST" action="/delete-account?lang=${lang}">
          <label for="email">${c.email}</label>
          <input id="email" name="email" type="email" required autocomplete="email">
          <label for="note">${c.note}</label>
          <textarea id="note" name="note" rows="3"></textarea>
          <button type="submit">${c.submit}</button>
        </form>
      </div>`,
  });
}

router.get('/delete-account', (req, res) => {
  const lang = req.query.lang === 'ar' ? 'ar' : 'en';
  res.type('html').send(deletionPage(lang, null));
});

router.post('/delete-account', express.urlencoded({ extended: false }), async (req, res) => {
  const lang = req.query.lang === 'ar' ? 'ar' : 'en';
  const email = (req.body?.email || '').toString().toLowerCase().trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return res.status(400).type('html').send(deletionPage(lang, 'bad'));
  }
  await pool.query(
    `INSERT INTO deletion_requests (email, note) VALUES ($1, $2)`,
    [email, (req.body?.note || '').toString().slice(0, 500)]);
  res.type('html').send(deletionPage(lang, 'ok'));
});

module.exports = router;
