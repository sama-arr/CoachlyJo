// Seeds baseline data: one admin, the 6/9/12 packages, sample slot templates,
// and a payment note. Idempotent-ish: safe to run once on a fresh DB.
// Usage: npm run seed
require('dotenv').config();
const bcrypt = require('bcryptjs');
const { pool, withTransaction } = require('./pool_v0_13');

async function seed() {
  await withTransaction(async (client) => {
    // Ensure singleton config rows exist (schema creates them, but make seed robust
    // so it also works after a TRUNCATE during testing).
    await client.query(`INSERT INTO platform_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING`);
    await client.query(`INSERT INTO payment_notes (id) VALUES (1) ON CONFLICT (id) DO NOTHING`);

    // Admin
    const adminPw = await bcrypt.hash('admin1234', 10);
    const admin = await client.query(
      `INSERT INTO users (role,email,phone,password_hash,email_verified,phone_verified)
       VALUES ('admin','admin@fitness.local','+962700000000',$1,TRUE,TRUE)
       ON CONFLICT (email) DO NOTHING RETURNING id`,
      [adminPw]
    );
    console.log('Admin: admin@fitness.local / admin1234');

    // Packages (spec §9.1) — now split by mode (v0.2 item 8) + single session (item 10)
    await client.query(`
      INSERT INTO package_definitions (name_en,name_ar,class_count,price,validity_weeks,mode,is_single) VALUES
        ('Single Session (Online)','حصة واحدة (أونلاين)',1,18.00,2,'online',TRUE),
        ('Single Session (In-person)','حصة واحدة (حضوري)',1,20.00,2,'in_person',TRUE),
        ('6 Classes — Online','باقة 6 حصص أونلاين',6,90.00,8,'online',FALSE),
        ('9 Classes — Online','باقة 9 حصص أونلاين',9,126.00,12,'online',FALSE),
        ('12 Classes — Online','باقة 12 حصة أونلاين',12,156.00,16,'online',FALSE),
        ('6 Classes — In-person','باقة 6 حصص حضوري',6,108.00,8,'in_person',FALSE),
        ('9 Classes — In-person','باقة 9 حصص حضوري',9,153.00,12,'in_person',FALSE),
        ('12 Classes — In-person','باقة 12 حصة حضوري',12,192.00,16,'in_person',FALSE)
      -- (v0.15) The old 'ON CONFLICT DO NOTHING' had no constraint to act on,
      -- so re-seeding duplicated the entire catalogue. name_en is unique as of
      -- migration v0_15; this now really is idempotent.
      ON CONFLICT (name_en) DO NOTHING`);

    // Slot templates (spec §5) — a 1-on-1 online slot and a group in-person slot
    await client.query(`
      INSERT INTO slot_templates (day_of_week,start_time,duration,capacity,delivery) VALUES
        (6,'09:00','60',1,'online'),     -- Saturday 1-on-1 online
        (6,'10:30','60',1,'in_person'),  -- Saturday 1-on-1 in person
        (0,'18:00','45',10,'in_person'), -- Sunday group class (cap 10)
        (1,'07:00','30',1,'online')      -- Monday early 1-on-1 online
      -- Legacy table (unused since v0.5). Seed once, never duplicate.
      ON CONFLICT DO NOTHING`);

    // Payment note (spec §10.3)
    await client.query(
      `UPDATE payment_notes SET
         body_en='To activate your package, transfer the amount to: Bank ABC, IBAN JO00 0000 0000, Acct: Fitness Co. Then notify admin. Your package activates once payment is confirmed.',
         body_ar='لتفعيل باقتك، قم بتحويل المبلغ إلى: بنك ABC، آيبان JO00 0000 0000. ثم أبلغ الإدارة. سيتم تفعيل باقتك عند تأكيد الدفع.'
       WHERE id=1`
    );
  });
  console.log('Seed complete.');
  await pool.end();
}

seed().catch((e) => { console.error(e); process.exit(1); });
