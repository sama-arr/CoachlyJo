import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth_state_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/i18n_v0_13.dart';
import 'settings_screen_v0_13.dart';
import 'contact_us_v0_13.dart';
import 'account_v0_13.dart';
import 'about_v0_13.dart';

/// (v0.14 item 21) The settings cog is replaced by a hamburger that opens a
/// real slide-out drawer, instead of a popup menu that could only ever hold a
/// couple of lines. Settings, profile, bio, contact and sign-out live here.
class AppDrawer extends StatelessWidget {
  final String role;   // 'member' | 'coach' | 'admin'
  const AppDrawer({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final auth = context.read<AuthState>();
    final light = Theme.of(context).brightness == Brightness.light;
    final scheme = Theme.of(context).colorScheme;

    Widget item(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
      return ListTile(
        leading: Icon(icon, size: 21, color: danger ? scheme.error : null),
        title: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? scheme.error : null)),
        onTap: () {
          Navigator.pop(context);   // close the drawer first
          onTap();
        },
      );
    }

    return Drawer(
      backgroundColor: light ? Brand.surfaceLight : Brand.surface,
      child: SafeArea(
        child: Column(children: [
          // ---- brand header ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: light
                    ? [Brand.magentaLight.withValues(alpha: 0.14), Brand.orangeLight.withValues(alpha: 0.08)]
                    : [Brand.magenta.withValues(alpha: 0.28), Brand.orange.withValues(alpha: 0.16)],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CoachlyWordmark(fontSize: 26),
              const SizedBox(height: 8),
              Text(
                auth.email ?? tr(context, 'Signed in'),
                style: TextStyle(
                    fontSize: 12,
                    color: light ? Brand.mutedLight : c.onPanel),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                role == 'coach' ? tr(context, 'Coach')
                    : role == 'admin' ? tr(context, 'Administrator')
                    : tr(context, 'Member'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ]),
          ),

          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              item(Icons.settings_outlined, tr(context, 'Settings'),
                  () => Navigator.push(context, fadeSlideRoute(const SettingsScreen()))),

              if (role == 'coach')
                item(Icons.badge_outlined, tr(context, 'Change bio'),
                    () => Navigator.push(context,
                        fadeSlideRoute(const SettingsScreen(section: 'bio')))),

              if (role == 'coach')
                item(Icons.photo_camera_outlined, tr(context, 'Profile photo'),
                    () => Navigator.push(context,
                        fadeSlideRoute(const SettingsScreen(section: 'photo')))),

              item(Icons.lock_outline, tr(context, 'Change password'),
                  () => Navigator.push(context,
                      fadeSlideRoute(const SettingsScreen(section: 'password')))),

              item(Icons.support_agent, tr(context, 'Contact us'),
                  () => Navigator.push(context, fadeSlideRoute(const ContactUsScreen()))),

              const Divider(height: 18),

              item(Icons.privacy_tip_outlined, tr(context, 'Privacy Policy'),
                  () => Navigator.push(context,
                      fadeSlideRoute(const LegalScreen(onlyKey: 'legal_privacy')))),
              item(Icons.description_outlined, tr(context, 'Terms of Service'),
                  () => Navigator.push(context,
                      fadeSlideRoute(const LegalScreen(onlyKey: 'legal_terms')))),

              const Divider(height: 18),

              // (v0.15 item 3) About sits directly above Sign out and shows the
              // version plus which API this build is talking to.
              item(Icons.info_outline, tr(context, 'About'),
                  () => Navigator.push(context, fadeSlideRoute(const AboutScreen()))),

              item(Icons.logout, tr(context, 'Sign out'), () => auth.logout(), danger: true),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('CoachlyJo',
                style: TextStyle(
                    fontSize: 11,
                    color: light ? Brand.mutedLight : c.faint)),
          ),
        ]),
      ),
    );
  }
}
