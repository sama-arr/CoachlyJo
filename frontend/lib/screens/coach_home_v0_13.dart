import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../core/api_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/i18n_v0_13.dart';
import 'coach_member_detail_v0_13.dart';
import 'home_screen_v0_13.dart';
import 'notifications_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/link_text_v0_13.dart';
import '../core/simple_charts_v0_13.dart';
import 'settings_screen_v0_13.dart';

class CoachHome extends StatefulWidget {
  const CoachHome({super.key});
  @override
  State<CoachHome> createState() => _CoachHomeState();
}

class _CoachHomeState extends State<CoachHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text([
          tr(context, 'Home'),
          tr(context, 'Requests'),
          tr(context, 'Sessions'),
          tr(context, 'Availability'),
          tr(context, 'Clients'),
          tr(context, 'Dashboard'),
        ][_tab]),
        actions: [
          const NotificationBell(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (v) {
              if (v == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              } else if (v == 'bio') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen(section: 'bio')));
              } else if (v == 'signout') {
                context.read<AuthState>().logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'settings', child: Text(tr(context, 'Settings'))),
              PopupMenuItem(value: 'bio', child: Text(tr(context, 'Change bio'))),
              PopupMenuItem(value: 'signout', child: Text(tr(context, 'Sign out'))),
            ],
          ),
        ],
      ),
      // (v0.10 item 3) Coaches get the same home page, with coach-side rules.
      body: GlowBackground(child: [const HomeScreen(audience: 'coach'), const _RequestsTab(), const _MySessionsTab(), const _AvailabilityTab(), const _ClientsTab(), const _DashboardTab()][_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr(context, 'Home')),
          NavigationDestination(icon: const Icon(Icons.inbox), label: tr(context, 'Requests')),
          NavigationDestination(icon: const Icon(Icons.event_available), label: tr(context, 'Sessions')),
          NavigationDestination(icon: const Icon(Icons.edit_calendar), label: tr(context, 'Availability')),
          NavigationDestination(icon: const Icon(Icons.groups), label: tr(context, 'Clients')),
          NavigationDestination(icon: const Icon(Icons.insights), label: tr(context, 'Dashboard')),
        ],
      ),
    );
  }
}

// ---------------- Requests (actionable bookings only, item 4) ----------------
class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List bookings = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final all = await ApiClient.instance.get('/api/coaches/bookings');
      // (item 4) Only actionable items live here: pending decisions and accepted
      // upcoming sessions. Finished history is under Clients > Completed.
      bookings = (all as List).where((b) => b['status'] == 'pending' || b['status'] == 'accepted').toList();
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _decide(Map b, bool accept) async {
    String? reason;
    if (!accept) {
      final c = TextEditingController();
      reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(
        title: const Text('Rejection reason'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Required')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Reject')),
        ],
      ));
      if (reason == null || reason.trim().isEmpty) return;
    }
    try {
      await ApiClient.instance.post('/api/bookings/${b['id']}/decision', {'accept': accept, 'rejectionReason': reason});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // (v0.10 item 2) Coach cancels a session. The member always keeps their
  // class; cancelling on the same day costs the coach one session (recorded
  // for the admin to settle).
  Future<void> _coachCancel(Map b) async {
    final start = DateTime.tryParse(b['start_at'] ?? '')?.toLocal();
    final now = DateTime.now();
    final sameDay = start != null && start.year == now.year && start.month == now.month && start.day == now.day;
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Cancel session')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            sameDay
                ? tr(ctx, 'This session is today. Cancelling now costs you one session, recorded for the admin.')
                : tr(ctx, 'The member keeps their class. Cancelling on the same day costs you one session.'),
            style: TextStyle(fontSize: 12, color: sameDay ? const Color(0xFFFFC542) : const Color(0xFF9A9AA6)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: tr(ctx, 'Reason (required)')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Keep booking'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(tr(ctx, 'Cancel session')),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      final res = await ApiClient.instance.post('/api/bookings/${b['id']}/coach-cancel', {'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['penalty'] == true
              ? tr(context, 'Session cancelled — one session recorded against you.')
              : tr(context, 'Session cancelled.')),
        ));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _complete(Map b, {bool noShow = false}) async {
    if (noShow) {
      // (v0.7 item 2) Confirm — the member's class is still deducted.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'Record a no-show?')),
          content: Text(tr(ctx, "The member's class will still be deducted, and they cannot review this session.")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, 'Yes, no-show')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ApiClient.instance.post('/api/bookings/${b['id']}/complete', {'noShow': noShow});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          HeroPanel(title: tr(context, 'Requests'), icon: Icons.inbox),
          EmptyState(icon: Icons.inbox, message: tr(context, 'No requests yet.')),
        ]),
      );
    }
    return RefreshIndicator(onRefresh: _load, child: ListView(children: [
      HeroPanel(
        title: tr(context, 'Requests'),
        subtitle: '${bookings.length}',
        icon: Icons.inbox,
      ),
      ...bookings.asMap().entries.map<Widget>((entry) {
      final b = entry.value;
      final status = b['status'];
      final edge = status == 'pending' ? Brand.orange : const Color(0xFF3ED598);
      return FadeInUp(index: entry.key, child: BrandCard(accent: edge, child: ListTile(
        isThreeLine: status == 'accepted',
        leading: GradientAvatar(initials: '${b['member_first'][0]}${b['member_last'][0]}', size: 40),
        // (v0.9 item 2) Tap the member to see their fitness questionnaire.
        onTap: () => Navigator.push(context, fadeSlideRoute(
          CoachMemberDetail(
            memberId: '${b['member_id']}',
            memberName: '${b['member_first']} ${b['member_last']}',
          ),
        )),
        title: Text('${b['member_first']} ${b['member_last']}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtDate(context, DateTime.parse(b['start_at']).toLocal(), 'EEE d MMM, h:mm a')),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(children: [
              StatusPill(label: trStatus(context, status), color: edge),
              const SizedBox(width: 6),
              StatusPill(
                label: b['delivery'] == 'online' ? tr(context, 'Online') : tr(context, 'In-person'),
                color: Brand.magenta,
              ),
            ]),
          ),
          if (b['member_phone'] != null) Text('📞 ${b['member_phone']}'),
          if (b['member_location'] != null) Text('📍 ${b['member_location']}'),
          // (item 2) Zoom link is a tappable hyperlink now.
          if (b['zoom_join_url'] != null) LinkText(url: b['zoom_join_url'], label: tr(context, 'Join Zoom session')),
        ]),
        trailing: status == 'pending'
            ? Wrap(spacing: 4, children: [
                IconButton(icon: const Icon(Icons.check, color: Color(0xFF3ED598)), onPressed: () => _decide(b, true)),
                // (v0.10 item 2) 3 rejections per package; after that the coach
                // must accept or cancel with a reason.
                if ((int.tryParse('${b['pkg_rejects_used'] ?? 0}') ?? 0) < 3)
                  IconButton(icon: const Icon(Icons.close, color: Color(0xFFFF5470)), onPressed: () => _decide(b, false))
                else
                  IconButton(
                    tooltip: tr(context, 'Rejection limit reached — cancel instead'),
                    icon: const Icon(Icons.event_busy, color: Color(0xFFFF5470)),
                    onPressed: () => _coachCancel(b),
                  ),
              ])
            // (v0.7 item 2) Completion opens only after the session ends —
            // the server enforces it too, this just keeps the UI honest.
            : (DateTime.parse(b['end_at']).toLocal().isAfter(DateTime.now())
                // Session not over yet: the coach can still cancel it.
                ? Wrap(spacing: 2, children: [
                    Tooltip(
                      message: tr(context, 'Available after the session ends'),
                      child: const Icon(Icons.lock_clock, size: 20, color: Color(0xFF6E6E7A)),
                    ),
                    IconButton(
                      tooltip: tr(context, 'Cancel session'),
                      icon: const Icon(Icons.event_busy, size: 20),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _coachCancel(b),
                    ),
                  ])
                : Wrap(spacing: 4, children: [
                    FilledButton(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _complete(b),
                      child: Text(tr(context, 'Completed')),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _complete(b, noShow: true),
                      child: Text(tr(context, 'Did not show up')),
                    ),
                  ])),
      )));
    }),
    ]));
  }
}

// ---------------- Sessions ----------------
class _MySessionsTab extends StatefulWidget {
  const _MySessionsTab();
  @override
  State<_MySessionsTab> createState() => _MySessionsTabState();
}

class _MySessionsTabState extends State<_MySessionsTab> {
  List sessions = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      // (v0.6 item 3) Sessions tab = open bookable slots only. Booked
      // appointments live in the Requests tab with the member's details.
      sessions = await ApiClient.instance.get('/api/coaches/my-sessions?scope=open');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _remove(Map s) async {
    try {
      await ApiClient.instance.delete('/api/coaches/availability/${s['id']}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // (v0.6) Calendar-like reading: slots grouped under date headers.
  List<Widget> _groupedByDate() {
    final out = <Widget>[];
    String? currentDay;
    for (final s in sessions) {
      final local = DateTime.parse(s['start_at']).toLocal();
      final day = fmtDate(context, local, 'EEEE, d MMM');
      if (day != currentDay) {
        currentDay = day;
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ));
      }
      out.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          dense: true,
          leading: Icon(s['delivery'] == 'online' ? Icons.videocam : Icons.place, size: 20),
          title: Text(fmtDate(context, local, 'h:mm a')),
          subtitle: Text('1-on-1 · ${s['delivery'] == 'online' ? tr(context, "Online") : tr(context, "In-person")}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _remove(s)),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const SkeletonList()
          : error != null
              ? ErrorRetry(message: error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: sessions.isEmpty
                      ? ListView(children: [
                          HeroPanel(title: tr(context, 'Sessions'), icon: Icons.event_available),
                          EmptyState(
                            icon: Icons.event_busy,
                            message: tr(context, 'No open slots.\n\nSlots are generated automatically from your Availability — set your weekly hours in the Availability tab. Booked sessions appear under Requests.'),
                          ),
                        ])
                      : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                          HeroPanel(
                            title: tr(context, 'Sessions'),
                            subtitle: '${sessions.length}',
                            icon: Icons.event_available,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              tr(context, 'Your open bookable times, generated from your Availability. Booked sessions move to Requests. Delete a slot to make a one-off exception.'),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          ..._groupedByDate(),
                        ]),
                ),
    );
  }
}

// ---------------- Availability (v0.5 item 5) ----------------
// Weekly recurring schedule: per-day toggle + time ranges + one session
// duration. Matches the requested design; sessions generate automatically.

class _AvailabilityTab extends StatefulWidget {
  const _AvailabilityTab();
  @override
  State<_AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends State<_AvailabilityTab> {
  Map? data;
  bool loading = true;
  String? error;
  static const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  String _dayName(BuildContext c, int dow) => tr(c, _dayNames[dow]);
  static const _durations = [30, 45, 50, 60, 90];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = await ApiClient.instance.get('/api/coaches/availability');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  void _feedback(Map res) {
    final removed = int.tryParse('${res['removed'] ?? 0}') ?? 0;
    final kept = int.tryParse('${res['keptBooked'] ?? 0}') ?? 0;
    final generated = int.tryParse('${res['generated'] ?? 0}') ?? 0;
    final parts = <String>[];
    if (generated > 0) parts.add('$generated ${tr(context, 'sessions added')}');
    if (removed > 0) parts.add('$removed ${tr(context, 'unbooked sessions removed')}');
    if (kept > 0) parts.add('$kept ${tr(context, kept == 1 ? "booked session kept" : "booked sessions kept")}');
    if (parts.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    }
  }

  Future<void> _call(Future<dynamic> Function() fn) async {
    try {
      final res = await fn();
      if (res is Map) _feedback(res);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _fmt(String hhmm) {
    final h = int.parse(hhmm.substring(0, 2)), m = hhmm.substring(3, 5);
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $ampm';
  }

  Future<String?> _pickTime(String currentHHMM) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(currentHHMM.substring(0, 2)),
        minute: int.parse(currentHHMM.substring(3, 5)),
      ),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addRange(int dow) async {
    String start = '09:00', end = '12:00', delivery = 'online';
    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text('${tr(context, 'Add hours')} — ${_dayName(context, dow)}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () async { final v = await _pickTime(start); if (v != null) setS(() => start = v); },
            child: Text(_fmt(start)),
          )),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
          Expanded(child: OutlinedButton(
            onPressed: () async { final v = await _pickTime(end); if (v != null) setS(() => end = v); },
            child: Text(_fmt(end)),
          )),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'online', label: Text(tr(context, 'Online')), icon: const Icon(Icons.videocam)),
            ButtonSegment(value: 'in_person', label: Text(tr(context, 'In-person')), icon: const Icon(Icons.place)),
          ],
          selected: {delivery},
          onSelectionChanged: (s) => setS(() => delivery = s.first),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Cancel'))),
        FilledButton(onPressed: () async {
          Navigator.pop(ctx);
          await _call(() => ApiClient.instance.post('/api/coaches/availability/ranges',
              {'dow': dow, 'startTime': start, 'endTime': end, 'delivery': delivery}));
        }, child: Text(tr(context, 'Add'))),
      ],
    )));
  }

  Widget _rangeRow(Map r) {
    final start = r['start_time'].toString().substring(0, 5);
    final end = r['end_time'].toString().substring(0, 5);
    final online = r['delivery'] == 'online';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), visualDensity: VisualDensity.compact),
          onPressed: () async {
            final v = await _pickTime(start);
            if (v != null) {
              await _call(() => ApiClient.instance.put('/api/coaches/availability/ranges/${r['id']}', {'startTime': v}));
            }
          },
          child: Text(_fmt(start)),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), visualDensity: VisualDensity.compact),
          onPressed: () async {
            final v = await _pickTime(end);
            if (v != null) {
              await _call(() => ApiClient.instance.put('/api/coaches/availability/ranges/${r['id']}', {'endTime': v}));
            }
          },
          child: Text(_fmt(end)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: Icon(online ? Icons.videocam : Icons.place, size: 16),
              label: Text(online ? tr(context, 'Online') : tr(context, 'In-person'), style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _call(() => ApiClient.instance.put(
                  '/api/coaches/availability/ranges/${r['id']}', {'delivery': online ? 'in_person' : 'online'})),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _call(() => ApiClient.instance.delete('/api/coaches/availability/ranges/${r['id']}')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final minutes = data!['sessionMinutes'] as int;
    final days = data!['days'] as List;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
        HeroPanel(title: tr(context, 'Availability'), icon: Icons.edit_calendar),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const GradientIconBadge(icon: Icons.timer_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(context, 'Session duration'), style: const TextStyle(fontWeight: FontWeight.w700))),
              DropdownButton<int>(
                value: _durations.contains(minutes) ? minutes : 50,
                items: _durations.map((d) => DropdownMenuItem(value: d, child: Text('$d ${tr(context, 'min')}'))).toList(),
                onChanged: (v) {
                  if (v != null && v != minutes) {
                    _call(() => ApiClient.instance.put('/api/coaches/availability/settings', {'sessionMinutes': v}));
                  }
                },
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            tr(context, 'Members book sessions generated from your weekly hours. Changes remove only unbooked future sessions — booked ones are always kept.'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        ...days.map<Widget>((d) {
          final enabled = d['enabled'] == true;
          final ranges = (d['ranges'] as List?) ?? [];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_dayName(context, d['dow']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                  Switch(
                    value: enabled,
                    onChanged: (v) => _call(() => ApiClient.instance.put(
                        '/api/coaches/availability/days/${d['dow']}', {'enabled': v})),
                  ),
                ]),
                if (enabled) ...[
                  if (ranges.isEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 4),
                        child: Text(tr(context, 'No hours yet — add a time range.'), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                  ...ranges.map<Widget>((r) => _rangeRow(r)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addRange(d['dow']),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr(context, 'Add more')),
                    ),
                  ),
                ] else if (ranges.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${ranges.length} ${tr(context, ranges.length == 1 ? "saved range" : "saved ranges")} (${tr(context, 'day off')})',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}

// ---------------- Clients (v0.4 items 4, 10) ----------------
class _ClientsTab extends StatefulWidget {
  const _ClientsTab();
  @override
  State<_ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<_ClientsTab> {
  bool showCompleted = false;
  List rows = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      rows = await ApiClient.instance.get('/api/coaches/clients');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, h:mm a');
    final visible = rows.where((r) => (r['is_completed'] == true) == showCompleted).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr(context, 'Active'))),
            ButtonSegment(value: true, label: Text(tr(context, 'Completed'))),
          ],
          selected: {showCompleted},
          onSelectionChanged: (s) => setState(() => showCompleted = s.first),
        ),
      ),
      Expanded(
        child: loading
            ? const SkeletonList()
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: visible.isEmpty
                        ? ListView(children: [
                            Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                    showCompleted
                                        ? 'No completed packages yet.'
                                        : 'No active clients yet.\n\nMembers appear here once their package with you is activated.',
                                    textAlign: TextAlign.center)),
                          ])
                        : ListView(padding: const EdgeInsets.only(bottom: 24), children: visible.map<Widget>((r) {
                            final used = r['classes_consumed'];
                            final total = r['classes_total'];
                            return BrandCard(
                              accent: r['is_completed'] == true ? const Color(0xFF6E6E7A) : const Color(0xFF3ED598),
                              onTap: () => Navigator.push(context, fadeSlideRoute(
                                CoachMemberDetail(
                                  memberId: '${r['member_id']}',
                                  memberName: '${r['first_name']} ${r['last_name']}',
                                ),
                              )),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    GradientAvatar(
                                      initials: '${(r['first_name'] ?? '?').toString()[0]}${(r['last_name'] ?? '?').toString()[0]}',
                                      size: 38),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('${r['first_name']} ${r['last_name']}',
                                            style: Theme.of(context).textTheme.titleSmall),
                                        Text('${r['package_name']}${r['is_single'] == true ? ' (trial)' : ''}',
                                            style: Theme.of(context).textTheme.bodySmall),
                                      ]),
                                    ),
                                    Chip(
                                      label: Text('$used / $total used'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: (r['is_completed'] == true ? Colors.grey : Colors.green).withValues(alpha: 0.15),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text('📞 ${r['phone']}  ·  ✉️ ${r['email']}'),
                                  if (r['location'] != null) Text('📍 ${r['location']}'),
                                  if (r['expires_at'] != null)
                                    Text('Expires: ${DateFormat('d MMM yyyy').format(DateTime.parse(r['expires_at']).toLocal())}',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  if (r['next_session'] != null)
                                    Text('Next session: ${df.format(DateTime.parse(r['next_session']).toLocal())}'),
                                  if (r['next_session'] == null && r['last_session'] != null)
                                    Text('Last session: ${df.format(DateTime.parse(r['last_session']).toLocal())}'),
                                ]),
                              ),
                            );
                          }).toList()),
                  ),
      ),
    ]);
  }
}

// ---------------- Dashboard (v0.4 item 9 — activity only) ----------------
class _DashboardTab extends StatefulWidget {
  const _DashboardTab();
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  int days = 30;
  Map? data;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = Map<String, dynamic>.from(await ApiClient.instance.get('/api/coaches/dashboard?days=$days'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final d = data!;
    final weekly = ((d['weeklyCompleted'] as List?) ?? [])
        .map((w) => MapEntry('${w['week']}', (w['completed'] as num?) ?? 0))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
        HeroPanel(
          title: tr(context, 'Dashboard'),
          icon: Icons.insights,
          child: Row(children: [
            HeroStat(value: '${d['completed']}', label: tr(context, 'Completed'), animate: true),
            const SizedBox(width: 10),
            HeroStat(value: '${d['activeClients']}', label: tr(context, 'Clients'), animate: true),
            const SizedBox(width: 10),
            HeroStat(value: '⭐ ${d['avgRating']}', label: tr(context, 'Rating')),
          ]),
        ),
        Center(child: RangePicker(days: days, onChanged: (v) { setState(() => days = v); _load(); })),
        const SizedBox(height: 12),
        StatGrid(cards: [
          StatCard(label: 'Upcoming sessions', value: '${d['upcomingSessions']}', icon: Icons.event, color: Brand.magenta),
          StatCard(label: 'Pending requests', value: '${d['pendingRequests']}', icon: Icons.inbox, color: Brand.orange),
          StatCard(label: 'Completed (last ${d['days']}d)', value: '${d['completed']}', icon: Icons.check_circle, color: const Color(0xFF3ED598)),
          StatCard(label: 'Active clients', value: '${d['activeClients']}', icon: Icons.groups, color: Brand.magenta),
          StatCard(
              label: 'Completion rate',
              value: d['completionRate'] == null ? '—' : '${d['completionRate']}%',
              icon: Icons.trending_up, color: Brand.orange),
          StatCard(label: 'Rating', value: '⭐ ${d['avgRating']} (${d['ratingCount']})', icon: Icons.star, color: const Color(0xFFFFC542)),
          // (v0.10) Sessions owed from same-day cancellations.
          StatCard(
            label: tr(context, 'Sessions owed'),
            value: '${d['penaltySessions'] ?? 0}',
            icon: Icons.gavel,
            color: (int.tryParse('${d['penaltySessions'] ?? 0}') ?? 0) > 0
                ? const Color(0xFFFF5470) : const Color(0xFF6E6E7A),
          ),
        ]),
        const SizedBox(height: 8),
        SimpleBarChart(title: 'Completed sessions per week', data: weekly),
        const SizedBox(height: 4),
        Text('Cancelled: ${d['cancelled']} · Rejected: ${d['rejected']} in the last ${d['days']} days',
            style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 24),
      ]),
    );
  }
}
