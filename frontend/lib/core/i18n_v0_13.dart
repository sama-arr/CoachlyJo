import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// =============================================================================
/// CoachlyJo i18n (v0.7 item 3): English + Arabic for the member and coach
/// experience (admin stays English by agreement).
///
/// Approach: the ENGLISH source string is the key. `tr(context, 'Log in')`
/// returns the Arabic translation in Arabic mode, or the string itself in
/// English mode / when a translation is missing — the app can never crash or
/// show blank text because of a missing key.
///
/// RTL: MaterialApp gets the locale from AppLang; Flutter flips layout
/// direction automatically for 'ar'.
///
/// Digits: per client decision, Western digits (0-9) everywhere. Arabic date
/// formatting goes through [fmtDate], which converts any Eastern Arabic
/// numerals the locale produces back to Western ones.
/// =============================================================================

class AppLang extends ChangeNotifier {
  static const _key = 'coachly_lang';
  String code = 'en';
  bool get isAr => code == 'ar';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    code = prefs.getString(_key) ?? 'en';
    notifyListeners();
  }

  Future<void> set(String c) async {
    code = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, c);
  }

  Future<void> toggle() => set(isAr ? 'en' : 'ar');
}

/// Translate an English source string. Falls back to English when missing.
String tr(BuildContext context, String en) {
  final lang = Provider.of<AppLang>(context, listen: false);
  if (!lang.isAr) return en;
  return _ar[en] ?? en;
}

/// Package display name honoring the language (packages carry name_ar).
String pkgName(BuildContext context, Map p) {
  final lang = Provider.of<AppLang>(context, listen: false);
  final ar = (p['name_ar'] ?? '').toString();
  return lang.isAr && ar.isNotEmpty ? ar : (p['name_en'] ?? '').toString();
}

/// Payment note honoring the language (body_ar with EN fallback).
String noteBody(BuildContext context, Map note) {
  final lang = Provider.of<AppLang>(context, listen: false);
  final ar = (note['body_ar'] ?? '').toString();
  final en = (note['body_en'] ?? '').toString();
  return lang.isAr && ar.isNotEmpty ? ar : en;
}

const _eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// Format a date in the active locale, always with Western digits.
String fmtDate(BuildContext context, DateTime dt, String pattern) {
  final lang = Provider.of<AppLang>(context, listen: false);
  var out = DateFormat(pattern, lang.isAr ? 'ar' : 'en').format(dt);
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_eastern[i], '$i');
  }
  return out;
}

/// Booking/package status labels.
String trStatus(BuildContext context, String s) => tr(context, s);

// ---------------------------------------------------------------------------
// Arabic dictionary — English source string -> Arabic.
// ---------------------------------------------------------------------------
const Map<String, String> _ar = {
  // --- shared / navigation ---
  'Coaches': 'المدربون',
  'Bookings': 'الحجوزات',
  'Packages': 'الباقات',
  'Profile': 'الملف الشخصي',
  'Requests': 'الطلبات',
  'Sessions': 'الجلسات',
  'Availability': 'الأوقات المتاحة',
  'Clients': 'العملاء',
  'Dashboard': 'لوحة المتابعة',
  'Settings': 'الإعدادات',
  'Cancel': 'إلغاء',
  'OK': 'حسناً',
  'Save': 'حفظ',
  'Add': 'إضافة',
  'Delete': 'حذف',
  'Submit': 'إرسال',
  'Retry': 'إعادة المحاولة',
  'Log out': 'تسجيل الخروج',
  'Online': 'أونلاين',
  'In-person': 'حضوري',
  'Status': 'الحالة',
  'pending': 'قيد الانتظار',
  'accepted': 'مقبول',
  'rejected': 'مرفوض',
  'cancelled': 'ملغي',
  'completed': 'مكتمل',
  'active': 'فعّالة',
  'expired': 'منتهية',
  'pending_payment': 'بانتظار الدفع',
  'Cannot reach server.': 'تعذر الوصول إلى الخادم.',

  // --- login / auth ---
  'Train with the right coach.': 'تدرّب مع المدرب المناسب.',
  'Email': 'البريد الإلكتروني',
  'Password': 'كلمة المرور',
  'Log in': 'تسجيل الدخول',
  'Create an account': 'إنشاء حساب',
  'Forgot password?': 'نسيت كلمة المرور؟',
  'Forgot password': 'نسيت كلمة المرور',
  'Send code': 'إرسال الرمز',
  'Send a new code': 'إرسال رمز جديد',
  'Reset password': 'إعادة تعيين كلمة المرور',
  'Reset code': 'رمز إعادة التعيين',
  'New password (min 8)': 'كلمة المرور الجديدة (8 على الأقل)',
  'Confirm new password': 'تأكيد كلمة المرور الجديدة',
  'Enter your account email and we will send you a reset code.':
      'أدخل بريدك الإلكتروني وسنرسل لك رمز إعادة التعيين.',
  'Enter the 6-character code from your email and choose a new password.':
      'أدخل الرمز المكوّن من 6 خانات من بريدك واختر كلمة مرور جديدة.',
  '6 characters, expires in 10 minutes': '6 خانات، تنتهي صلاحيته خلال 10 دقائق',
  'Password reset. You can log in with your new password.':
      'تمت إعادة التعيين. يمكنك تسجيل الدخول بكلمة المرور الجديدة.',

  // --- member: coaches & booking ---
  'Book': 'حجز',
  'Book a session': 'حجز جلسة',
  'Trial': 'جلسة تجريبية',
  'No approved coaches available yet.': 'لا يوجد مدربون معتمدون حالياً.',
  'No sessions available for this coach yet.': 'لا توجد جلسات متاحة لهذا المدرب حالياً.',
  'Rating': 'التقييم',
  'About': 'نبذة',
  'Upcoming': 'القادمة',
  'History': 'السجل',
  'Completed, cancelled and rejected sessions': 'الجلسات المكتملة والملغاة والمرفوضة',
  'No upcoming sessions. Find a coach and book your next session!':
      'لا توجد جلسات قادمة. ابحث عن مدرب واحجز جلستك التالية!',
  'No past sessions yet.': 'لا توجد جلسات سابقة بعد.',
  'Join Zoom session': 'الانضمام إلى جلسة زوم',
  'Review': 'تقييم',
  'Reviewed': 'تم التقييم',
  'Rate your session': 'قيّم جلستك',
  'Comment (optional)': 'تعليق (اختياري)',
  'Reason': 'السبب',
  'No-show': 'لم يحضر',
  'Cancel this booking?': 'إلغاء هذا الحجز؟',
  'Keep booking': 'الاحتفاظ بالحجز',
  'Yes, cancel': 'نعم، إلغاء',
  'This session is today. Cancelling now counts as a same-day cancellation and a class WILL be deducted from your package.':
      'هذه الجلسة اليوم. الإلغاء الآن يُعد إلغاءً في نفس اليوم وسيتم خصم حصة من باقتك.',
  'This session is not today, so no class will be deducted from your package.':
      'هذه الجلسة ليست اليوم، لذلك لن يتم خصم أي حصة من باقتك.',

  // --- member: packages / purchase ---
  'My Packages': 'باقاتي',
  'Buy a package': 'شراء باقة',
  'Past packages': 'الباقات السابقة',
  'Finished, expired and cancelled': 'المنتهية والمنتهية الصلاحية والملغاة',
  'No past packages yet.': 'لا توجد باقات سابقة بعد.',
  'No packages yet. Packages are purchased per coach — tap "Buy a package" to start.':
      'لا توجد باقات بعد. تُشترى الباقات لكل مدرب — اضغط "شراء باقة" للبدء.',
  'Packages are purchased for one specific coach — you will use all its classes with them.':
      'تُشترى الباقة لمدرب محدد — ستستخدم جميع حصصها معه.',
  'Coach': 'المدرب',
  'Session type': 'نوع الجلسة',
  'Classes': 'الحصص',
  'Single session': 'جلسة واحدة',
  'classes': 'حصص',
  'Choose Online or In-person to see the class options.':
      'اختر أونلاين أو حضوري لعرض خيارات الحصص.',
  'Valid': 'صالحة لمدة',
  'weeks': 'أسابيع',
  'Please pay to the following bank details:': 'يرجى الدفع إلى الحساب البنكي التالي:',
  'Contact admin for payment details.': 'تواصل مع الإدارة لتفاصيل الدفع.',
  'Then upload your proof of payment (required)': 'ثم ارفع إثبات الدفع (مطلوب)',
  'No image selected': 'لم يتم اختيار صورة',
  'Upload': 'رفع',
  'Request submitted': 'تم إرسال الطلب',
  'Your proof of payment was submitted. The package activates once the admin confirms the payment.':
      'تم إرسال إثبات الدفع. سيتم تفعيل الباقة بعد تأكيد الإدارة للدفع.',
  'Proof submitted — awaiting admin confirmation.': 'تم إرسال الإثبات — بانتظار تأكيد الإدارة.',
  'Payment proof rejected': 'تم رفض إثبات الدفع',
  'Re-upload proof': 'إعادة رفع الإثبات',
  'New proof submitted — awaiting review.': 'تم إرسال إثبات جديد — بانتظار المراجعة.',
  'Remaining': 'المتبقي',
  'Pending': 'قيد الانتظار',
  'Activated': 'تاريخ التفعيل',
  'Expires': 'تاريخ الانتهاء',
  'Requested': 'تاريخ الطلب',

  // --- coach ---
  'Accept': 'قبول',
  'Reject': 'رفض',
  'Rejection reason': 'سبب الرفض',
  'Completed': 'مكتمل',
  'Mark completed': 'وضع علامة مكتمل',
  'Did not show up': 'لم يحضر',
  'Available after the session ends': 'متاح بعد انتهاء الجلسة',
  'Record a no-show?': 'تسجيل عدم حضور؟',
  "The member's class will still be deducted, and they cannot review this session.":
      'سيتم خصم حصة العضو مع ذلك، ولن يتمكن من تقييم هذه الجلسة.',
  'Yes, no-show': 'نعم، لم يحضر',
  'Session duration': 'مدة الجلسة',
  'min': 'دقيقة',
  'Add more': 'إضافة المزيد',
  'Add hours': 'إضافة ساعات',
  'No hours yet — add a time range.': 'لا توجد ساعات بعد — أضف نطاقاً زمنياً.',
  'day off': 'يوم إجازة',
  'saved range': 'نطاق محفوظ',
  'saved ranges': 'نطاقات محفوظة',
  'Sunday': 'الأحد',
  'Monday': 'الاثنين',
  'Tuesday': 'الثلاثاء',
  'Wednesday': 'الأربعاء',
  'Thursday': 'الخميس',
  'Friday': 'الجمعة',
  'Saturday': 'السبت',
  'Members book sessions generated from your weekly hours. Changes remove only unbooked future sessions — booked ones are always kept.':
      'يحجز الأعضاء جلسات مولّدة من ساعاتك الأسبوعية. التعديلات تزيل الجلسات المستقبلية غير المحجوزة فقط — المحجوزة تبقى دائماً.',
  'Your open bookable times, generated from your Availability. Booked sessions move to Requests. Delete a slot to make a one-off exception.':
      'أوقاتك المتاحة للحجز، مولّدة من صفحة الأوقات المتاحة. الجلسات المحجوزة تنتقل إلى الطلبات. احذف وقتاً لعمل استثناء لمرة واحدة.',
  'No open slots.\n\nSlots are generated automatically from your Availability — set your weekly hours in the Availability tab. Booked sessions appear under Requests.':
      'لا توجد أوقات متاحة.\n\nتُولَّد الأوقات تلقائياً من صفحة الأوقات المتاحة — حدّد ساعاتك الأسبوعية هناك. الجلسات المحجوزة تظهر في الطلبات.',
  'Active': 'الحاليون',
  'No requests yet.': 'لا توجد طلبات بعد.',
  'sessions added': 'جلسات أُضيفت',
  'unbooked sessions removed': 'جلسات غير محجوزة أُزيلت',
  'booked session kept': 'جلسة محجوزة أُبقيت',
  'booked sessions kept': 'جلسات محجوزة أُبقيت',

  'Booked! Awaiting coach acceptance.': 'تم الحجز! بانتظار قبول المدرب.',
  'Find a Coach': 'ابحث عن مدرب',
  'No reviews yet.': 'لا توجد تقييمات بعد.',
  'Reviews': 'التقييمات',
  'Sign out': 'تسجيل الخروج',
  'Upcoming sessions': 'الجلسات القادمة',
  'Buy a package with': 'شراء باقة مع',
  'Member': 'عضو',
  'Create account': 'إنشاء الحساب',
  'A few quick questions': 'بعض الأسئلة السريعة',
  'Choose': 'اختر',
  'Date of birth': 'تاريخ الميلاد',
  'Location (city / area)': 'الموقع (المدينة / المنطقة)',
  'Nationality': 'الجنسية',
  'Documents (pdf, doc, docx, jpg, png)': 'المستندات (pdf, doc, docx, jpg, png)',
  'No file selected': 'لم يتم اختيار ملف',
  'Enter the verification code sent to your phone.': 'أدخل رمز التحقق المرسل إلى هاتفك.',
  'Verify & continue': 'تحقق ومتابعة',
  'First name': 'الاسم الأول',
  'Last name': 'اسم العائلة',
  'Phone (07XXXXXXXX)': 'الهاتف (07XXXXXXXX)',
  'Bio / experience': 'نبذة / الخبرة',
  'Verification code': 'رمز التحقق',
  'Contact': 'معلومات التواصل',
  'Fitness questionnaire': 'استبيان اللياقة',
  'This member has not filled the questionnaire.': 'لم يقم هذا العضو بتعبئة الاستبيان.',
  'No packages yet.': 'لا توجد باقات بعد.',
  'used': 'مستخدمة',
  'Home': 'الرئيسية',
  'This session is today. Cancelling now costs you one session, recorded for the admin.': 'هذه الجلسة اليوم. الإلغاء الآن يكلفك جلسة واحدة تُسجّل للإدارة.',
  'Session cancelled — one session recorded against you.': 'تم إلغاء الجلسة — تم تسجيل جلسة واحدة عليك.',
  'Session cancelled.': 'تم إلغاء الجلسة.',
  'Rejection limit reached — cancel instead': 'تم بلوغ حد الرفض — قم بالإلغاء بدلاً من ذلك',
  'This session starts within 24 hours. Cancelling now WILL deduct a class from your package.': 'تبدأ هذه الجلسة خلال 24 ساعة. الإلغاء الآن سيخصم حصة من باقتك.',
  'This session is more than 24 hours away, so no class will be deducted.': 'موعد هذه الجلسة بعد أكثر من 24 ساعة، لذلك لن يتم خصم أي حصة.',
  'How it works': 'كيف يعمل التطبيق',
  'Rules & regulations': 'القواعد والأحكام',
  'Watch how CoachlyJo works': 'شاهد كيف يعمل كوتشلي جو',
  'Play video': 'تشغيل الفيديو',
  'Cancel session': 'إلغاء الجلسة',
  'Why are you cancelling?': 'ما سبب الإلغاء؟',
  'Reason (required)': 'السبب (مطلوب)',
  'The member keeps their class. Cancelling on the same day costs you one session.': 'يحتفظ العضو بحصته. الإلغاء في نفس اليوم يكلفك جلسة واحدة.',
  'You have used all 3 cancellations for this package.': 'لقد استخدمت جميع مرات الإلغاء الثلاث لهذه الباقة.',
  'cancellations left': 'مرات إلغاء متبقية',
  'Sessions owed': 'جلسات مستحقة عليك',
  'rejections used': 'مرات رفض مستخدمة',
  'Notifications': 'الإشعارات',
  'Mark all read': 'تعليم الكل كمقروء',
  'No notifications yet. Updates about your sessions and packages appear here.': 'لا توجد إشعارات بعد. ستظهر هنا التحديثات المتعلقة بجلساتك وباقاتك.',
  'just now': 'الآن',
  'm ago': ' د',
  'h ago': ' س',
  'd ago': ' ي',
  'Archive': 'أرشفة',
  'Legal': 'المستندات القانونية',
  'Privacy Policy': 'سياسة الخصوصية',
  'Terms of Service': 'شروط الاستخدام',
  'Delete account': 'حذف الحساب',
  'Permanently remove your account and personal data': 'إزالة حسابك وبياناتك الشخصية نهائياً',
  'This permanently deletes your account': 'سيؤدي هذا إلى حذف حسابك نهائياً',
  'We erase your name, email, phone number, date of birth, location, questionnaire answers, uploaded documents and payment-proof images, and your notifications.': 'نمسح اسمك وبريدك الإلكتروني ورقم هاتفك وتاريخ ميلادك وموقعك وإجابات الاستبيان والمستندات المرفوعة وصور إثبات الدفع وإشعاراتك.',
  'We keep an anonymised record of completed purchases where accounting law requires it. It cannot identify you.': 'نحتفظ بسجل مجهول الهوية لعمليات الشراء المكتملة عند اشتراط القانون المحاسبي ذلك، ولا يمكنه التعرف عليك.',
  'Before you go': 'قبل أن تغادر',
  'upcoming session(s) will be cancelled': 'جلسة قادمة سيتم إلغاؤها',
  'unused class(es) will be lost': 'حصة غير مستخدمة ستفقدها',
  'Type DELETE to confirm': 'اكتب DELETE للتأكيد',
  'Your password': 'كلمة المرور',
  'Delete my account': 'حذف حسابي',
  'Keep my account': 'الاحتفاظ بحسابي',
  'Delete your account?': 'هل تريد حذف حسابك؟',
  'This cannot be undone. Your personal data will be erased and your upcoming sessions cancelled.': 'لا يمكن التراجع عن هذا. سيتم مسح بياناتك الشخصية وإلغاء جلساتك القادمة.',
  'Delete permanently': 'حذف نهائي',
  'Your account and personal data have been deleted.': 'تم حذف حسابك وبياناتك الشخصية.',
  // --- settings ---
  'Language': 'اللغة',
  'Change bio': 'تعديل النبذة',
  'Change password': 'تغيير كلمة المرور',
  'Old password': 'كلمة المرور الحالية',
  'New password': 'كلمة المرور الجديدة',
  'Password changed.': 'تم تغيير كلمة المرور.',
};
