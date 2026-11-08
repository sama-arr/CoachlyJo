// End-to-end test suite against a running API on :4000 (v0.11).
// v0.7 note: completion is only allowed AFTER a session's end time, so the
// suite shifts sessions into the past directly in the DB (test-only) before
// completing them — production code has no time-travel path.
// Covers everything from v0.1–v0.4 plus the v0.5 items:
//   forgot password (neutral responses, attempts cap, invalidation),
//   weekly recurring availability with auto-generated sessions (50-min default),
//   availability cleanup rules (booked sessions always kept),
//   payment-note endpoint (bank details before proof).
// All timing is computed relative to "now" so the suite never goes stale.
const BASE = 'http://localhost:4000';
let pass = 0, fail = 0;
function check(name, cond, extra = '') {
  if (cond) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name}  ${extra}`); }
}
async function api(method, path, body, token) {
  const r = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json().catch(() => ({}));
  return { status: r.status, data, headers: r.headers };
}
async function apiRaw(path, token, useQueryToken = false) {
  const url = BASE + path + (useQueryToken ? `${path.includes('?') ? '&' : '?'}token=${token}` : '');
  const r = await fetch(url, useQueryToken ? {} : { headers: { Authorization: `Bearer ${token}` } });
  const buf = Buffer.from(await r.arrayBuffer());
  return { status: r.status, contentType: r.headers.get('content-type'), bytes: buf };
}
const { pool } = require('../src/db/pool_v0_13');
// Test-only: move a session into the past so it can be completed.
async function endSessionInPast(sessionId, hoursAgo = 2) {
  await pool.query(
    `UPDATE coach_sessions SET start_at = now() - ($2 || ' hours')::interval,
                               end_at   = now() - ($2 || ' hours')::interval + interval '50 minutes'
      WHERE id = $1`, [sessionId, String(hoursAgo)]);
}
const uniq = Date.now();
const pngB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const proof = { fileName: 'proof.png', mimeType: 'image/png', dataBase64: pngB64 };
const pdfB64 = Buffer.from('%PDF-1.4\n%test\n').toString('base64');

// Weekday (0=Sun..6=Sat) of now + n days, in the platform timezone (Asia/Amman).
function dowPlus(n) {
  const d = new Date(Date.now() + n * 86400000);
  const wd = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Amman', weekday: 'short' }).format(d);
  return { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[wd];
}
const minutesBetween = (a, b) => Math.round((new Date(b) - new Date(a)) / 60000);
// (v0.14) The calendar stores availability against real dates.
const datePlus = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

// (v0.14 item 2) Registration is now short; the rest of the profile is
// completed inside the app. Members must finish it before booking or buying,
// so the suite completes it the same way the app does.
async function completeMemberProfile(token, location = 'Abdoun') {
  return api('POST', '/api/profile/member', {
    dateOfBirth: '1995-04-10',
    location,
    assessment: { goal: 'Lose weight', level: 'beginner' },
  }, token);
}
async function completeCoachProfile(token) {
  return api('POST', '/api/profile/coach', {
    dateOfBirth: '1990-05-01',
    yearsExperience: 6,
    specialties: ['Strength training', 'Weight loss'],
    documents: [
      { docType: 'degree_certificate', fileName: 'degree.pdf', mimeType: 'application/pdf', dataBase64: pdfB64 },
    ],
  }, token);
}

(async () => {
  console.log('\n=== 1. ADMIN LOGIN ===');
  const admin = await api('POST', '/api/auth/login', { email: 'admin@fitness.local', password: 'admin1234' });
  check('admin login', admin.status === 200 && admin.data.token);
  const adminTok = admin.data.token;

  console.log('\n=== 2. MEMBER REGISTER + OTP + LOGIN ===');
  const mReg = await api('POST', '/api/auth/register/member', {
    email: `m${uniq}@x.com`, phone: `0790${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Lina', lastName: 'A', nationality: 'Jordanian', location: 'Amman', dateOfBirth: '1995-04-10',
    birthPlace: 'Amman', nationality: 'Jordan',
    assessment: { goal: 'Lose weight', level: 'beginner' },
  });
  check('member register', mReg.status === 201 && mReg.data.devOtp, JSON.stringify(mReg.data));
  const mVerify = await api('POST', '/api/auth/verify', { userId: mReg.data.user.id, code: mReg.data.devOtp, channel: 'phone' });
  check('member OTP verify', mVerify.data.verified === true);
  const mLogin = await api('POST', '/api/auth/login', { email: `m${uniq}@x.com`, password: 'secret12' });
  const memberTok = mLogin.data.token;
  check('member completes their profile', (await completeMemberProfile(memberTok, 'Amman')).status === 200);
  check('member login', !!memberTok);

  console.log('\n=== 3. COACHES REGISTER; A APPROVED NOW, B APPROVED LATER ===');
  const cReg = await api('POST', '/api/auth/register/coach', {
    email: `c${uniq}@x.com`, phone: `0791${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Omar', lastName: 'K', nationality: 'Jordanian', dateOfBirth: '1990-05-01', nationality: 'Jordanian',
    bio: 'Certified strength coach, 6 years.',
    documents: [
      { docType: 'degree_certificate', fileName: 'degree.pdf', mimeType: 'application/pdf', dataBase64: pdfB64 },
      { docType: 'experience_proof', fileName: 'exp.pdf', mimeType: 'application/pdf', dataBase64: pdfB64 },
    ],
  });
  check('coach A register with documents', cReg.status === 201, JSON.stringify(cReg.data));
  const cLogin = await api('POST', '/api/auth/login', { email: `c${uniq}@x.com`, password: 'secret12' });
  const coachTok = cLogin.data.token;
  const coachId = cReg.data.user.id;

  const c2Reg = await api('POST', '/api/auth/register/coach', {
    email: `c2${uniq}@x.com`, phone: `0792${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Sara', lastName: 'M', nationality: 'Jordanian', dateOfBirth: '1992-02-02', nationality: 'Jordanian',
    bio: 'Yoga & mobility.',
  });
  const coach2Id = c2Reg.data.user.id;
  const c2Login = await api('POST', '/api/auth/login', { email: `c2${uniq}@x.com`, password: 'secret12' });
  const coach2Tok = c2Login.data.token;

  const pending = await api('GET', '/api/admin/coaches/pending', null, adminTok);
  check('coach appears in pending list', pending.data.some((c) => c.user_id === coachId));
  const docs = await api('GET', `/api/admin/coaches/${coachId}/documents`, null, adminTok);
  check('admin lists coach documents', docs.status === 200 && docs.data.length === 2);
  check('admin approves coach A', (await api('POST', `/api/admin/coaches/${coachId}/approve`, {}, adminTok)).data.status === 'approved');

  console.log('\n=== 3b. ADMIN DOCUMENT VIEWING (v0.4) ===');
  const docId = docs.data[0].id;
  const dlHeader = await apiRaw(`/api/admin/documents/${docId}/download`, adminTok);
  check('document download with auth header', dlHeader.status === 200 && /pdf/.test(dlHeader.contentType || ''));
  const dlQuery = await apiRaw(`/api/admin/documents/${docId}/download`, adminTok, true);
  check('document download with ?token=', dlQuery.status === 200 && dlQuery.bytes.length > 5);
  check('document download rejects non-admin', (await apiRaw(`/api/admin/documents/${docId}/download`, memberTok, true)).status === 403);

  console.log('\n=== 4. PER-WEEK AVAILABILITY CALENDAR (v0.14 item 16) ===');
  const dateEve = datePlus(1);   // evening online hours, tomorrow
  const dateIP = datePlus(2);    // in-person hours
  const dateTog = datePlus(3);   // used later for the clear/edit tests
  const dateB = datePlus(1);     // coach B

  const av0 = await api('GET', '/api/coaches/availability/week', null, coachTok);
  check('week view returns 7 dated days and the 50-min default',
    av0.status === 200 && av0.data.sessionMinutes === 50 && av0.data.days.length === 7
    && av0.data.days.every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d.date)),
    JSON.stringify(av0.data).slice(0, 140));
  check('week starts on a Monday', new Date(`${av0.data.weekStart}T00:00:00Z`).getUTCDay() === 1);
  check('a fresh week has no hours set', av0.data.days.every((d) => d.blocks.length === 0));

  const r1 = await api('POST', '/api/coaches/availability/day',
    { date: dateEve, startTime: '20:00', endTime: '23:00', delivery: 'online' }, coachTok);
  check('coach A paints evening hours -> sessions generated', r1.status === 201 && r1.data.generated > 0, JSON.stringify(r1.data));
  const blockEveId = r1.data.block.id;
  const r2 = await api('POST', '/api/coaches/availability/day',
    { date: dateIP, startTime: '10:00', endTime: '12:00', delivery: 'in_person' }, coachTok);
  check('coach A adds in-person hours', r2.status === 201 && r2.data.generated > 0);
  const r3 = await api('POST', '/api/coaches/availability/day',
    { date: dateTog, startTime: '09:00', endTime: '11:00', delivery: 'online' }, coachTok);
  check('coach A adds a third day of hours', r3.status === 201);
  const blockTogId = r3.data.block.id;

  // More evening days, so the later booking/cancellation tests have enough
  // open online slots to work with.
  const extraEveIds = [];
  for (const d of [4, 5, 6, 7]) {
    const extra = await api('POST', '/api/coaches/availability/day',
      { date: datePlus(d), startTime: '20:00', endTime: '23:00', delivery: 'online' }, coachTok);
    if (extra.status === 201) extraEveIds.push(extra.data.block.id);
  }
  check('coach A has a full week of evening hours', extraEveIds.length === 4, `n=${extraEveIds.length}`);
  const onlineBlockIds = [blockEveId, ...extraEveIds];

  const overlap = await api('POST', '/api/coaches/availability/day',
    { date: dateEve, startTime: '21:00', endTime: '22:00', delivery: 'online' }, coachTok);
  check('overlapping hours on the same date rejected', overlap.status === 409, JSON.stringify(overlap.data));
  const badTimes = await api('POST', '/api/coaches/availability/day',
    { date: dateEve, startTime: '23:00', endTime: '22:00', delivery: 'online' }, coachTok);
  check('end-before-start rejected', badTimes.status === 400);
  const pastDay = await api('POST', '/api/coaches/availability/day',
    { date: datePlus(-3), startTime: '09:00', endTime: '10:00', delivery: 'online' }, coachTok);
  check('hours cannot be set on a past date', pastDay.status === 400);

  const av1 = await api('GET', `/api/coaches/availability/week?start=${dateEve}`, null, coachTok);
  const eveDay = av1.data.days.find((d) => d.date === dateEve);
  check('week view shows the painted hours on the right date', !!eveDay && eveDay.blocks.length === 1);

  let mySessions = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  const eveSessions = mySessions.filter((s) => s.generated_from_day === blockEveId)
    .sort((a, b) => new Date(a.start_at) - new Date(b.start_at));
  // 20:00-23:00 @ 50 min => 20:00, 20:50, 21:40 on that one date
  check('evening hours generated 3 sessions', eveSessions.length === 3, `n=${eveSessions.length}`);
  check('sessions spaced 50 minutes (default duration)', minutesBetween(eveSessions[0].start_at, eveSessions[1].start_at) === 50,
    `${eveSessions[0].start_at} -> ${eveSessions[1].start_at}`);
  check('generated sessions are 1-on-1 online', eveSessions[0].capacity === 1 && eveSessions[0].delivery === 'online');

  console.log('\n=== 4a. COPY LAST WEEK (v0.14 item 16) ===');
  const nextWeekTarget = datePlus(8);
  const copied = await api('POST', '/api/coaches/availability/copy-week', { targetWeek: nextWeekTarget }, coachTok);
  check('copy-week duplicates the previous week\'s hours', copied.status === 200 && copied.data.copied >= 1, JSON.stringify(copied.data));
  const copiedWeek = await api('GET', `/api/coaches/availability/week?start=${nextWeekTarget}`, null, coachTok);
  check('copied hours appear in the target week',
    copiedWeek.data.days.some((d) => d.blocks.length > 0));
  const copyAgain = await api('POST', '/api/coaches/availability/copy-week', { targetWeek: nextWeekTarget }, coachTok);
  check('copying twice does not duplicate hours', copyAgain.status === 200 && copyAgain.data.copied === 0, JSON.stringify(copyAgain.data));

  console.log('\n=== 4b. COACH LOCKED UNTIL APPROVED (v0.14 item 3) ===');
  const rB = await api('POST', '/api/coaches/availability/day',
    { date: dateB, startTime: '18:00', endTime: '20:00', delivery: 'online' }, coach2Tok);
  check('unapproved coach cannot set availability', rB.status === 403 && /approval/i.test(rB.data.error || ''), JSON.stringify(rB.data));
  check('unapproved coach cannot see their sessions',
    (await api('GET', '/api/coaches/my-sessions', null, coach2Tok)).status === 403);
  check('unapproved coach cannot open their dashboard',
    (await api('GET', '/api/coaches/dashboard', null, coach2Tok)).status === 403);
  check('admin approves coach B', (await api('POST', `/api/admin/coaches/${coach2Id}/approve`, {}, adminTok)).data.status === 'approved');
  const rB2 = await api('POST', '/api/coaches/availability/day',
    { date: dateB, startTime: '18:00', endTime: '20:00', delivery: 'online' }, coach2Tok);
  check('approved coach can now set availability', rB2.status === 201 && rB2.data.generated > 0, JSON.stringify(rB2.data));
  // Hours beyond the 2-week single-package validity, for the expiry test later.
  const rB3 = await api('POST', '/api/coaches/availability/day',
    { date: datePlus(20), startTime: '18:00', endTime: '20:00', delivery: 'online' }, coach2Tok);
  check('coach B also sets hours three weeks out', rB3.status === 201 && rB3.data.generated > 0);
  let bSessions = (await api('GET', '/api/coaches/my-sessions', null, coach2Tok)).data;
  check('approval unlocks session generation', bSessions.length > 0, `n=${bSessions.length}`);

  console.log('\n=== 4c. DURATION CHANGE REBUILDS THE GRID ===');
  const durBad = await api('PUT', '/api/coaches/availability/settings', { sessionMinutes: 40 }, coach2Tok);
  check('invalid duration rejected', durBad.status === 400);
  const dur60 = await api('PUT', '/api/coaches/availability/settings', { sessionMinutes: 60 }, coach2Tok);
  check('coach B switches to 60-min sessions', dur60.status === 200 && dur60.data.generated > 0, JSON.stringify(dur60.data));
  bSessions = (await api('GET', '/api/coaches/my-sessions', null, coach2Tok)).data
    .sort((a, b) => new Date(a.start_at) - new Date(b.start_at));
  check('coach B sessions now spaced 60 minutes', minutesBetween(bSessions[0].start_at, bSessions[1].start_at) === 60,
    `${bSessions[0].start_at} -> ${bSessions[1].start_at}`);

  // Pick concrete sessions for the booking tests.
  mySessions = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  const aOnline = mySessions.filter((s) => onlineBlockIds.includes(s.generated_from_day))
    .sort((a, b) => new Date(a.start_at) - new Date(b.start_at));
  const aInPerson = mySessions.filter((s) => s.delivery === 'in_person')
    .sort((a, b) => new Date(a.start_at) - new Date(b.start_at));
  const sessionA1 = aOnline[0].id, sessionA2 = aOnline[1].id, sessionA3 = aOnline[2].id;
  const sessionAIP = aInPerson[0].id;
  const sessionB1 = bSessions[0].id;

  console.log('\n=== 5. NO PACKAGE => BOOKING BLOCKED ===');
  const noPkg = await api('POST', '/api/bookings', { sessionId: sessionA1 }, memberTok);
  check('booking without any package blocked (402)', noPkg.status === 402, JSON.stringify(noPkg.data));

  console.log('\n=== 6. PAYMENT NOTE BEFORE PROOF (v0.5 item 2) + PURCHASE ===');
  const note = await api('GET', '/api/members/payment-note', null, memberTok);
  check('member fetches bank details before uploading proof', note.status === 200 && (note.data.body_en || '').length > 0, JSON.stringify(note.data).slice(0, 80));

  const cat = await api('GET', '/api/members/packages/catalogue', null, memberTok);
  check('catalogue split by mode (8 items)', cat.data.length === 8, `len=${cat.data.length}`);
  const pkg6 = cat.data.find((p) => p.class_count === 6 && p.mode === 'online' && !p.is_single);
  const singleOnline = cat.data.find((p) => p.is_single && p.mode === 'online');

  const noProof = await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId }, memberTok);
  check('request without proof rejected', noProof.status === 400 && /proof/i.test(noProof.data.error || ''));
  const reqPkg = await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId, proof }, memberTok);
  check('package request with coach + proof -> pending', reqPkg.status === 201 && reqPkg.data.package.status === 'pending_payment');
  check('package bound to coach', reqPkg.data.package.coach_id === coachId);
  const memberPkgId = reqPkg.data.package.id;
  check('second concurrent package with SAME coach blocked',
    (await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId, proof }, memberTok)).status === 409);

  console.log('\n=== 6b. PAYMENT PROOF LIFECYCLE ===');
  const pendingList = await api('GET', '/api/admin/packages/pending', null, adminTok);
  const pRow = pendingList.data.find((p) => p.id === memberPkgId);
  check('pending list shows proof metadata + names', !!pRow && pRow.has_proof === true && pRow.member_first === 'Lina');
  const proofDl = await apiRaw(`/api/admin/packages/${memberPkgId}/payment-proof`, adminTok);
  check('admin views proof image bytes', proofDl.status === 200 && /image\/png/.test(proofDl.contentType || ''));
  const rejPay = await api('POST', `/api/admin/packages/${memberPkgId}/reject-payment`, { reason: 'Amount does not match' }, adminTok);
  check('admin rejects proof with reason', rejPay.status === 200);
  let mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('member sees rejection reason, still pending', mine.status === 'pending_payment' && /Amount/.test(mine.payment_rejection_reason || ''));
  check('member re-uploads proof', (await api('POST', `/api/members/packages/${memberPkgId}/proof`, { proof }, memberTok)).status === 200);
  const act = await api('POST', `/api/admin/packages/${memberPkgId}/activate`, {}, adminTok);
  check('admin activates package; expiry set', act.status === 200 && act.data.status === 'active' && !!act.data.expires_at);

  console.log('\n=== 7. COACH-BOUND BOOKING RULES ===');
  const wrongCoach = await api('POST', '/api/bookings', { sessionId: sessionB1 }, memberTok);
  check('booking a DIFFERENT coach with coach-A package blocked', wrongCoach.status === 409 && /different coach/i.test(wrongCoach.data.error || ''));
  const wrongMode = await api('POST', '/api/bookings', { sessionId: sessionAIP }, memberTok);
  check('online package cannot book in-person (popup message text)', wrongMode.status === 409 && /only book an online session/i.test(wrongMode.data.error || ''));

  console.log('\n=== 8. COUNTER LOGIC (spec §7) ===');
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('initial remaining=6 pending=0', Number(mine.remaining) === 6 && Number(mine.pending) === 0);
  const b2 = await api('POST', '/api/bookings', { sessionId: sessionA2 }, memberTok);
  check('book against coach-A package', b2.status === 201, JSON.stringify(b2.data));
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('after booking remaining=6 pending=1 (hold)', Number(mine.remaining) === 6 && Number(mine.pending) === 1);
  check('coach accepts', (await api('POST', `/api/bookings/${b2.data.id}/decision`, { accept: true }, coachTok)).data.status === 'accepted');
  // (v0.7 item 2) Completing BEFORE the session ends is rejected.
  const tooEarly = await api('POST', `/api/bookings/${b2.data.id}/complete`, {}, coachTok);
  check('complete before session end blocked (anti-fraud)', tooEarly.status === 409 && /not ended/i.test(tooEarly.data.error || ''), JSON.stringify(tooEarly.data));
  await endSessionInPast(sessionA2);
  const done2 = await api('POST', `/api/bookings/${b2.data.id}/complete`, {}, coachTok);
  check('coach completes after session end', done2.data.status === 'completed' && done2.data.completion_kind === 'coach', JSON.stringify(done2.data));
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('after completion remaining=5 pending=0 (deduction)', Number(mine.remaining) === 5 && Number(mine.pending) === 0);

  console.log('\n=== 9. REVIEW ONLY AFTER COMPLETION ===');
  check('review completed session', (await api('POST', `/api/bookings/${b2.data.id}/review`, { rating: 5, comment: 'Great' }, memberTok)).status === 201);
  const revBad = await api('POST', `/api/bookings/${sessionA3}/review`, { rating: 5 }, memberTok);
  check('review on non-booking rejected', revBad.status === 404 || revBad.status === 409);

  console.log('\n=== 10. REJECTION RELEASES HOLD ===');
  const b3 = await api('POST', '/api/bookings', { sessionId: sessionA3 }, memberTok);
  check('coach rejects with reason', (await api('POST', `/api/bookings/${b3.data.id}/decision`, { accept: false, rejectionReason: 'Unavailable' }, coachTok)).data.status === 'rejected');
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('after rejection remaining=5 pending=0 (no deduction)', Number(mine.remaining) === 5 && Number(mine.pending) === 0);

  console.log('\n=== 11. SINGLE = ONE PAID TRIAL PER COACH + EXPIRY WINDOW ===');
  const reqSingleB = await api('POST', '/api/members/packages/request', { packageDefId: singleOnline.id, coachId: coach2Id, proof }, memberTok);
  check('single trial with coach B allowed', reqSingleB.status === 201);
  const singleBId = reqSingleB.data.package.id;
  await api('POST', `/api/admin/packages/${singleBId}/activate`, {}, adminTok);
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === singleBId);
  // The single is valid 2 weeks; the horizon is 4 weeks, so a session beyond
  // the expiry exists — booking it must be blocked (spec §9.5).
  const expiresAt = new Date(mine.expires_at);
  bSessions = (await api('GET', '/api/coaches/my-sessions', null, coach2Tok)).data;
  const farB = bSessions.find((s) => new Date(s.start_at) > expiresAt);
  check('a generated session beyond the 2-week expiry exists', !!farB);
  const farBook = await api('POST', '/api/bookings', { sessionId: farB.id }, memberTok);
  check('cannot book session after package expiry', farBook.status === 400, JSON.stringify(farBook.data));

  const bB1 = await api('POST', '/api/bookings', { sessionId: sessionB1 }, memberTok);
  check('book coach B with coach-B single', bB1.status === 201, JSON.stringify(bB1.data));
  await api('POST', `/api/bookings/${bB1.data.id}/decision`, { accept: true }, coach2Tok);
  await endSessionInPast(sessionB1);
  await api('POST', `/api/bookings/${bB1.data.id}/complete`, {}, coach2Tok);
  check('second single with SAME coach blocked permanently',
    (await api('POST', '/api/members/packages/request', { packageDefId: singleOnline.id, coachId: coach2Id, proof }, memberTok)).status === 409);
  const pkgAfterSingle = await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId: coach2Id, proof }, memberTok);
  check('regular package with coach B allowed after single exhausted', pkgAfterSingle.status === 201);

  console.log('\n=== 12. REASSIGN + CANCELLED SINGLE ALLOWANCE ===');
  const m2Reg = await api('POST', '/api/auth/register/member', {
    email: `m2${uniq}@x.com`, phone: `0793${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Rana', lastName: 'B', nationality: 'Jordanian', location: 'Irbid',
  });
  const m2Login = await api('POST', '/api/auth/login', { email: `m2${uniq}@x.com`, password: 'secret12' });
  const member2Tok = m2Login.data.token;
  await completeMemberProfile(member2Tok, 'Irbid');
  const m2Single = await api('POST', '/api/members/packages/request', { packageDefId: singleOnline.id, coachId, proof }, member2Tok);
  check('member2 requests single with coach A', m2Single.status === 201);
  await api('POST', `/api/admin/packages/${m2Single.data.package.id}/reject`, {}, adminTok);
  const m2SingleAgain = await api('POST', '/api/members/packages/request', { packageDefId: singleOnline.id, coachId, proof }, member2Tok);
  check('cancelled single can be requested again (allowance preserved)', m2SingleAgain.status === 201);
  const noReason = await api('POST', `/api/admin/member-packages/${m2SingleAgain.data.package.id}/reassign`, { coachId: coach2Id }, adminTok);
  check('reassign without a reason rejected (v0.9 audit trail)', noReason.status === 400);
  const reassignOk = await api('POST', `/api/admin/member-packages/${m2SingleAgain.data.package.id}/reassign`,
    { coachId: coach2Id, reason: 'Member requested a different coach' }, adminTok);
  check('reassign pending package to coach B', reassignOk.status === 200 && reassignOk.data.coach_id === coach2Id, JSON.stringify(reassignOk.data));
  const reassignConflict = await api('POST', `/api/admin/member-packages/${memberPkgId}/reassign`,
    { coachId: coach2Id, reason: 'test' }, adminTok);
  check('reassign blocked when member already has a package with target coach', reassignConflict.status === 409);

  console.log('\n=== 13. COACH CLIENTS: ACTIVE vs COMPLETED ===');
  const clientsA = await api('GET', '/api/coaches/clients', null, coachTok);
  const rowA = (clientsA.data || []).find((r) => r.package_id === memberPkgId);
  check('coach A sees member1 as ACTIVE client with contact', !!rowA && rowA.is_completed === false && !!rowA.phone);
  const clientsB = await api('GET', '/api/coaches/clients', null, coach2Tok);
  const rowB = (clientsB.data || []).find((r) => r.package_id === singleBId);
  check('coach B sees exhausted single under COMPLETED', !!rowB && rowB.is_completed === true);

  console.log('\n=== 14. COACH DASHBOARD ===');
  const dash = await api('GET', '/api/coaches/dashboard?days=30', null, coachTok);
  check('dashboard stats respond', dash.status === 200 && dash.data.completed >= 1 && dash.data.activeClients >= 1);
  check('dashboard: no revenue fields exposed', !('revenue' in dash.data) && !('earnings' in dash.data));

  console.log('\n=== 15. ADMIN DETAILED REPORTS ===');
  const det = await api('GET', '/api/admin/reports/detailed?days=30', null, adminTok);
  const t = det.data.totals || {};
  check('detailed report totals present', det.status === 200 && Number(t.revenue_in_range) > 0 && Number(t.sessions_in_range) >= 2);
  check('coach leaderboard present', Array.isArray(det.data.coachLeaderboard) && det.data.coachLeaderboard.length >= 2);

  console.log('\n=== 16. COACH SEES CONTACT + ZOOM ON ACCEPTED ===');
  const bA = await api('POST', '/api/bookings', { sessionId: sessionA1 }, memberTok);
  check('book online session A1', bA.status === 201, JSON.stringify(bA.data));
  await api('POST', `/api/bookings/${bA.data.id}/decision`, { accept: true }, coachTok);
  const cbk = (await api('GET', '/api/coaches/bookings', null, coachTok)).data.find((b) => b.id === bA.data.id);
  check('coach sees member phone + location once accepted', !!cbk.member_phone && cbk.member_location === 'Amman');
  check('coach sees zoom link (placeholder in dev)', !!cbk.zoom_join_url);
  check('coach booking carries member_id (opens member detail)', !!cbk.member_id);
  const mbk = (await api('GET', '/api/members/bookings', null, memberTok)).data.find((b) => b.id === bA.data.id);
  check('member also sees zoom link when accepted', !!mbk.zoom_join_url);

  console.log('\n=== 17. PRE-BOOK CAP = 3 ===');
  // member1 has 1 upcoming accepted (A1). Two more allowed, 4th blocked.
  const capPool = aOnline.slice(3, 6).map((s) => s.id);
  const c1 = await api('POST', '/api/bookings', { sessionId: capPool[0] }, memberTok);
  const c2 = await api('POST', '/api/bookings', { sessionId: capPool[1] }, memberTok);
  check('2nd and 3rd upcoming bookings allowed', c1.status === 201 && c2.status === 201, JSON.stringify(c2.data));
  const c3 = await api('POST', '/api/bookings', { sessionId: capPool[2] }, memberTok);
  check('4th upcoming booking blocked by cap', c3.status === 409 && /3 upcoming/i.test(c3.data.error || ''));

  console.log('\n=== 18. EARLY CANCEL (no deduction) ===');
  const early = await api('POST', `/api/bookings/${c2.data.id}/cancel`, {}, memberTok);
  check('early cancel (future date) -> no deduction', early.status === 200 && early.data.cancel_kind === 'early');
  mine = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('after early cancel remaining unchanged', Number(mine.remaining) === 5);

  console.log('\n=== 19. AVAILABILITY CLEANUP RULES (v0.5 item 5) ===');
  // Book one session on that day, then edit/delete those hours: the booked
  // session must be KEPT, its unbooked siblings removed.
  mySessions = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  const togSessions = mySessions.filter((s) => s.generated_from_day === blockTogId);
  check('that day generated sessions', togSessions.length >= 2, `n=${togSessions.length}`);
  const togBook = await api('POST', '/api/bookings', { sessionId: togSessions[0].id }, memberTok);
  check('member books one of those sessions', togBook.status === 201, JSON.stringify(togBook.data));
  // Editing the hours rebuilds unbooked sessions and keeps booked ones.
  const rEdit = await api('PUT', `/api/coaches/availability/day/${blockTogId}`,
    { startTime: '08:00', endTime: '11:00' }, coachTok);
  check('editing hours: regenerates, keeps the booked session',
    rEdit.status === 200 && rEdit.data.generated > 0 && rEdit.data.keptBooked === 1, JSON.stringify(rEdit.data));

  // Deleting the block removes its future unbooked sessions; booked stays.
  const delDay = await api('DELETE', `/api/coaches/availability/day/${blockTogId}`, null, coachTok);
  check('deleting hours: unbooked removed, booked kept',
    delDay.status === 200 && delDay.data.keptBooked === 1, JSON.stringify(delDay.data));
  const avAfter = await api('GET', `/api/coaches/availability/week?start=${dateTog}`, null, coachTok);
  check('deleted hours gone from the week view',
    avAfter.data.days.find((d) => d.date === dateTog).blocks.length === 0);
  // The kept booked session survives the range deletion (provenance nulled).
  mySessions = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  check('booked session survives range deletion', mySessions.some((s) => s.id === togSessions[0].id));
  // Tidy: cancel that booking so later counts are unaffected.
  await api('POST', `/api/bookings/${togBook.data.id}/cancel`, {}, memberTok);

  console.log('\n=== 20. ONE-OFF SESSION DELETE (kept from v0.1) ===');
  mySessions = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  // Pick a slot with no booking HISTORY at all (a rejected booking leaves
  // booked=0 but deleting the session would cascade the booking row away).
  const touched = new Set([sessionA1, sessionA2, sessionA3, ...capPool]);
  const unbooked = mySessions.find((s) => onlineBlockIds.includes(s.generated_from_day) && Number(s.booked) === 0 && !touched.has(s.id));
  const removeOne = await api('DELETE', `/api/coaches/availability/${unbooked.id}`, null, coachTok);
  check('coach removes a single unbooked generated session', removeOne.status === 200 && removeOne.data.removed);
  const removeBooked = await api('DELETE', `/api/coaches/availability/${sessionA2}`, null, coachTok);
  check('coach cannot remove a booked session', removeBooked.status === 409);

  console.log('\n=== 21. CHANGE PASSWORD (in-app) ===');
  const okPw = await api('POST', '/api/auth/change-password', { oldPassword: 'secret12', newPassword: 'newsecret12', confirmPassword: 'newsecret12' }, memberTok);
  check('password changed', okPw.status === 200 && okPw.data.changed === true);
  check('login with new password works', (await api('POST', '/api/auth/login', { email: `m${uniq}@x.com`, password: 'newsecret12' })).status === 200);

  console.log('\n=== 22. FORGOT PASSWORD (v0.5 item 1) ===');
  const unknown = await api('POST', '/api/auth/forgot-password', { email: `nobody${uniq}@x.com` });
  check('unknown email: neutral message, no code', unknown.status === 200 && /if this email is registered/i.test(unknown.data.message || '') && unknown.data.devCode === undefined,
    JSON.stringify(unknown.data));
  const adminProbe = await api('POST', '/api/auth/forgot-password', { email: 'admin@fitness.local' });
  check('admin email: same neutral message, no code (members/coaches only)', adminProbe.status === 200 && adminProbe.data.devCode === undefined);
  const badEmailFp = await api('POST', '/api/auth/forgot-password', { email: 'notanemail' });
  check('invalid email format rejected', badEmailFp.status === 400);

  const fp1 = await api('POST', '/api/auth/forgot-password', { email: `m${uniq}@x.com` });
  check('known member email: neutral message + 6-char dev code', fp1.status === 200 && /^[A-Z0-9]{6}$/.test(fp1.data.devCode || ''), JSON.stringify(fp1.data));
  const code1 = fp1.data.devCode;
  const fp2 = await api('POST', '/api/auth/forgot-password', { email: `m${uniq}@x.com` });
  const code2 = fp2.data.devCode;
  const oldCode = await api('POST', '/api/auth/verify-reset-code', { email: `m${uniq}@x.com`, code: code1 });
  check('requesting a new code invalidates the old one', oldCode.status === 400, JSON.stringify(oldCode.data));

  for (let i = 0; i < 5; i++) {
    await api('POST', '/api/auth/verify-reset-code', { email: `m${uniq}@x.com`, code: 'WRONG0' });
  }
  const afterAttempts = await api('POST', '/api/auth/verify-reset-code', { email: `m${uniq}@x.com`, code: code2 });
  check('correct code blocked after 5 wrong attempts', afterAttempts.status === 400);

  const fp3 = await api('POST', '/api/auth/forgot-password', { email: `m${uniq}@x.com` });
  const verified = await api('POST', '/api/auth/verify-reset-code', { email: `m${uniq}@x.com`, code: fp3.data.devCode });
  check('valid code exchanges for a reset token', verified.status === 200 && !!verified.data.resetToken, JSON.stringify(verified.data));
  const resetToken = verified.data.resetToken;

  const mismatch = await api('POST', '/api/auth/reset-password',
    { resetToken, newPassword: 'resetpw123', confirmPassword: 'other12345' });
  check('confirmation mismatch rejected', mismatch.status === 400);
  const short = await api('POST', '/api/auth/reset-password',
    { resetToken, newPassword: 'short', confirmPassword: 'short' });
  check('short password rejected', short.status === 400);
  const good = await api('POST', '/api/auth/reset-password',
    { resetToken, newPassword: 'resetpw123', confirmPassword: 'resetpw123' });
  check('reset with a valid token succeeds', good.status === 200, JSON.stringify(good.data));
  check('login with reset password works',
    (await api('POST', '/api/auth/login', { email: `m${uniq}@x.com`, password: 'resetpw123' })).status === 200);
  const reuse = await api('POST', '/api/auth/reset-password',
    { resetToken, newPassword: 'again12345', confirmPassword: 'again12345' });
  check('reset token is single-use', reuse.status === 400);
  const noToken = await api('POST', '/api/auth/reset-password',
    { newPassword: 'again12345', confirmPassword: 'again12345' });
  check('reset without a token rejected', noToken.status === 400);

  const coachFp = await api('POST', '/api/auth/forgot-password', { email: `c${uniq}@x.com` });
  check('coach can also request a reset code', coachFp.status === 200 && /^[A-Z0-9]{6}$/.test(coachFp.data.devCode || ''));

  console.log('\n=== 23. QUESTIONNAIRE + LOCATIONS + SETTINGS (regression) ===');
  check('default questionnaire has 5 questions', (await api('GET', '/api/auth/questionnaire', null, null)).data.length === 5);
  const locs = await api('GET', '/api/auth/locations', null, null);
  check('public locations list (>=12 Jordan cities)', locs.status === 200 && locs.data.length >= 12);
  const getSettings = await api('GET', '/api/admin/settings', null, adminTok);
  check('admin reads platform settings', getSettings.status === 200 && getSettings.data.timezone === 'Asia/Amman');

  console.log('\n=== 24. PACKAGE EDIT — NO RETROACTIVE CHANGE ===');
  const allPkgs = await api('GET', '/api/admin/packages', null, adminTok);
  const pkgToEdit = allPkgs.data.find((p) => p.class_count === 9 && p.mode === 'online');
  const editPkg = await api('PUT', `/api/admin/packages/${pkgToEdit.id}`, { price: 199.99 }, adminTok);
  check('admin edits package def price', editPkg.status === 200 && Number(editPkg.data.price) === 199.99);
  const stillSnap = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('purchased package keeps snapshot', Number(stillSnap.price) === 90);

  console.log('\n=== 25. VALIDATION + PHONE NORMALIZATION (regression) ===');
  const badPhone = await api('POST', '/api/auth/register/member', { email: `p${uniq}@x.com`, phone: '12345', password: 'secret12', firstName: 'X', lastName: 'Y' });
  check('invalid phone rejected', badPhone.status === 400);
  const memSumPhone = await api('GET', `/api/admin/members/${mReg.data.user.id}/summary`, null, adminTok);
  check('phone stored as 009627XXXXXXXX', /^009627\d{8}$/.test(memSumPhone.data.profile.phone));
  check('member summary includes package list with coach (v0.4)', (memSumPhone.data.packages || []).some((p) => p.coach_first === 'Omar'));

  console.log('\n=== 25c. NO-SHOW + AUTO-COMPLETE (v0.7 item 2) ===');
  // Fresh future sessions of coach A for these flows.
  // (v0.7 bug fix) Sessions whose earlier booking was cancelled or rejected
  // are open again and CAN be re-booked by the same member — the old global
  // unique constraint made that a raw 500. We deliberately reuse them here:
  const nsSession = capPool[1];   // member cancelled this one earlier
  const acSession = sessionA3;    // coach rejected this one earlier

  // -- no-show flow: class still deducted, review blocked, member sees the kind
  const minesBefore = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  const consumedBefore = Number(minesBefore.remaining);
  const bNS = await api('POST', '/api/bookings', { sessionId: nsSession }, memberTok);
  check('book session for no-show test', bNS.status === 201, JSON.stringify(bNS.data));
  await api('POST', `/api/bookings/${bNS.data.id}/decision`, { accept: true }, coachTok);
  const earlyNS = await api('POST', `/api/bookings/${bNS.data.id}/complete`, { noShow: true }, coachTok);
  check('no-show before session end also blocked', earlyNS.status === 409);
  await endSessionInPast(nsSession);
  const ns = await api('POST', `/api/bookings/${bNS.data.id}/complete`, { noShow: true }, coachTok);
  check('no-show recorded after session end', ns.status === 200 && ns.data.completion_kind === 'no_show', JSON.stringify(ns.data));
  const minesAfter = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('no-show still deducts the class', Number(minesAfter.remaining) === consumedBefore - 1,
    `before=${consumedBefore} after=${minesAfter.remaining}`);
  const revNS = await api('POST', `/api/bookings/${bNS.data.id}/review`, { rating: 5 }, memberTok);
  check('review blocked for no-show', revNS.status === 409 && /no-show/i.test(revNS.data.error || ''));
  const memNS = (await api('GET', '/api/members/bookings?scope=history', null, memberTok)).data.find((b) => b.id === bNS.data.id);
  check('member sees the no-show kind in history', memNS && memNS.completion_kind === 'no_show');

  // -- auto-complete: accepted + ended >48h ago -> completed by the job
  const bAC = await api('POST', '/api/bookings', { sessionId: acSession }, memberTok);
  check('book session for auto-complete test', bAC.status === 201, JSON.stringify(bAC.data));
  await api('POST', `/api/bookings/${bAC.data.id}/decision`, { accept: true }, coachTok);
  await endSessionInPast(acSession, 50); // ended 50h ago (>48h window)
  const { autoCompleteOverdue } = require('../src/services/booking.service_v0_13');
  const autoN = await autoCompleteOverdue();
  check('auto-complete job completed the overdue booking', autoN >= 1, `n=${autoN}`);
  const acRow = (await api('GET', '/api/members/bookings?scope=history', null, memberTok)).data.find((b) => b.id === bAC.data.id);
  check('overdue booking is completed with kind=auto', acRow && acRow.status === 'completed' && acRow.completion_kind === 'auto', JSON.stringify(acRow || {}));
  check('auto-completed session can be reviewed',
    (await api('POST', `/api/bookings/${bAC.data.id}/review`, { rating: 4, comment: 'ok' }, memberTok)).status === 201);

  console.log('\n=== 25b. ARCHIVES + OPEN-SLOT FILTERS (v0.6) ===');
  // Item 4: members no longer see sessions that are pending/accepted/completed.
  const visibleA = (await api('GET', `/api/members/coaches/${coachId}/sessions`, null, memberTok)).data;
  const visibleIds = new Set(visibleA.map((x) => x.id));
  check('member listing hides ACCEPTED session', !visibleIds.has(sessionA1));
  check('member listing hides PENDING session', !visibleIds.has(capPool[0]));
  check('member listing hides COMPLETED session', !visibleIds.has(sessionA2));
  check('member listing still shows open sessions', visibleA.length > 0);
  check('every visible session is future + unbooked',
    visibleA.every((x) => Number(x.booked) === 0 && new Date(x.start_at) > new Date()));

  // Item 3: coach Sessions tab = open slots only.
  const openSlots = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data;
  const openIds = new Set(openSlots.map((x) => x.id));
  check('scope=open excludes accepted/pending/completed slots',
    !openIds.has(sessionA1) && !openIds.has(capPool[0]) && !openIds.has(sessionA2));
  check('scope=open returns only unbooked future slots',
    openSlots.length > 0 && openSlots.every((x) => Number(x.booked) === 0 && new Date(x.start_at) > new Date()));
  const allSlots = (await api('GET', '/api/coaches/my-sessions', null, coachTok)).data;
  check('no scope still returns everything (compat)', allSlots.length > openSlots.length);

  // Item 2: bookings upcoming vs history.
  const up = (await api('GET', '/api/members/bookings?scope=upcoming', null, memberTok)).data;
  const upIds = new Set(up.map((x) => x.id));
  check('upcoming contains accepted + pending future bookings', upIds.has(bA.data.id) && upIds.has(c1.data.id));
  check('upcoming excludes completed/cancelled/rejected',
    !upIds.has(b2.data.id) && !upIds.has(c2.data.id) && !upIds.has(b3.data.id));
  const hist = (await api('GET', '/api/members/bookings?scope=history', null, memberTok)).data;
  const histIds = new Set(hist.map((x) => x.id));
  check('history contains completed, cancelled and rejected',
    histIds.has(b2.data.id) && histIds.has(c2.data.id) && histIds.has(b3.data.id));
  check('history excludes upcoming', !histIds.has(bA.data.id));

  // Item 1: packages active vs past.
  const actPkgs = (await api('GET', '/api/members/packages/mine?scope=active', null, memberTok)).data;
  const actIds = new Set(actPkgs.map((x) => x.id));
  const pastPkgs = (await api('GET', '/api/members/packages/mine?scope=past', null, memberTok)).data;
  const pastIds = new Set(pastPkgs.map((x) => x.id));
  check('active scope has the in-use package, not the exhausted single',
    actIds.has(memberPkgId) && !actIds.has(singleBId));
  check('past scope has the exhausted single, not the in-use package',
    pastIds.has(singleBId) && !pastIds.has(memberPkgId));
  check('no scope returns all packages (compat)',
    (await api('GET', '/api/members/packages/mine', null, memberTok)).data.length === actPkgs.length + pastPkgs.length);

  console.log('\n=== 25d. AMMAN AREAS (v0.9 item 1) ===');
  const areas = (await api('GET', '/api/auth/locations', null, null)).data;
  const areaNames = areas.map((l) => l.name_en);
  check('locations are Amman areas (30 active)', areas.length === 30, `n=${areas.length}`);
  check('includes well-known districts', ['Abdoun', 'Sweifieh', 'Khalda', 'Jabal Amman'].every((x) => areaNames.includes(x)));
  check('governorate entries no longer offered', !areaNames.includes('Irbid') && !areaNames.includes('Aqaba'));
  check('areas carry Arabic names', areas.every((l) => (l.name_ar || '').trim().length > 0));

  console.log('\n=== 25e. QUESTIONNAIRE ON THE COACH SIDE (v0.9 item 2) ===');
  const memberId = mReg.data.user.id;
  const mDetail = await api('GET', `/api/coaches/members/${memberId}`, null, coachTok);
  check('coach opens their client detail', mDetail.status === 200 && mDetail.data.profile.first_name === 'Lina', JSON.stringify(mDetail.data).slice(0, 120));
  const answers = mDetail.data.questionnaire.answers;
  check('questionnaire answers returned with question labels',
    answers.length >= 2 && answers.some((a) => a.key === 'goal' && a.answer === 'Lose weight'), JSON.stringify(answers));
  check('coach also sees that member\'s packages with them', (mDetail.data.packages || []).length >= 1);
  // Privacy gate: coach B has no relationship with member2 (that package was moved away).
  const m3Reg = await api('POST', '/api/auth/register/member', {
    email: `m3${uniq}@x.com`, phone: `0794${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Noor', lastName: 'S', nationality: 'Jordanian', location: 'Abdoun',
  });
  const strangerDetail = await api('GET', `/api/coaches/members/${m3Reg.data.user.id}`, null, coachTok);
  check('coach blocked from a member who is not their client', strangerDetail.status === 403, JSON.stringify(strangerDetail.data));
  check('member cannot call the coach endpoint', (await api('GET', `/api/coaches/members/${memberId}`, null, memberTok)).status === 403);

  console.log('\n=== 25f. ADMIN PACKAGE MANAGEMENT (v0.9 items 3-5) ===');
  // -- master list with full detail + filters
  const all = await api('GET', '/api/admin/member-packages', null, adminTok);
  check('master package list returns rows with member AND coach', all.status === 200 && all.data.length >= 3
    && all.data.every((p) => p.member_first && (p.coach_first || p.coach_id === null)), `n=${all.data.length}`);
  const masterRow = all.data.find((p) => p.id === memberPkgId);
  check('master row carries classes, price and payment detail',
    masterRow && Number(masterRow.classes_total) === 6 && Number(masterRow.price) === 90 && masterRow.has_proof === true,
    JSON.stringify(masterRow || {}).slice(0, 140));
  check('master list filters by status', (await api('GET', '/api/admin/member-packages?status=active', null, adminTok)).data.every((p) => p.status === 'active'));
  check('master list filters by coach', (await api('GET', `/api/admin/member-packages?coachId=${coachId}`, null, adminTok)).data.every((p) => p.coach_id === coachId));
  check('master list searches by member name', (await api('GET', '/api/admin/member-packages?q=Lina', null, adminTok)).data.length >= 1);

  // -- coach's members (item 4)
  const coachMembers = await api('GET', `/api/admin/coaches/${coachId}/members`, null, adminTok);
  const lina = (coachMembers.data || []).find((m) => m.member_id === memberId);
  check('admin sees the coach\'s members with totals', coachMembers.status === 200 && lina && lina.packages >= 1 && Number(lina.revenue) > 0,
    JSON.stringify(lina || {}));

  // -- add / deduct classes (item 3)
  const before = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  const addNoReason = await api('POST', `/api/admin/member-packages/${memberPkgId}/adjust-classes`, { delta: 2 }, adminTok);
  check('adjust without reason rejected', addNoReason.status === 400);
  const add2 = await api('POST', `/api/admin/member-packages/${memberPkgId}/adjust-classes`,
    { delta: 2, reason: 'Goodwill for a rescheduled session' }, adminTok);
  check('admin adds 2 classes', add2.status === 200 && add2.data.classes_total === Number(before.classes_total) + 2, JSON.stringify(add2.data));
  const ded1 = await api('POST', `/api/admin/member-packages/${memberPkgId}/adjust-classes`,
    { delta: -1, reason: 'Correcting a data entry mistake' }, adminTok);
  check('admin deducts 1 class', ded1.status === 200 && ded1.data.classes_total === Number(before.classes_total) + 1);
  const tooFar = await api('POST', `/api/admin/member-packages/${memberPkgId}/adjust-classes`,
    { delta: -99, reason: 'should fail' }, adminTok);
  check('cannot deduct below used + held classes', tooFar.status === 409 && /already used/i.test(tooFar.data.error || ''), JSON.stringify(tooFar.data));
  const memberSees = (await api('GET', '/api/members/packages/mine', null, memberTok)).data.find((p) => p.id === memberPkgId);
  check('member sees the adjusted total immediately', Number(memberSees.classes_total) === Number(before.classes_total) + 1);

  // -- cancel is blocked while upcoming bookings exist, allowed after (option (a))
  const cancelBlocked = await api('POST', `/api/admin/member-packages/${memberPkgId}/cancel`, { reason: 'Member asked to stop' }, adminTok);
  check('cancel blocked while upcoming bookings exist', cancelBlocked.status === 409 && cancelBlocked.data.upcomingBookings >= 1, JSON.stringify(cancelBlocked.data));
  // clear the upcoming bookings, then cancel
  // (v0.10) The member's 3-cancellations-per-package cap may already be spent,
  // so clear any remaining upcoming bookings through the coach.
  const upcomingNow = (await api('GET', '/api/members/bookings?scope=upcoming', null, memberTok)).data;
  for (const b of upcomingNow) {
    const own = await api('POST', `/api/bookings/${b.id}/cancel`, {}, memberTok);
    if (own.status !== 200) {
      await api('POST', `/api/bookings/${b.id}/coach-cancel`, { reason: 'Clearing package for cancellation' }, coachTok);
    }
  }
  const cancelOk = await api('POST', `/api/admin/member-packages/${memberPkgId}/cancel`, { reason: 'Member asked to stop' }, adminTok);
  check('cancel succeeds once no upcoming bookings remain', cancelOk.status === 200 && cancelOk.data.status === 'cancelled', JSON.stringify(cancelOk.data));

  // -- audit trail
  const auditLog = await api('GET', `/api/admin/member-packages/${memberPkgId}/history`, null, adminTok);
  check('adjustment history records every action with reason + admin',
    auditLog.status === 200 && auditLog.data.length >= 3
    && auditLog.data.some((h) => h.action === 'add_classes' && /Goodwill/.test(h.reason))
    && auditLog.data.some((h) => h.action === 'cancel')
    && auditLog.data.every((h) => h.admin_email === 'admin@fitness.local'), JSON.stringify(auditLog.data).slice(0, 160));

  // -- move to another coach releases upcoming bookings with the old coach
  // Use the fresh member (Noor) — member2 already holds a package with coach B,
  // which the one-usable-package-per-coach rule would (correctly) block.
  const m3Login = await api('POST', '/api/auth/login', { email: `m3${uniq}@x.com`, password: 'secret12' });
  const member3Tok = m3Login.data.token;
  await completeMemberProfile(member3Tok, 'Khalda');
  const movePkgReq = await api('POST', '/api/members/packages/request',
    { packageDefId: pkg6.id, coachId, proof }, member3Tok);
  check('member3 buys a package with coach A (for the move test)', movePkgReq.status === 201, JSON.stringify(movePkgReq.data));
  const movePkgId = movePkgReq.data.package.id;
  await api('POST', `/api/admin/packages/${movePkgId}/activate`, {}, adminTok);
  const openA = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data.filter((x) => x.delivery === 'online');
  const mvBooking = await api('POST', '/api/bookings', { sessionId: openA[0].id }, member3Tok);
  check('member3 books a session with coach A', mvBooking.status === 201, JSON.stringify(mvBooking.data));
  const moved = await api('POST', `/api/admin/member-packages/${movePkgId}/reassign`,
    { coachId: coach2Id, reason: 'Coach A is leaving the platform' }, adminTok);
  check('admin moves the package to coach B', moved.status === 200 && moved.data.coach_id === coach2Id, JSON.stringify(moved.data));
  check('upcoming booking with the old coach was released', moved.data.releasedBookings === 1, JSON.stringify(moved.data));
  const afterMove = (await api('GET', '/api/members/bookings?scope=history', null, member3Tok)).data.find((b) => b.id === mvBooking.data.id);
  check('released booking shows as cancelled to the member', afterMove && afterMove.status === 'cancelled');
  const movedPkg = (await api('GET', '/api/members/packages/mine', null, member3Tok)).data.find((p) => p.id === movePkgId);
  check('no class was deducted by the move', Number(movedPkg.remaining) === Number(movedPkg.classes_total) && Number(movedPkg.pending) === 0,
    JSON.stringify(movedPkg));

  console.log('\n=== 25g. HOME PAGE CONTENT (v0.10 items 1-3) ===');
  const memberContent = await api('GET', '/api/auth/content?audience=member', null, null);
  check('brand name is CoachlyJo everywhere in content',
    JSON.stringify(memberContent.data).includes('CoachlyJo')
    && !/CoachlyJoJo/.test(JSON.stringify(memberContent.data))
    && !/كوتشلي جو جو/.test(JSON.stringify(memberContent.data)),
    JSON.stringify(memberContent.data.intro).slice(0, 120));
  check('member content: intro, steps and rules', memberContent.status === 200
    && memberContent.data.intro.length >= 1
    && memberContent.data.steps.length === 3
    && memberContent.data.rules.length === 2, JSON.stringify(Object.keys(memberContent.data)));
  check('content carries English AND Arabic', memberContent.data.rules.every((r) => r.title_ar && r.body_ar));
  check('client cancellation rule text is published',
    /24 hours/.test(memberContent.data.rules.map((r) => r.body_en).join(' '))
    && /3 sessions per package/.test(memberContent.data.rules.map((r) => r.body_en).join(' ')));
  const coachContent = await api('GET', '/api/auth/content?audience=coach', null, null);
  check('coach content has its own steps and 3 rules',
    coachContent.data.steps.length === 3 && coachContent.data.rules.length === 3);
  check('coach rules mention the rejection limit',
    /3 times per package/.test(coachContent.data.rules.map((r) => r.body_en).join(' ')));
  await api('PUT', '/api/admin/content-video', { videoUrl: '' }, adminTok); // reset for a repeatable run
  check('video slot is empty until admin sets it',
    (await api('GET', '/api/auth/content?audience=member', null, null)).data.videoUrl === '');

  // admin edits content + video
  const adminContent = await api('GET', '/api/admin/content', null, adminTok);
  check('admin lists all content blocks', adminContent.status === 200 && adminContent.data.blocks.length >= 12);
  const introBlock = adminContent.data.blocks.find((b) => b.key === 'intro_main');
  const editedIntro = await api('PUT', `/api/admin/content/${introBlock.id}`,
    { bodyEn: 'CoachlyJo connects you with verified coaches across Amman.' }, adminTok);
  check('admin edits a content block', editedIntro.status === 200 && /across Amman/.test(editedIntro.data.body_en));
  check('edit is visible to members immediately',
    /across Amman/.test((await api('GET', '/api/auth/content?audience=member', null, null)).data.intro[0].body_en));
  const vid = await api('PUT', '/api/admin/content-video', { videoUrl: 'https://example.com/intro.mp4' }, adminTok);
  check('admin sets the intro video URL', vid.status === 200);
  check('video URL now served to the home page',
    (await api('GET', '/api/auth/content?audience=member', null, null)).data.videoUrl === 'https://example.com/intro.mp4');
  const newRule = await api('POST', '/api/admin/content',
    { key: `rule_test_${uniq}`, audience: 'member', kind: 'rule', titleEn: 'Test rule', bodyEn: 'Body', sortOrder: 9 }, adminTok);
  check('admin adds a new rule block', newRule.status === 201);
  check('duplicate key rejected', (await api('POST', '/api/admin/content',
    { key: `rule_test_${uniq}`, audience: 'member', kind: 'rule' }, adminTok)).status === 409);
  check('admin deletes a content block', (await api('DELETE', `/api/admin/content/${newRule.data.id}`, null, adminTok)).status === 200);

  console.log('\n=== 25h. CANCELLATION POLICY (v0.10 item 2) ===');
  // Fresh member + package so the cancellation counters start clean.
  const m4 = await api('POST', '/api/auth/register/member', {
    email: `m4${uniq}@x.com`, phone: `0795${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Dana', lastName: 'K', nationality: 'Jordanian', location: 'Sweifieh',
  });
  const m4Tok = (await api('POST', '/api/auth/login', { email: `m4${uniq}@x.com`, password: 'secret12' })).data.token;
  await completeMemberProfile(m4Tok, 'Sweifieh');
  const m4Pkg = await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId, proof }, m4Tok);
  await api('POST', `/api/admin/packages/${m4Pkg.data.package.id}/activate`, {}, adminTok);
  const m4PkgId = m4Pkg.data.package.id;

  // Sessions more than 24h away vs inside the window.
  const openNow = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online')
    .sort((a, b) => new Date(a.start_at) - new Date(b.start_at));
  const farSessions = openNow.filter((x) => (new Date(x.start_at) - new Date()) / 3600000 > 26);
  check('open sessions exist beyond the 24h window', farSessions.length >= 4, `n=${farSessions.length}`);

  // (a) early cancel — more than 24h ahead: no deduction
  const e1 = await api('POST', '/api/bookings', { sessionId: farSessions[0].id }, m4Tok);
  const c1res = await api('POST', `/api/bookings/${e1.data.id}/cancel`, {}, m4Tok);
  check('cancel >24h ahead succeeds', c1res.status === 200 && c1res.data.cancel_kind === 'early', JSON.stringify(c1res.data));
  let m4State = (await api('GET', '/api/members/packages/mine', null, m4Tok)).data.find((p) => p.id === m4PkgId);
  check('no class deducted for an early cancel', Number(m4State.remaining) === 6 && Number(m4State.pending) === 0);

  // (b) late cancel — session pulled inside the 24h window: deducts
  const lateBooking = await api('POST', '/api/bookings', { sessionId: farSessions[1].id }, m4Tok);
  await pool.query(
    `UPDATE coach_sessions SET start_at = now() + interval '5 hours',
                               end_at   = now() + interval '5 hours' + interval '50 minutes'
      WHERE id = $1`, [farSessions[1].id]);
  const lateRes = await api('POST', `/api/bookings/${lateBooking.data.id}/cancel`, {}, m4Tok);
  check('cancel inside 24h succeeds and is flagged late', lateRes.status === 200 && lateRes.data.cancel_kind === 'same_day', JSON.stringify(lateRes.data));
  m4State = (await api('GET', '/api/members/packages/mine', null, m4Tok)).data.find((p) => p.id === m4PkgId);
  check('class IS deducted for a cancel inside 24h', Number(m4State.remaining) === 5, JSON.stringify(m4State));

  // (c) third cancellation allowed, fourth blocked
  const e3 = await api('POST', '/api/bookings', { sessionId: farSessions[2].id }, m4Tok);
  check('3rd cancellation still allowed', (await api('POST', `/api/bookings/${e3.data.id}/cancel`, {}, m4Tok)).status === 200);
  const e4 = await api('POST', '/api/bookings', { sessionId: farSessions[3].id }, m4Tok);
  const blocked = await api('POST', `/api/bookings/${e4.data.id}/cancel`, {}, m4Tok);
  check('4th cancellation blocked by the 3-per-package limit',
    blocked.status === 409 && /already cancelled 3/i.test(blocked.data.error || ''), JSON.stringify(blocked.data));
  check('the booking survives the refused cancellation',
    (await api('GET', '/api/members/bookings?scope=upcoming', null, m4Tok)).data.some((b) => b.id === e4.data.id));
  const m4Bookings = (await api('GET', '/api/members/bookings?scope=upcoming', null, m4Tok)).data;
  check('member bookings expose the cancellations used counter',
    m4Bookings.every((b) => typeof b.pkg_cancels_used === 'number'), JSON.stringify(m4Bookings[0] || {}).slice(0, 120));

  console.log('\n=== 25i. COACH CANCELLATION + PENALTY (v0.10 item 2) ===');
  // Coach cancels the booking the member could not: member keeps the class.
  await api('POST', `/api/bookings/${e4.data.id}/decision`, { accept: true }, coachTok);
  const noReasonCancel = await api('POST', `/api/bookings/${e4.data.id}/coach-cancel`, {}, coachTok);
  check('coach cancel without a reason rejected', noReasonCancel.status === 400);
  const beforeCoachCancel = (await api('GET', '/api/members/packages/mine', null, m4Tok)).data.find((p) => p.id === m4PkgId);
  const coachCancelled = await api('POST', `/api/bookings/${e4.data.id}/coach-cancel`,
    { reason: 'I am travelling that week' }, coachTok);
  check('coach cancels an accepted session', coachCancelled.status === 200 && coachCancelled.data.cancel_kind === 'coach', JSON.stringify(coachCancelled.data));
  check('early coach cancel creates NO penalty', coachCancelled.data.penalty === false);
  const afterCoachCancel = (await api('GET', '/api/members/packages/mine', null, m4Tok)).data.find((p) => p.id === m4PkgId);
  check('member is not charged for a coach cancellation',
    Number(afterCoachCancel.remaining) === Number(beforeCoachCancel.remaining) && Number(afterCoachCancel.pending) === 0,
    `before=${beforeCoachCancel.remaining} after=${afterCoachCancel.remaining}`);
  check('coach cancellation does not consume the member\'s 3 allowance',
    (await api('POST', '/api/bookings', { sessionId: farSessions[4] ? farSessions[4].id : openNow[0].id }, m4Tok)).status === 201);

  // Same-day coach cancellation -> penalty recorded
  // Re-read open slots: earlier steps in this section consumed several.
  const freshOpen = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online');
  const sdSession = freshOpen[freshOpen.length - 1];
  const sdBooking = await api('POST', '/api/bookings', { sessionId: sdSession.id }, m4Tok);
  if (sdBooking.status === 201) {
    await api('POST', `/api/bookings/${sdBooking.data.id}/decision`, { accept: true }, coachTok);
    await pool.query(
      `UPDATE coach_sessions SET start_at = now() + interval '3 hours',
                                 end_at   = now() + interval '3 hours' + interval '50 minutes'
        WHERE id = $1`, [sdSession.id]);
    const sdCancel = await api('POST', `/api/bookings/${sdBooking.data.id}/coach-cancel`,
      { reason: 'Emergency' }, coachTok);
    check('same-day coach cancel records a penalty', sdCancel.status === 200 && sdCancel.data.penalty === true, JSON.stringify(sdCancel.data));
    const penalties = await api('GET', '/api/admin/penalties', null, adminTok);
    check('admin sees the unsettled penalty with coach and member',
      penalties.status === 200 && penalties.data.some((p) => p.coach_first === 'Omar' && p.sessions === 1), JSON.stringify(penalties.data).slice(0, 140));
    const dash = await api('GET', '/api/coaches/dashboard?days=30', null, coachTok);
    check('coach dashboard shows sessions owed', dash.data.penaltySessions >= 1, `n=${dash.data.penaltySessions}`);
    const settle = await api('POST', `/api/admin/penalties/${penalties.data[0].id}/settle`, {}, adminTok);
    check('admin settles a penalty', settle.status === 200 && !!settle.data.settled_at);
    check('settled penalty leaves the open list',
      !(await api('GET', '/api/admin/penalties', null, adminTok)).data.some((p) => p.id === penalties.data[0].id));
  } else {
    check('same-day coach cancel scenario set up', false, JSON.stringify(sdBooking.data));
  }

  console.log('\n=== 25j. COACH REJECTION LIMIT (v0.10 item 2) ===');
  const rejSessions = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online').slice(0, 5);
  let rejected = 0;
  for (const sess of rejSessions) {
    const bk = await api('POST', '/api/bookings', { sessionId: sess.id }, m4Tok);
    if (bk.status !== 201) continue;
    const dec = await api('POST', `/api/bookings/${bk.data.id}/decision`,
      { accept: false, rejectionReason: 'Not available' }, coachTok);
    if (dec.status === 200) { rejected++; continue; }
    check('4th rejection on the same package is blocked',
      dec.status === 409 && /already rejected 3/i.test(dec.data.error || ''), JSON.stringify(dec.data));
    check('exactly 3 rejections were allowed', rejected === 3, `allowed=${rejected}`);
    // and the request is still pending, so the coach must accept or cancel it
    check('the request stays pending after a refused rejection',
      (await api('GET', '/api/coaches/bookings', null, coachTok)).data.some((b) => b.id === bk.data.id && b.status === 'pending'));
    break;
  }
  check('rejection reason is still mandatory',
    (await api('POST', `/api/bookings/${e1.data.id}/decision`, { accept: false }, coachTok)).status !== 200);
  const coachBk = (await api('GET', '/api/coaches/bookings', null, coachTok)).data;
  check('coach bookings expose the rejections used counter',
    coachBk.every((b) => typeof b.pkg_rejects_used === 'number' || b.member_package_id === null));

  console.log('\n=== 25k. PACKAGE DELETE / ARCHIVE (v0.11 item 1) ===');
  const defs = await api('GET', '/api/admin/packages', null, adminTok);
  check('admin package list exposes purchase counts', defs.status === 200 && defs.data.every((d) => typeof d.purchases === 'number'));
  const usedDef = defs.data.find((d) => d.purchases > 0);
  check('a purchased definition exists for the test', !!usedDef);
  const refused = await api('DELETE', `/api/admin/packages/${usedDef.id}`, null, adminTok);
  check('deleting a purchased package is refused with a hint',
    refused.status === 409 && refused.data.canArchive === true && refused.data.purchases > 0, JSON.stringify(refused.data));
  const archived = await api('DELETE', `/api/admin/packages/${usedDef.id}?force=archive`, null, adminTok);
  check('archiving a purchased package works', archived.status === 200 && archived.data.archived === true);
  check('archived package disappears from the member catalogue',
    !(await api('GET', '/api/members/packages/catalogue', null, memberTok)).data.some((p) => p.id === usedDef.id));
  const stillOwned = (await api('GET', '/api/members/packages/mine', null, memberTok)).data;
  check('existing purchases of an archived package still work', stillOwned.length > 0);
  const restored = await api('POST', `/api/admin/packages/${usedDef.id}/restore`, {}, adminTok);
  check('archived package can be restored', restored.status === 200 && restored.data.is_archived === false);
  check('restored package returns to the catalogue',
    (await api('GET', '/api/members/packages/catalogue', null, memberTok)).data.some((p) => p.id === usedDef.id));

  // a brand-new, never-purchased definition really is deleted
  const fresh = await api('POST', '/api/admin/packages',
    { nameEn: `Temp ${uniq}`, nameAr: 'مؤقت', classCount: 4, mode: 'online', price: 55, validityWeeks: 4 }, adminTok);
  check('admin creates a package definition', fresh.status === 201, JSON.stringify(fresh.data));
  const hardDel = await api('DELETE', `/api/admin/packages/${fresh.data.id}`, null, adminTok);
  check('never-purchased package is deleted outright', hardDel.status === 200 && hardDel.data.purchases === 0, JSON.stringify(hardDel.data));
  check('deleted package is gone from the admin list',
    !(await api('GET', '/api/admin/packages', null, adminTok)).data.some((d) => d.id === fresh.data.id));
  check('deleting a non-existent package 404s',
    (await api('DELETE', `/api/admin/packages/${fresh.data.id}`, null, adminTok)).status === 404);
  // (v0.11 fix) creating/updating a definition with an explicit mode used to
  // fail on the package_mode enum cast — guard both paths.
  const inPerson = await api('POST', '/api/admin/packages',
    { nameEn: `Temp IP ${uniq}`, nameAr: 'مؤقت حضوري', classCount: 5, mode: 'in_person', price: 70, validityWeeks: 6 }, adminTok);
  check('package definition can be created with mode=in_person', inPerson.status === 201 && inPerson.data.mode === 'in_person', JSON.stringify(inPerson.data));
  const switched = await api('PUT', `/api/admin/packages/${inPerson.data.id}`, { mode: 'online' }, adminTok);
  check('package definition mode can be updated', switched.status === 200 && switched.data.mode === 'online', JSON.stringify(switched.data));
  await api('DELETE', `/api/admin/packages/${inPerson.data.id}`, null, adminTok);

  console.log('\n=== 25l. NOTIFICATION CENTRE (v0.11 item 2) ===');
  // The suite has already approved a coach, activated packages, accepted and
  // rejected bookings, cancelled sessions and recorded a penalty — so real
  // notifications should exist for each role.
  const coachNotifs = await api('GET', '/api/notifications', null, coachTok);
  check('coach notification list responds with unread count',
    coachNotifs.status === 200 && typeof coachNotifs.data.unread === 'number' && Array.isArray(coachNotifs.data.items),
    JSON.stringify(coachNotifs.data).slice(0, 90));
  const cTypes = coachNotifs.data.items.map((n) => n.type);
  check('coach was notified of approval', cTypes.includes('coach_approved'));
  check('coach was notified of booking requests', cTypes.includes('booking_requested'));
  check('coach was notified of a new client', cTypes.includes('new_client'));
  check('coach was notified of the same-day penalty', cTypes.includes('penalty_recorded'));
  check('notifications carry English AND Arabic text',
    coachNotifs.data.items.every((n) => n.title_en && n.title_ar));

  const memberNotifs = await api('GET', '/api/notifications', null, memberTok);
  const mTypes = memberNotifs.data.items.map((n) => n.type);
  check('member was notified their package went active', mTypes.includes('package_activated'));
  check('member was notified of booking decisions',
    mTypes.includes('booking_accepted') && mTypes.includes('booking_rejected'));
  check('member was notified of admin package changes',
    mTypes.includes('package_adjusted') || mTypes.includes('package_cancelled') || mTypes.includes('package_moved'),
    JSON.stringify(mTypes));

  const adminNotifs = await api('GET', '/api/notifications', null, adminTok);
  const aTypes = adminNotifs.data.items.map((n) => n.type);
  check('admin was notified of new coach applications', aTypes.includes('admin_new_coach'));
  check('admin was notified of package payment requests', aTypes.includes('admin_new_package_request'));
  check('admin was notified of the same-day coach cancellation', aTypes.includes('admin_coach_same_day_cancel'));

  // read / unread mechanics
  const beforeRead = (await api('GET', '/api/notifications/unread-count', null, memberTok)).data.unread;
  check('unread count is positive to start', beforeRead > 0, `n=${beforeRead}`);
  const firstUnread = memberNotifs.data.items.find((n) => n.read_at === null);
  const readOne = await api('POST', `/api/notifications/${firstUnread.id}/read`, {}, memberTok);
  check('marking one as read works', readOne.status === 200);
  check('unread count drops by one',
    (await api('GET', '/api/notifications/unread-count', null, memberTok)).data.unread === beforeRead - 1);
  check('re-reading the same notification 404s',
    (await api('POST', `/api/notifications/${firstUnread.id}/read`, {}, memberTok)).status === 404);
  check('unread filter returns only unread',
    (await api('GET', '/api/notifications?unread=true', null, memberTok)).data.items.every((n) => n.read_at === null));
  const readAll = await api('POST', '/api/notifications/read-all', {}, memberTok);
  check('read-all clears the badge', readAll.status === 200
    && (await api('GET', '/api/notifications/unread-count', null, memberTok)).data.unread === 0);

  // privacy: a user can only touch their own notifications
  const otherId = coachNotifs.data.items[0].id;
  check('cannot read someone else\'s notification',
    (await api('POST', `/api/notifications/${otherId}/read`, {}, memberTok)).status === 404);
  check('cannot delete someone else\'s notification',
    (await api('DELETE', `/api/notifications/${otherId}`, null, memberTok)).status === 404);
  check('own notification can be deleted',
    (await api('DELETE', `/api/notifications/${firstUnread.id}`, null, memberTok)).status === 200);

  console.log('\n=== 25m. SCHEDULED REMINDERS (v0.11 item 2) ===');
  const { sendDueReminders, sendPackageNotices } = require('../src/services/notification.service_v0_13');
  // Put an accepted session exactly inside the 1-hour reminder window.
  const remOpen = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online');
  const remBooking = await api('POST', '/api/bookings', { sessionId: remOpen[0].id }, m4Tok);
  check('booked a session for the reminder test', remBooking.status === 201, JSON.stringify(remBooking.data));
  await api('POST', `/api/bookings/${remBooking.data.id}/decision`, { accept: true }, coachTok);
  await pool.query(
    `UPDATE coach_sessions SET start_at = now() + interval '55 minutes',
                               end_at   = now() + interval '105 minutes'
      WHERE id = $1`, [remOpen[0].id]);
  const sent = await sendDueReminders();
  check('reminders sent to both member and coach', sent >= 2, `n=${sent}`);
  const m4Notifs = (await api('GET', '/api/notifications', null, m4Tok)).data.items;
  check('member has a session reminder', m4Notifs.some((n) => n.type === 'session_reminder'));
  check('reminder links to the booking',
    m4Notifs.some((n) => n.type === 'session_reminder' && n.related_id === remBooking.data.id));
  const again = await sendDueReminders();
  check('re-running the job does NOT duplicate reminders', again === 0, `n=${again}`);

  // package expiry notice, also de-duplicated
  const expPkg = (await api('GET', '/api/members/packages/mine', null, m4Tok)).data.find((p) => p.status === 'active');
  if (expPkg) {
    await pool.query(`UPDATE member_packages SET expires_at = now() + interval '2 days' WHERE id=$1`, [expPkg.id]);
    const notices = await sendPackageNotices();
    check('package-expiring notice created', notices >= 1, `n=${notices}`);
    check('expiry notice does not repeat', (await sendPackageNotices()) === 0);
    check('member sees the expiring notice',
      (await api('GET', '/api/notifications', null, m4Tok)).data.items.some((n) => n.type === 'package_expiring'));
  }

  console.log('\n=== 25n. LEGAL DOCUMENTS + PUBLIC PAGES (v0.13 store compliance) ===');
  const legal = await api('GET', '/api/account/legal', null, null);
  check('privacy policy and terms are public (no login needed)',
    legal.status === 200 && legal.data.length >= 2, JSON.stringify(legal.data.map((l) => l.key)));
  const privacy = legal.data.find((l) => l.key === 'legal_privacy');
  const terms = legal.data.find((l) => l.key === 'legal_terms');
  check('both documents exist in English AND Arabic',
    !!privacy && !!terms && privacy.body_ar.length > 200 && terms.body_ar.length > 200);
  check('privacy policy covers the data we actually collect',
    /questionnaire/i.test(privacy.body_en) && /payment proof/i.test(privacy.body_en));
  check('privacy policy explains account deletion and retention',
    /delete your account/i.test(privacy.body_en) && /anonymised/i.test(privacy.body_en));
  check('terms state the cancellation rules the app enforces',
    /24 hours/.test(terms.body_en) && /3 sessions per package/.test(terms.body_en));

  // Public HTML pages (Apple listing URL + Google's web deletion route).
  const privacyPage = await fetch(`${BASE}/privacy`);
  const privacyHtml = await privacyPage.text();
  check('/privacy renders a public HTML page', privacyPage.status === 200 && /Privacy Policy/.test(privacyHtml));
  check('/privacy has an Arabic version', /سياسة الخصوصية/.test(await (await fetch(`${BASE}/privacy?lang=ar`)).text()));
  const termsPage = await fetch(`${BASE}/terms`);
  check('/terms renders publicly', termsPage.status === 200);
  const delPage = await fetch(`${BASE}/delete-account`);
  const delHtml = await delPage.text();
  check('/delete-account renders the public web form',
    delPage.status === 200 && /<form/.test(delHtml) && /Delete my account/.test(delHtml));
  check('/delete-account has an Arabic version',
    /حذف حسابي/.test(await (await fetch(`${BASE}/delete-account?lang=ar`)).text()));

  console.log('\n=== 25o. WEB DELETION REQUESTS (Google Play requirement) ===');
  const webReq = await fetch(`${BASE}/delete-account`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `email=${encodeURIComponent(`m4${uniq}@x.com`)}&note=No+longer+training`,
  });
  check('web form accepts a deletion request', webReq.status === 200);
  const badReq = await fetch(`${BASE}/delete-account`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'email=not-an-email',
  });
  check('web form rejects an invalid email', badReq.status === 400);
  const apiReq = await api('POST', '/api/account/request-deletion', { email: `nobody${uniq}@x.com` }, null);
  check('JSON deletion-request endpoint works without a session', apiReq.status === 200);
  const queue = await api('GET', '/api/admin/deletion-requests?status=open', null, adminTok);
  check('admin sees both requests in the queue', queue.status === 200 && queue.data.length >= 2, `n=${queue.data.length}`);
  const matched = queue.data.find((q) => q.email === `m4${uniq}@x.com`);
  check('queue shows which request matches a real account', !!matched && matched.matched_user_id !== null);
  const unmatched = queue.data.find((q) => q.email === `nobody${uniq}@x.com`);
  check('queue shows unmatched requests too', !!unmatched && unmatched.matched_user_id === null);
  const reqRejected = await api('POST', `/api/admin/deletion-requests/${unmatched.id}/reject`, {}, adminTok);
  check('admin can reject a request', reqRejected.status === 200 && reqRejected.data.status === 'rejected');
  check('rejected request leaves the open queue',
    !(await api('GET', '/api/admin/deletion-requests?status=open', null, adminTok)).data.some((q) => q.id === unmatched.id));

  console.log('\n=== 25p. IN-APP ACCOUNT DELETION (Apple + Google requirement) ===');
  // A fresh member with a package and an upcoming booking — the realistic case.
  const delEmail = `del${uniq}@x.com`;
  const delReg = await api('POST', '/api/auth/register/member', {
    email: delEmail, phone: `0796${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Tariq', lastName: 'Z', nationality: 'Jordanian', location: 'Khalda',
    assessment: { goal: 'Build muscle', level: 'intermediate' },
  });
  check('registered a member for the deletion test', delReg.status === 201);
  const delId = delReg.data.user.id;
  const delTok = (await api('POST', '/api/auth/login', { email: delEmail, password: 'secret12' })).data.token;
  await completeMemberProfile(delTok, 'Khalda');
  const delPkg = await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId, proof }, delTok);
  await api('POST', `/api/admin/packages/${delPkg.data.package.id}/activate`, {}, adminTok);
  const delOpen = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online');
  const delBooking = await api('POST', '/api/bookings', { sessionId: delOpen[0].id }, delTok);
  check('member has an upcoming booking before deleting', delBooking.status === 201, JSON.stringify(delBooking.data));
  await api('POST', `/api/bookings/${delBooking.data.id}/decision`, { accept: true }, coachTok);

  const preview = await api('GET', '/api/account/deletion-preview', null, delTok);
  check('deletion preview tells the member what they lose',
    preview.status === 200 && preview.data.upcomingSessions >= 1 && preview.data.unusedClasses >= 1,
    JSON.stringify(preview.data));

  check('deletion requires a password', (await api('DELETE', '/api/account', {}, delTok)).status === 400);
  check('deletion rejects the wrong password',
    (await api('DELETE', '/api/account', { password: 'wrongpass' }, delTok)).status === 401);

  const del = await api('DELETE', '/api/account', { password: 'secret12', reason: 'Testing' }, delTok);
  check('member deletes their own account',
    del.status === 200 && del.data.deleted === true && del.data.cancelledBookings >= 1, JSON.stringify(del.data));

  // Data really is gone
  const gone = await pool.query(
    `SELECT u.email, u.phone, u.deleted_at, mp.first_name, mp.last_name, mp.location
       FROM users u JOIN member_profiles mp ON mp.user_id = u.id WHERE u.id = $1`, [delId]);
  const g = gone.rows[0];
  check('email is anonymised', /deleted\+/.test(g.email) && !g.email.includes(delEmail));
  check('phone is erased', g.phone === null);
  check('name is erased', g.first_name === 'Deleted' && g.last_name === 'user');
  check('location is erased', g.location === null);
  check('account is flagged deleted', g.deleted_at !== null);
  const assess = await pool.query(`SELECT COUNT(*)::int n FROM fitness_assessments WHERE member_id=$1`, [delId]);
  check('questionnaire answers are deleted', assess.rows[0].n === 0);
  const notifs = await pool.query(`SELECT COUNT(*)::int n FROM notifications WHERE user_id=$1`, [delId]);
  check('notifications are deleted', notifs.rows[0].n === 0);
  const proofGone = await pool.query(
    `SELECT COUNT(*)::int n FROM member_packages WHERE member_id=$1 AND proof_content IS NOT NULL`, [delId]);
  check('payment-proof images are deleted', proofGone.rows[0].n === 0);
  const bookingGone = await pool.query(
    `SELECT status FROM bookings WHERE id=$1`, [delBooking.data.id]);
  check('upcoming booking was cancelled', bookingGone.rows[0].status === 'cancelled');
  const financial = await pool.query(
    `SELECT COUNT(*)::int n FROM member_packages WHERE member_id=$1`, [delId]);
  check('anonymised financial record is retained (disclosed in the policy)', financial.rows[0].n >= 1);
  const coachNotified = await api('GET', '/api/notifications', null, coachTok);
  check('the coach was told their session was cancelled',
    coachNotified.data.items.some((n) => /closed their/i.test(n.body_en || '')));

  check('the deleted account can no longer log in',
    (await api('POST', '/api/auth/login', { email: delEmail, password: 'secret12' })).status !== 200);
  check('the old token no longer works',
    (await api('GET', '/api/members/packages/mine', null, delTok)).status === 401);
  check('admin accounts cannot be deleted from the app',
    (await api('DELETE', '/api/account', { password: 'admin1234' }, adminTok)).status === 409);

  console.log('\n=== 25q. ADMIN-INITIATED DELETION ===');
  const sup = `sup${uniq}@x.com`;
  const supReg = await api('POST', '/api/auth/register/member', {
    email: sup, phone: `0797${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Huda', lastName: 'M', nationality: 'Jordanian', location: 'Abdoun',
  });
  const adminDel = await api('DELETE', `/api/admin/users/${supReg.data.user.id}`, { reason: 'Support request' }, adminTok);
  check('admin can delete a user on request', adminDel.status === 200 && adminDel.data.deleted === true);
  check('deleting twice is refused',
    (await api('DELETE', `/api/admin/users/${supReg.data.user.id}`, {}, adminTok)).status === 409);
  const audit = await pool.query(`SELECT requested_by FROM account_deletions WHERE user_id=$1`, [supReg.data.user.id]);
  check('deletion is written to the audit trail', audit.rows[0]?.requested_by === 'admin');

  console.log('\n=== 25r. SHORT REGISTRATION + COMPLETE PROFILE (v0.14 items 1, 2, 4, 11) ===');
  const shortEmail = `short${uniq}@x.com`;
  const noNat = await api('POST', '/api/auth/register/member', {
    email: shortEmail, phone: `0798${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Omar', lastName: 'Q',
  });
  check('registration requires nationality', noNat.status === 400, JSON.stringify(noNat.data));
  const shortReg = await api('POST', '/api/auth/register/member', {
    email: shortEmail, phone: `0798${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Omar', lastName: 'Q', nationality: 'Jordanian',
  });
  check('member registers with only the five short fields', shortReg.status === 201, JSON.stringify(shortReg.data));
  const shortTok = (await api('POST', '/api/auth/login', { email: shortEmail, password: 'secret12' })).data.token;

  const st0 = await api('GET', '/api/profile/status', null, shortTok);
  check('profile status reports exactly what is missing',
    st0.status === 200 && st0.data.complete === false
    && st0.data.missing.includes('dateOfBirth') && st0.data.missing.includes('location')
    && st0.data.missing.includes('questionnaire'), JSON.stringify(st0.data));

  // (item 2) The app blocks these until the profile is done — so does the API.
  const earlyBuy = await api('POST', '/api/members/packages/request',
    { packageDefId: pkg6.id, coachId, proof }, shortTok);
  check('cannot buy a package before completing the profile',
    earlyBuy.status === 403 && earlyBuy.data.profileIncomplete === true, JSON.stringify(earlyBuy.data));
  const openForEarly = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data;
  const earlyBook = await api('POST', '/api/bookings', { sessionId: openForEarly[0].id }, shortTok);
  check('cannot book before completing the profile', earlyBook.status === 403 && earlyBook.data.profileIncomplete === true);

  const halfDone = await api('POST', '/api/profile/member', { dateOfBirth: '1996-02-02' }, shortTok);
  check('profile completion rejects a half-filled form', halfDone.status === 400);
  const done = await api('POST', '/api/profile/member',
    { dateOfBirth: '1996-02-02', location: 'Abdoun', assessment: { goal: 'Build muscle', level: 'beginner' } }, shortTok);
  check('member completes their profile', done.status === 200 && done.data.complete === true, JSON.stringify(done.data));
  check('buying works once the profile is complete',
    (await api('POST', '/api/members/packages/request', { packageDefId: pkg6.id, coachId, proof }, shortTok)).status === 201);
  check('birth place is gone from the API',
    !JSON.stringify(await api('GET', '/api/members/profile', null, shortTok)).includes('birth_place'));

  console.log('\n=== 25s. COACH PROFILE COMPLETION (v0.14 items 4, 11) ===');
  const cEmail = `c3${uniq}@x.com`;
  const cReg3 = await api('POST', '/api/auth/register/coach', {
    email: cEmail, phone: `0799${String(uniq).slice(-6)}`, password: 'secret12',
    firstName: 'Yazan', lastName: 'H', nationality: 'Jordanian',
  });
  check('coach registers without documents', cReg3.status === 201, JSON.stringify(cReg3.data));
  const c3Tok = (await api('POST', '/api/auth/login', { email: cEmail, password: 'secret12' })).data.token;
  const cSt = await api('GET', '/api/profile/status', null, c3Tok);
  check('coach profile status lists documents as missing',
    cSt.data.missing.includes('documents') && cSt.data.missing.includes('yearsExperience')
    && cSt.data.missing.includes('specialties'), JSON.stringify(cSt.data));
  check('coach status reports pending approval', cSt.data.approvalStatus === 'pending');

  const noDocs = await api('POST', '/api/profile/coach',
    { dateOfBirth: '1992-03-03', yearsExperience: 4, specialties: ['Boxing'] }, c3Tok);
  check('coach profile requires documents (item 4)', noDocs.status === 400 && /certificate|experience/i.test(noDocs.data.error || ''),
    JSON.stringify(noDocs.data));
  const cDone = await api('POST', '/api/profile/coach', {
    dateOfBirth: '1992-03-03', yearsExperience: 4, specialties: ['Boxing', 'Conditioning'],
    documents: [{ docType: 'degree_certificate', fileName: 'cert.pdf', mimeType: 'application/pdf', dataBase64: pdfB64 }],
  }, c3Tok);
  check('coach completes their profile', cDone.status === 200 && cDone.data.complete === true, JSON.stringify(cDone.data));

  // (item 11) The bio is composed from experience + specialties.
  const c3Profile = await api('GET', '/api/coaches/profile', null, c3Tok);
  check('bio is generated from experience and specialties',
    /4 years of experience/.test(c3Profile.data.bio_en || '') && /Boxing/.test(c3Profile.data.bio_en || ''),
    JSON.stringify(c3Profile.data.bio_en));
  check('Arabic bio is generated too', /سنوات/.test(c3Profile.data.bio_ar || ''), JSON.stringify(c3Profile.data.bio_ar));

  // (item 11) Optional profile photo.
  const photo = await api('POST', '/api/profile/coach/photo', { mimeType: 'image/png', dataBase64: pngB64 }, c3Tok);
  check('coach uploads a profile photo', photo.status === 200);
  const photoBytes = await apiRaw(`/api/profile/coach/${cReg3.data.user.id}/photo`, memberTok);
  check('members can fetch the coach photo', photoBytes.status === 200 && photoBytes.bytes.length > 0);
  check('coach can remove the photo', (await api('DELETE', '/api/profile/coach/photo', null, c3Tok)).status === 200);
  check('removed photo 404s', (await apiRaw(`/api/profile/coach/${cReg3.data.user.id}/photo`, memberTok)).status === 404);
  check('a bad photo type is rejected',
    (await api('POST', '/api/profile/coach/photo', { mimeType: 'application/pdf', dataBase64: pdfB64 }, c3Tok)).status === 400);

  console.log('\n=== 25t. CONTACT DETAILS + THEME (v0.14 items 6, 12) ===');
  const contact = await api('GET', '/api/auth/contact', null, null);
  check('contact details are public', contact.status === 200 && contact.data.email === 'coachlyapp@hotmail.com', JSON.stringify(contact.data));
  const setContact = await api('PUT', '/api/admin/contact',
    { phone: '+962790000000', instagram: 'coachlyjo' }, adminTok);
  check('admin configures contact details', setContact.status === 200);
  const contact2 = await api('GET', '/api/auth/contact', null, null);
  check('updated details are served to the app',
    contact2.data.phone === '+962790000000' && contact2.data.instagram === 'coachlyjo');
  check('an invalid contact email is rejected',
    (await api('PUT', '/api/admin/contact', { email: 'not-an-email' }, adminTok)).status === 400);

  check('theme preference saves', (await api('PUT', '/api/profile/theme', { theme: 'light' }, memberTok)).status === 200);
  check('an unknown theme is rejected', (await api('PUT', '/api/profile/theme', { theme: 'neon' }, memberTok)).status === 400);

  console.log('\n=== 25u. PUSH TOKENS (v0.14 item 13) ===');
  const devTok = `fcm-test-token-${uniq}-abcdefghijklmnop`;
  check('device registers for push',
    (await api('POST', '/api/push/register', { token: devTok, platform: 'android' }, memberTok)).status === 200);
  check('re-registering the same token is fine',
    (await api('POST', '/api/push/register', { token: devTok, platform: 'android' }, memberTok)).status === 200);
  const tokRow = await pool.query(`SELECT user_id FROM device_tokens WHERE token=$1`, [devTok]);
  check('token is stored once against the member', tokRow.rowCount === 1);
  check('a short token is rejected',
    (await api('POST', '/api/push/register', { token: 'abc', platform: 'android' }, memberTok)).status === 400);
  check('an unknown platform is rejected',
    (await api('POST', '/api/push/register', { token: devTok, platform: 'windows' }, memberTok)).status === 400);
  check('sign-out removes the device token',
    (await api('DELETE', '/api/push/register', { token: devTok }, memberTok)).status === 200);

  console.log('\n=== 25v. ZOOM FAILURE NO LONGER BLOCKS ACCEPTANCE (v0.14) ===');
  // The suite runs with placeholder links enabled; the contract we check here
  // is that the response carries the zoomPending flag the app reads.
  const zOpen = (await api('GET', '/api/coaches/my-sessions?scope=open', null, coachTok)).data
    .filter((x) => x.delivery === 'online');
  // `shortTok` bought a package with coach A a few checks ago and has classes left.
  const zPkg = (await api('GET', '/api/members/packages/mine', null, shortTok)).data
    .find((p) => p.status === 'pending_payment' || p.status === 'active');
  if (zPkg && zPkg.status === 'pending_payment') {
    await api('POST', `/api/admin/packages/${zPkg.id}/activate`, {}, adminTok);
  }
  const zBooking = await api('POST', '/api/bookings', { sessionId: zOpen[0].id }, shortTok);
  if (zBooking.status === 201) {
    const zDecision = await api('POST', `/api/bookings/${zBooking.data.id}/decision`, { accept: true }, coachTok);
    check('acceptance succeeds and reports Zoom state',
      zDecision.status === 200 && zDecision.data.status === 'accepted' && 'zoomPending' in zDecision.data,
      JSON.stringify(zDecision.data).slice(0, 120));
    const manual = await api('PUT', `/api/bookings/${zBooking.data.id}/meeting-link`,
      { joinUrl: 'https://meet.google.com/abc-defg-hij' }, coachTok);
    check('coach can supply their own meeting link', manual.status === 200, JSON.stringify(manual.data));
    const memberSees = (await api('GET', '/api/members/bookings?scope=upcoming', null, shortTok))
      .data.find((b) => b.id === zBooking.data.id);
    check('member sees the coach-supplied link', memberSees && /meet\.google\.com/.test(memberSees.zoom_join_url || ''));
    check('an invalid meeting link is rejected',
      (await api('PUT', `/api/bookings/${zBooking.data.id}/meeting-link`, { joinUrl: 'not a url' }, coachTok)).status === 400);
  } else {
    check('zoom acceptance scenario set up', false, JSON.stringify(zBooking.data));
  }

  console.log('\n=== 26. SCHEMA VERSION HEALTH ===');
  const sv = await api('GET', '/health/schema', null, null);
  check('schema reports up to date (v14)', sv.status === 200 && sv.data.upToDate === true && sv.data.current === 14, JSON.stringify(sv.data));

  console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===`);
  await pool.end().catch(() => {});
  process.exit(fail ? 1 : 0);
})();
