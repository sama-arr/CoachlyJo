import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_v0_13.dart';
import '../core/i18n_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/upload_picker_v0_13.dart';
import '../core/theme_v0_13.dart';
import 'account_v0_13.dart';
import 'contact_us_v0_13.dart';
import '../core/motion_v0_13.dart';

/// Settings hub (v0.8). `section` narrows the screen to one card when opened
/// from a specific menu entry; the default shows everything relevant to the
/// role, with the LANGUAGE switch first (item 2 — it was buried in v0.7).
class SettingsScreen extends StatelessWidget {
  final String section; // 'all' | 'password' | 'payment' | 'bio'
  const SettingsScreen({super.key, this.section = 'all'});

  @override
  Widget build(BuildContext context) {
    final title = section == 'payment' ? 'Payment details'
        : section == 'bio' ? 'About me'
        : section == 'password' ? tr(context, 'Change password')
        : section == 'photo' ? tr(context, 'Profile photo')
        : tr(context, 'Settings');
    final showAll = section == 'all';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: GlowBackground(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // (v0.14 item 12) Theme choice sits beside language.
          if (showAll) const _LanguageCard(),
          if (showAll) const _ThemeCard(),
          // (v0.14 item 8) Change password is its own screen now: tapping the
          // row opens it, rather than showing the fields inline on a list of
          // unrelated settings.
          if (showAll)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const GradientIconBadge(icon: Icons.lock_outline, size: 32),
                title: Text(tr(context, 'Change password')),
                subtitle: Text(tr(context, 'Update the password you sign in with'),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    fadeSlideRoute(const SettingsScreen(section: 'password'))),
              ),
            ),
          if (showAll)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const GradientIconBadge(icon: Icons.support_agent, size: 32),
                title: Text(tr(context, 'Contact us')),
                subtitle: Text(tr(context, 'Email, phone and Instagram'),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, fadeSlideRoute(const ContactUsScreen())),
              ),
            ),
          if (section == 'password') const _ChangePasswordCard(),
          if (section == 'bio') const _CoachAboutCard(),
          if (section == 'photo') const _CoachPhotoCard(),
          if (section == 'payment') const _PaymentNoteCard(),
          // (v0.13) Store-required: legal documents and account deletion must
          // both be reachable from inside the app.
          if (showAll) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                ListTile(
                  leading: const GradientIconBadge(icon: Icons.privacy_tip_outlined, size: 32),
                  title: Text(tr(context, 'Privacy Policy')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      fadeSlideRoute(const LegalScreen(onlyKey: 'legal_privacy'))),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const GradientIconBadge(icon: Icons.description_outlined, size: 32),
                  title: Text(tr(context, 'Terms of Service')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      fadeSlideRoute(const LegalScreen(onlyKey: 'legal_terms'))),
                ),
              ]),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text(tr(context, 'Delete account'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                subtitle: Text(tr(context, 'Permanently remove your account and personal data'),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, fadeSlideRoute(const DeleteAccountScreen())),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ChangePasswordCard extends StatefulWidget {
  const _ChangePasswordCard();
  @override
  State<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<_ChangePasswordCard> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _msg;
  bool _ok = false;

  Future<void> _submit() async {
    setState(() { _msg = null; });
    if (_new.text != _confirm.text) { setState(() { _msg = 'New password and confirmation do not match'; _ok = false; }); return; }
    if (_new.text.length < 8) { setState(() { _msg = 'New password must be at least 8 characters'; _ok = false; }); return; }
    try {
      await ApiClient.instance.post('/api/auth/change-password', {
        'oldPassword': _old.text, 'newPassword': _new.text, 'confirmPassword': _confirm.text,
      });
      setState(() { _msg = tr(context, 'Password changed.'); _ok = true; _old.clear(); _new.clear(); _confirm.clear(); });
    } on ApiException catch (e) {
      setState(() { _msg = e.message; _ok = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr(context, 'Change password'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      _pw(_old, 'Current password'),
      _pw(_new, 'New password (min 8)'),
      _pw(_confirm, 'Confirm new password'),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text(_msg!, style: TextStyle(color: _ok ? Colors.green : Theme.of(context).colorScheme.error))),
      const SizedBox(height: 12),
      FilledButton(onPressed: _submit, child: const Text('Update password')),
    ])));
  }

  Widget _pw(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, obscureText: true, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
  );
}

class _CoachAboutCard extends StatefulWidget {
  const _CoachAboutCard();
  @override
  State<_CoachAboutCard> createState() => _CoachAboutCardState();
}

class _CoachAboutCardState extends State<_CoachAboutCard> {
  final _bio = TextEditingController();
  String? _msg;
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final p = await ApiClient.instance.get('/api/coaches/profile');
      _bio.text = (p['bio_en'] ?? '').toString();
    } catch (_) {}
    setState(() => loading = false);
  }

  Future<void> _save() async {
    try {
      await ApiClient.instance.put('/api/coaches/profile', {'bioEn': _bio.text});
      setState(() => _msg = 'About updated.');
    } on ApiException catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('About me', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (loading) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
      else TextField(controller: _bio, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Tell members about your coaching...')),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _save, child: const Text('Save about')),
    ])));
  }
}

// (item 13) Admin free-text editor for the bank/payment details popup.
class _PaymentNoteCard extends StatefulWidget {
  const _PaymentNoteCard();
  @override
  State<_PaymentNoteCard> createState() => _PaymentNoteCardState();
}

class _PaymentNoteCardState extends State<_PaymentNoteCard> {
  final _en = TextEditingController();
  final _ar = TextEditingController();
  String? _msg;

  Future<void> _save() async {
    try {
      await ApiClient.instance.put('/api/admin/payment-note', {'bodyEn': _en.text, 'bodyAr': _ar.text});
      setState(() => _msg = 'Payment details updated.');
    } on ApiException catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Payment / bank details (shown to members)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(controller: _en, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'English')),
      const SizedBox(height: 10),
      TextField(controller: _ar, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'العربية')),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _save, child: const Text('Save payment details')),
    ])));
  }
}


/// (v0.7 item 3) Language switch — persists per device.
/// (v0.7 item 3 / v0.8 item 2) Language switch — persists per device and is
/// the first thing in Settings so it is easy to find.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard();
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppLang>();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const GradientIconBadge(icon: Icons.language),
            const SizedBox(width: 12),
            Text(tr(context, 'Language'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'ar', label: Text('العربية')),
              ],
              selected: {lang.code},
              onSelectionChanged: (s) => lang.set(s.first),
            ),
          ),
        ]),
      ),
    );
  }
}


/// (v0.14 item 12) Light / dark / follow-system, saved on the device and
/// mirrored to the account so it follows the user to a new phone.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard();
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const GradientIconBadge(icon: Icons.brightness_6, size: 32),
            const SizedBox(width: 12),
            Text(tr(context, 'Appearance'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: 'system',
                    icon: const Icon(Icons.phone_android, size: 16),
                    label: Text(tr(context, 'System'))),
                ButtonSegment(
                    value: 'light',
                    icon: const Icon(Icons.light_mode, size: 16),
                    label: Text(tr(context, 'Light'))),
                ButtonSegment(
                    value: 'dark',
                    icon: const Icon(Icons.dark_mode, size: 16),
                    label: Text(tr(context, 'Dark'))),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => theme.set(s.first),
            ),
          ),
        ]),
      ),
    );
  }
}

/// (v0.14 item 11) Coach profile photo — optional, replaceable any time.
class _CoachPhotoCard extends StatefulWidget {
  const _CoachPhotoCard();
  @override
  State<_CoachPhotoCard> createState() => _CoachPhotoCardState();
}

class _CoachPhotoCardState extends State<_CoachPhotoCard> {
  bool busy = false;
  String? message;

  Future<void> _pick() async {
    // (v0.15 item 1) Camera or gallery, same as the documents.
    final picked = await pickUploads(context, imagesOnly: true, allowMultiple: false);
    if (picked.isEmpty) return;
    setState(() { busy = true; message = null; });
    try {
      await ApiClient.instance.post('/api/profile/coach/photo', {
        'mimeType': picked.first.mimeType,
        'dataBase64': picked.first.dataBase64,
      });
      setState(() => message = tr(context, 'Photo updated.'));
    } on ApiException catch (e) {
      setState(() => message = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() { busy = true; message = null; });
    try {
      await ApiClient.instance.delete('/api/profile/coach/photo');
      setState(() => message = tr(context, 'Photo removed.'));
    } on ApiException catch (e) {
      setState(() => message = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const GradientIconBadge(icon: Icons.photo_camera_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr(context, 'Profile photo'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(tr(context, 'Members see this on your profile. It is optional.'),
              style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _pick,
                icon: const Icon(Icons.upload, size: 18),
                label: Text(tr(context, 'Choose photo')),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: busy ? null : _remove,
              child: Text(tr(context, 'Remove')),
            ),
          ]),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(message!, style: const TextStyle(fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
