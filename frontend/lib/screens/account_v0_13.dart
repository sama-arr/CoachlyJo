import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/i18n_v0_13.dart';
import 'package:provider/provider.dart';

/// (v0.13) Privacy policy / terms viewer.
///
/// Both stores require the policy to be reachable, and reviewers check it
/// BEFORE signing in — so this screen works with or without a session (the
/// endpoint is public).
class LegalScreen extends StatefulWidget {
  /// 'legal_privacy' or 'legal_terms'; null shows both.
  final String? onlyKey;
  const LegalScreen({super.key, this.onlyKey});
  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  List blocks = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final all = await ApiClient.instance.get('/api/account/legal');
      blocks = widget.onlyKey == null
          ? all
          : (all as List).where((b) => b['key'] == widget.onlyKey).toList();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Legal'))),
      body: GlowBackground(
        child: loading
            ? const SkeletonList(count: 2)
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: [
                        ...blocks.asMap().entries.map((e) {
                          final b = e.value as Map;
                          final title =
                              isAr && '${b['title_ar']}'.trim().isNotEmpty
                                  ? '${b['title_ar']}'
                                  : '${b['title_en']}';
                          final body =
                              isAr && '${b['body_ar']}'.trim().isNotEmpty
                                  ? '${b['body_ar']}'
                                  : '${b['body_en']}';
                          return FadeInUp(
                            index: e.key,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  Text(title,
                                      style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  const GradientRule(width: 46),
                                  const SizedBox(height: 12),
                                  Text(body,
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.7,
                                          color: c.onPanel)),
                                  const SizedBox(height: 22),
                                ]),
                          );
                        }),
                      ]),
      ),
    );
  }
}

/// (v0.13) Account deletion — Apple requires an in-app path, Google requires
/// the same plus the web route we serve at /delete-account.
///
/// Flow: show exactly what will be lost -> type DELETE -> confirm with the
/// account password -> the account is erased and the session ends.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  AppColors get c => AppColors.of(context);
  Map? preview;
  bool loading = true;
  bool busy = false;
  String? error;
  final _confirm = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      preview = Map<String, dynamic>.from(
          await ApiClient.instance.get('/api/account/deletion-preview'));
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    if (mounted) setState(() => loading = false);
  }

  bool get _ready =>
      _confirm.text.trim().toUpperCase() == 'DELETE' &&
      _password.text.isNotEmpty;

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete your account?')),
        content: Text(tr(ctx,
            'This cannot be undone. Your personal data will be erased and your upcoming sessions cancelled.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'Keep my account'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Delete permanently')),
          ),
        ],
      ),
    );
    if (sure != true) return;

    setState(() => busy = true);
    try {
      await ApiClient.instance
          .delete('/api/account', body: {'password': _password.text});
      if (!mounted) return;
      // End the session: the account no longer exists.
      await context.read<AuthState>().logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr(
                context, 'Your account and personal data have been deleted.'))),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Delete account'))),
      body: GlowBackground(
        child: loading
            ? const SkeletonList(count: 2)
            : ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const GradientIconBadge(
                                icon: Icons.delete_forever, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                  tr(context,
                                      'This permanently deletes your account'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          Text(
                              tr(context,
                                  'We erase your name, email, phone number, date of birth, location, questionnaire answers, uploaded documents and payment-proof images, and your notifications.'),
                              style: TextStyle(
                                  fontSize: 13, height: 1.6, color: c.onPanel)),
                          const SizedBox(height: 10),
                          Text(
                              tr(context,
                                  'We keep an anonymised record of completed purchases where accounting law requires it. It cannot identify you.'),
                              style: TextStyle(
                                  fontSize: 12, height: 1.6, color: c.muted)),
                        ]),
                  ),
                ),

                // What the user loses right now — concrete, not abstract.
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(context, 'Before you go'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            _line(Icons.event_busy,
                                '${preview!['upcomingSessions']} ${tr(context, 'upcoming session(s) will be cancelled')}'),
                            if ((preview!['unusedClasses'] ?? 0) > 0)
                              _line(Icons.card_membership,
                                  '${preview!['unusedClasses']} ${tr(context, 'unused class(es) will be lost')}',
                                  warn: true),
                          ]),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Text(tr(context, 'Type DELETE to confirm'),
                    style: TextStyle(fontSize: 12, color: c.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _confirm,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'DELETE'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      InputDecoration(labelText: tr(context, 'Your password')),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_ready && !busy) ? _delete : null,
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(tr(context, 'Delete my account')),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'Keep my account')),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _line(IconData icon, String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: warn ? c.danger : c.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
