import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/api_v0_13.dart';
import '../core/config_v0_13.dart';
import '../core/version_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/gym_art_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// =============================================================================
/// About (v0.15 item 3).
///
/// Sits above Sign out in the drawer. Shows the app version and — deliberately
/// — the API host this build talks to. With staging and production running side
/// by side, "which backend is this tester on?" was guesswork; now it is one tap,
/// and a long-press copies the details for a bug report.
/// =============================================================================
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? serverSchema;
  String? serverEnvironment;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    _ping();
  }

  /// Confirms the app can actually reach its API, and reports what it found.
  Future<void> _ping() async {
    try {
      final r = Map<String, dynamic>.from(
        await ApiClient.instance.get('/health/schema'),
      );
      if (mounted) {
        setState(() {
          serverSchema = 'v${r['current']} (expects v${r['expected']})';
          serverEnvironment = r['upToDate'] == true
              ? 'ok'
              : 'schema out of date';
          checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          serverEnvironment = 'unreachable';
          checking = false;
        });
      }
    }
  }

  String get _host {
    final raw = AppConfig.apiBaseUrl;
    return raw.replaceFirst(RegExp(r'^https?://'), '');
  }

  String get _summary =>
      'CoachlyJo $appVersion (build $appBuildNumber)\n'
      'API: ${AppConfig.apiBaseUrl}\n'
      'Server: ${serverSchema ?? 'unknown'} · ${serverEnvironment ?? 'checking'}';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final reachable = serverEnvironment == 'ok';

    Widget row(
      IconData icon,
      String label,
      String value, {
      Color? valueColor,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? c.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'About CoachlyJo'))),
      body: GlowBackground(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            FadeInUp(
              child: GymBanner(
                title: 'CoachlyJo',
                subtitle: tr(context, 'Fitness coaching in Amman'),
                art: GymArt.dumbbell,
              ),
            ),
            FadeInUp(
              index: 1,
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row(
                        Icons.info_outline,
                        tr(context, 'App version'),
                        '$appVersion (build $appBuildNumber)',
                      ),
                      Divider(color: c.border, height: 10),
                      row(
                        Icons.dns_outlined,
                        tr(context, 'Connected to'),
                        _host,
                      ),
                      Divider(color: c.border, height: 10),
                      row(
                        reachable
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        tr(context, 'Server'),
                        checking
                            ? tr(context, 'Checking…')
                            : reachable
                            ? '${serverSchema!} · ${tr(context, 'reachable')}'
                            : '${serverEnvironment!}',
                        valueColor: checking
                            ? null
                            : (reachable ? c.success : c.danger),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            FadeInUp(
              index: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _summary));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              context,
                              'Details copied — paste them into your report.',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr(context, 'Copy details for a bug report')),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                '© ${DateTime.now().year} CoachlyJo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
