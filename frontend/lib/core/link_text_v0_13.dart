import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A tappable hyperlink (v0.4 item 2 — Zoom links open the Zoom app/browser).
class LinkText extends StatelessWidget {
  final String url;
  final String? label;
  final IconData icon;
  const LinkText({super.key, required this.url, this.label, this.icon = Icons.videocam});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label ?? url,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, decoration: TextDecoration.underline, decorationColor: color),
            ),
          ),
        ]),
      ),
    );
  }
}
