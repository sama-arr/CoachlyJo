import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// (v0.11 item 2) Bell icon with an unread badge, for any app bar.
/// Polls the cheap unread-count endpoint; refreshes when the centre closes.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Light polling — one tiny COUNT query per minute.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    try {
      final r = await ApiClient.instance.get('/api/notifications/unread-count');
      if (mounted) setState(() => unread = int.tryParse('${r['unread']}') ?? 0);
    } catch (_) { /* badge is best-effort */ }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      IconButton(
        icon: const Icon(Icons.notifications_none),
        tooltip: tr(context, 'Notifications'),
        onPressed: () async {
          await Navigator.push(context, fadeSlideRoute(const NotificationsScreen()));
          _refresh();
        },
      ),
      if (unread > 0)
        Positioned(
          top: 8,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 17),
            decoration: BoxDecoration(
              gradient: Brand.gradientVivid,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Brand.background, width: 1.5),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ),
    ]);
  }
}

/// The notification centre itself.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List items = [];
  int unread = 0;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = Map<String, dynamic>.from(await ApiClient.instance.get('/api/notifications'));
      items = r['items'] as List;
      unread = int.tryParse('${r['unread']}') ?? 0;
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _markRead(Map n) async {
    if (n['read_at'] != null) return;
    try {
      await ApiClient.instance.post('/api/notifications/${n['id']}/read');
      _load();
    } on ApiException catch (_) {}
  }

  Future<void> _readAll() async {
    try {
      await ApiClient.instance.post('/api/notifications/read-all');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(Map n) async {
    try {
      await ApiClient.instance.delete('/api/notifications/${n['id']}');
      _load();
    } on ApiException catch (_) {}
  }

  /// Icon + colour per event family, so the list is scannable.
  (IconData, Color) _style(String type) {
    if (type.startsWith('booking_accepted') || type == 'coach_approved' || type == 'package_activated') {
      return (Icons.check_circle, const Color(0xFF3ED598));
    }
    if (type.contains('reject') || type.contains('cancel') || type == 'no_show_recorded' || type == 'penalty_recorded') {
      return (Icons.error_outline, const Color(0xFFFF5470));
    }
    if (type == 'session_reminder') return (Icons.alarm, Brand.orange);
    if (type.startsWith('package')) return (Icons.card_membership, Brand.magenta);
    if (type.startsWith('admin_')) return (Icons.admin_panel_settings, Brand.orange);
    if (type == 'booking_requested' || type == 'new_client') return (Icons.person_add_alt, Brand.magenta);
    return (Icons.notifications, Brand.magenta);
  }

  String _relative(BuildContext context, String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return tr(context, 'just now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}${tr(context, 'm ago')}';
    if (diff.inHours < 24) return '${diff.inHours}${tr(context, 'h ago')}';
    if (diff.inDays < 7) return '${diff.inDays}${tr(context, 'd ago')}';
    return fmtDate(context, d, 'd MMM');
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Notifications')),
        actions: [
          if (unread > 0)
            TextButton(onPressed: _readAll, child: Text(tr(context, 'Mark all read'))),
        ],
      ),
      body: GlowBackground(
        child: loading
            ? const SkeletonList()
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : items.isEmpty
                    ? EmptyState(
                        icon: Icons.notifications_none,
                        message: tr(context, 'No notifications yet. Updates about your sessions and packages appear here.'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 24),
                          children: items.asMap().entries.map<Widget>((e) {
                            final n = e.value as Map;
                            final isUnread = n['read_at'] == null;
                            final (icon, color) = _style('${n['type']}');
                            final title = isAr && '${n['title_ar']}'.trim().isNotEmpty
                                ? '${n['title_ar']}' : '${n['title_en']}';
                            final body = isAr && '${n['body_ar'] ?? ''}'.trim().isNotEmpty
                                ? '${n['body_ar']}' : '${n['body_en'] ?? ''}';
                            return FadeInUp(
                              index: e.key,
                              child: PressableCard(
                                onTap: () => _markRead(n),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isUnread ? Brand.surfaceHigh : Brand.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isUnread ? color.withValues(alpha: 0.35) : const Color(0xFF23232C),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(icon, size: 17, color: color),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Row(children: [
                                            Expanded(
                                              child: Text(title,
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500)),
                                            ),
                                            if (isUnread)
                                              Container(
                                                width: 7, height: 7,
                                                margin: const EdgeInsets.only(left: 6),
                                                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                              ),
                                          ]),
                                          if (body.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(body,
                                                style: const TextStyle(
                                                    fontSize: 12, height: 1.4, color: Color(0xFFCFCFDA))),
                                          ],
                                          const SizedBox(height: 5),
                                          Text(_relative(context, '${n['created_at']}'),
                                              style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E7A))),
                                        ]),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        color: const Color(0xFF6E6E7A),
                                        onPressed: () => _delete(n),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
      ),
    );
  }
}
