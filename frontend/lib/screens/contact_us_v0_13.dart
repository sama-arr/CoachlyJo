import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/gym_art_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// (v0.14 item 6) Contact Us.
///
/// Every detail is admin-configurable (Admin → Setup → Contact details), so the
/// phone number and Instagram handle can be filled in later without an app
/// release. Rows only appear once they have a value, and each one is tappable:
/// email opens the mail app, phone dials, WhatsApp and Instagram deep-link.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});
  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  Map? contact;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      contact = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/contact'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Could not open that app on this device.'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Could not open that app on this device.'))));
      }
    }
  }

  Widget _row(IconData icon, String label, String value, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: GradientIconBadge(icon: icon, size: 34),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6))),
        subtitle: Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = '${contact?['email'] ?? ''}';
    final phone = '${contact?['phone'] ?? ''}';
    final insta = '${contact?['instagram'] ?? ''}';
    final wa = '${contact?['whatsapp'] ?? ''}';

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Contact us'))),
      body: GlowBackground(
        child: loading
            ? const SkeletonList(count: 3)
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                    FadeInUp(
                      child: GymBanner(
                        title: tr(context, 'We are here to help'),
                        subtitle: tr(context, 'Questions about a package, a session or your account? Reach us any way you like.'),
                        art: GymArt.heartRate,
                      ),
                    ),
                    if (email.isNotEmpty)
                      FadeInUp(index: 1, child: _row(Icons.email_outlined, tr(context, 'Email'), email,
                          () => _open(Uri(scheme: 'mailto', path: email,
                              queryParameters: {'subject': 'CoachlyJo support'})))),
                    if (phone.isNotEmpty)
                      FadeInUp(index: 2, child: _row(Icons.phone_outlined, tr(context, 'Phone'), phone,
                          () => _open(Uri(scheme: 'tel', path: phone.replaceAll(' ', ''))))),
                    if (wa.isNotEmpty)
                      FadeInUp(index: 3, child: _row(Icons.chat_outlined, 'WhatsApp', wa,
                          () => _open(Uri.parse(
                              'https://wa.me/${wa.replaceAll(RegExp(r'[^0-9]'), '')}')))),
                    if (insta.isNotEmpty)
                      FadeInUp(index: 4, child: _row(Icons.camera_alt_outlined, 'Instagram',
                          insta.startsWith('@') ? insta : '@$insta',
                          () => _open(Uri.parse(
                              'https://instagram.com/${insta.replaceAll('@', '')}')))),
                    if (email.isEmpty && phone.isEmpty && insta.isEmpty && wa.isEmpty)
                      EmptyState(
                        icon: Icons.support_agent,
                        message: tr(context, 'Contact details have not been added yet.'),
                      ),
                  ]),
      ),
    );
  }
}
