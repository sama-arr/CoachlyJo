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
import 'complete_profile_v0_13.dart';
import 'app_drawer_v0_13.dart';
import '../core/gym_art_v0_13.dart';
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
  // (v0.14 items 2, 3) A coach completes their profile, then waits for an
  // admin. Until approved, only Home and Complete Profile are reachable.
  bool? _profileComplete;
  String _approval = 'pending';
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final st = await ApiClient.instance.get('/api/profile/status');
      if (mounted) {
        setState(() {
          _profileComplete = st['complete'] == true;
          _approval = '${st['approvalStatus'] ?? 'pending'}';
          _rejectionReason = st['rejectionReason'];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _profileComplete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsProfile = _profileComplete == false;
    final approved = _approval == 'approved';

    // Pages a coach can reach before approval.
    final pages = <Widget>[
      const HomeScreen(audience: 'coach'),
      if (needsProfile)
        CompleteProfileScreen(
            role: 'coach',
            onCompleted: () {
              setState(() {
                _profileComplete = true;
                _tab = 0;
              });
              _checkProfile();
            }),
      if (approved) const _RequestsTab(),
      if (approved) const _MySessionsTab(),
      if (approved) const _AvailabilityTab(),
      if (approved) const _ClientsTab(),
      if (approved) const _DashboardTab(),
    ];
    final titles = <String>[
      tr(context, 'Home'),
      if (needsProfile) tr(context, 'Complete profile'),
      if (approved) tr(context, 'Requests'),
      if (approved) tr(context, 'Sessions'),
      if (approved) tr(context, 'Availability'),
      if (approved) tr(context, 'Clients'),
      if (approved) tr(context, 'Dashboard'),
    ];
    final tab = _tab.clamp(0, pages.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: const [NotificationBell()],
      ),
      // (v0.14 item 21) Hamburger opens the slide-out drawer.
      drawer: const AppDrawer(role: 'coach'),
      body: GlowBackground(
        child: Column(children: [
          // (v0.14 item 3) Permanent, unmissable status banner until approved.
          if (!approved)
            _ApprovalBanner(
              status: _approval,
              reason: _rejectionReason,
              profileComplete: _profileComplete == true,
            ),
          Expanded(child: pages[tab]),
        ]),
      ),
      bottomNavigationBar: (!needsProfile && !approved)
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  tooltip: tr(context, 'Home'),
                  label: tr(context, 'Home'),
                ),
                if (needsProfile)
                  NavigationDestination(
                    icon: Badge(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      smallSize: 8,
                      child: const Icon(Icons.assignment_ind_outlined),
                    ),
                    selectedIcon: const Icon(Icons.assignment_ind),
                    tooltip: tr(context, 'Complete profile'),
                    label: tr(context, 'Profile'),
                  ),
                if (approved) ...[
                  NavigationDestination(
                    icon: const Icon(Icons.inbox),
                    tooltip: tr(context, 'Requests'),
                    label: tr(context, 'Requests'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.event_available),
                    tooltip: tr(context, 'Sessions'),
                    label: tr(context, 'Sessions'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.edit_calendar),
                    tooltip: tr(context, 'Availability'),
                    label: tr(context, 'Availability'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.groups),
                    tooltip: tr(context, 'Clients'),
                    label: tr(context, 'Clients'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.insights),
                    tooltip: tr(context, 'Dashboard'),
                    label: tr(context, 'Dashboard'),
                  ),
                ],
              ],
            ),
    );
  }
}

/// (v0.14 item 3) Tells the coach exactly where they stand, and what to do
/// next, instead of leaving empty tabs that silently fail.
class _ApprovalBanner extends StatelessWidget {
  final String status;
  final String? reason;
  final bool profileComplete;
  const _ApprovalBanner(
      {required this.status, this.reason, required this.profileComplete});

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    final scheme = Theme.of(context).colorScheme;
    final color = rejected ? scheme.error : Brand.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(rejected ? Icons.cancel_outlined : Icons.hourglass_top,
            color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              rejected
                  ? tr(context, 'Your application was not approved')
                  : tr(context, 'Awaiting admin approval'),
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              rejected
                  ? (reason ?? tr(context, 'Please contact CoachlyJo support.'))
                  : profileComplete
                      ? tr(context,
                          'Your documents are with our team. You can set your availability as soon as you are approved.')
                      : tr(context,
                          'Complete your profile and upload your certificates so an admin can review you.'),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ]),
        ),
      ]),
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
      final all = await ApiClient.instance.get('/api/coaches/bookings');
      // (item 4) Only actionable items live here: pending decisions and accepted
      // upcoming sessions. Finished history is under Clients > Completed.
      bookings = (all as List)
          .where((b) => b['status'] == 'pending' || b['status'] == 'accepted')
          .toList();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  Future<void> _decide(Map b, bool accept) async {
    final c = AppColors.of(context);
    String? reason;
    if (!accept) {
      final c = TextEditingController();
      reason = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Rejection reason'),
                content: TextField(
                    controller: c,
                    decoration: const InputDecoration(hintText: 'Required')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, c.text),
                      child: const Text('Reject')),
                ],
              ));
      if (reason == null || reason.trim().isEmpty) return;
    }
    try {
      await ApiClient.instance.post('/api/bookings/${b['id']}/decision',
          {'accept': accept, 'rejectionReason': reason});
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // (v0.10 item 2) Coach cancels a session. The member always keeps their
  // class; cancelling on the same day costs the coach one session (recorded
  // for the admin to settle).
  /// (v0.15 bug 4) Ask the server to create the Zoom meeting again — used
  /// after a configuration fix, so nobody has to cancel and rebook.
  Future<void> _retryLink(Map b) async {
    try {
      await ApiClient.instance.post('/api/bookings/${b['id']}/retry-meeting-link');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'Meeting link created.'))));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Paste a personal Zoom / Google Meet link instead.
  Future<void> _addOwnLink(Map b) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Add a meeting link')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(ctx, 'Paste your Zoom or Google Meet link. The member is notified straight away.'),
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://…'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr(ctx, 'Save')),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      await ApiClient.instance.put('/api/bookings/${b['id']}/meeting-link', {'joinUrl': url});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'Link saved and the member was notified.'))));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _coachCancel(Map b) async {
    final c = AppColors.of(context);
    final start = DateTime.tryParse(b['start_at'] ?? '')?.toLocal();
    final now = DateTime.now();
    final sameDay = start != null &&
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Cancel session')),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sameDay
                    ? tr(ctx,
                        'This session is today. Cancelling now costs you one session, recorded for the admin.')
                    : tr(ctx,
                        'The member keeps their class. Cancelling on the same day costs you one session.'),
                style: TextStyle(
                    fontSize: 12,
                    color: sameDay
                        ? c.warning
                        : c.muted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration:
                    InputDecoration(labelText: tr(ctx, 'Reason (required)')),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(ctx, 'Keep booking'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
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
      final res = await ApiClient.instance
          .post('/api/bookings/${b['id']}/coach-cancel', {'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['penalty'] == true
              ? tr(context,
                  'Session cancelled — one session recorded against you.')
              : tr(context, 'Session cancelled.')),
        ));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _complete(Map b, {bool noShow = false}) async {
    if (noShow) {
      // (v0.7 item 2) Confirm — the member's class is still deducted.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'Record a no-show?')),
          content: Text(tr(ctx,
              "The member's class will still be deducted, and they cannot review this session.")),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr(ctx, 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, 'Yes, no-show')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ApiClient.instance
          .post('/api/bookings/${b['id']}/complete', {'noShow': noShow});
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          HeroPanel(title: tr(context, 'Requests'), icon: Icons.inbox),
          EmptyState(
              icon: Icons.inbox, message: tr(context, 'No requests yet.')),
        ]),
      );
    }
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          HeroPanel(
            title: tr(context, 'Requests'),
            subtitle: '${bookings.length}',
            icon: Icons.inbox,
          ),
          ...bookings.asMap().entries.map<Widget>((entry) {
            final b = entry.value;
            final status = b['status'];
            final edge =
                status == 'pending' ? Brand.orange : c.success;
            return FadeInUp(
                index: entry.key,
                child: BrandCard(
                    accent: edge,
                    child: ListTile(
                      isThreeLine: status == 'accepted',
                      leading: GradientAvatar(
                          initials:
                              '${b['member_first'][0]}${b['member_last'][0]}',
                          size: 40),
                      // (v0.9 item 2) Tap the member to see their fitness questionnaire.
                      onTap: () => Navigator.push(
                          context,
                          fadeSlideRoute(
                            CoachMemberDetail(
                              memberId: '${b['member_id']}',
                              memberName:
                                  '${b['member_first']} ${b['member_last']}',
                            ),
                          )),
                      title: Text('${b['member_first']} ${b['member_last']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fmtDate(
                                context,
                                DateTime.parse(b['start_at']).toLocal(),
                                'EEE d MMM, h:mm a')),
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 2),
                              child: Row(children: [
                                StatusPill(
                                    label: trStatus(context, status),
                                    color: edge),
                                const SizedBox(width: 6),
                                StatusPill(
                                  label: b['delivery'] == 'online'
                                      ? tr(context, 'Online')
                                      : tr(context, 'In-person'),
                                  color: Brand.magenta,
                                ),
                              ]),
                            ),
                            if (b['member_phone'] != null)
                              Text('📞 ${b['member_phone']}'),
                            if (b['member_location'] != null)
                              Text('📍 ${b['member_location']}'),
                            // (item 2) Zoom link is a tappable hyperlink now.
                            if (b['zoom_join_url'] != null)
                              LinkText(
                                  url: b['zoom_join_url'],
                                  label: tr(context, 'Join Zoom session')),
                            // (v0.15 bug 4) Confirmed online session with no
                            // link yet: retry creation, or paste your own.
                            if (b['link_pending'] == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 10, children: [
                                  Text(tr(context, 'No meeting link yet'),
                                      style: TextStyle(fontSize: 11, color: c.warning)),
                                  InkWell(
                                    onTap: () => _retryLink(b),
                                    child: Text(tr(context, 'Retry'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context).colorScheme.primary)),
                                  ),
                                  InkWell(
                                    onTap: () => _addOwnLink(b),
                                    child: Text(tr(context, 'Add my link'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context).colorScheme.primary)),
                                  ),
                                ]),
                              ),
                          ]),
                      trailing: status == 'pending'
                          ? Wrap(spacing: 4, children: [
                              IconButton(
                                  icon: Icon(Icons.check,
                                      color: c.success),
                                  onPressed: () => _decide(b, true)),
                              // (v0.10 item 2) 3 rejections per package; after that the coach
                              // must accept or cancel with a reason.
                              if ((int.tryParse(
                                          '${b['pkg_rejects_used'] ?? 0}') ??
                                      0) <
                                  3)
                                IconButton(
                                    icon: Icon(Icons.close,
                                        color: c.danger),
                                    onPressed: () => _decide(b, false))
                              else
                                IconButton(
                                  tooltip: tr(context,
                                      'Rejection limit reached — cancel instead'),
                                  icon: Icon(Icons.event_busy,
                                      color: c.danger),
                                  onPressed: () => _coachCancel(b),
                                ),
                            ])
                          // (v0.7 item 2) Completion opens only after the session ends —
                          // the server enforces it too, this just keeps the UI honest.
                          : (DateTime.parse(b['end_at'])
                                  .toLocal()
                                  .isAfter(DateTime.now())
                              // Session not over yet: the coach can still cancel it.
                              ? Wrap(spacing: 2, children: [
                                  Tooltip(
                                    message: tr(context,
                                        'Available after the session ends'),
                                    child: Icon(Icons.lock_clock,
                                        size: 20, color: c.faint),
                                  ),
                                  IconButton(
                                    tooltip: tr(context, 'Cancel session'),
                                    icon:
                                        const Icon(Icons.event_busy, size: 20),
                                    color: Theme.of(context).colorScheme.error,
                                    onPressed: () => _coachCancel(b),
                                  ),
                                ])
                              : Wrap(spacing: 4, children: [
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact),
                                    onPressed: () => _complete(b),
                                    child: Text(tr(context, 'Completed')),
                                  ),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor:
                                          Theme.of(context).colorScheme.error,
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
      // (v0.6 item 3) Sessions tab = open bookable slots only. Booked
      // appointments live in the Requests tab with the member's details.
      sessions =
          await ApiClient.instance.get('/api/coaches/my-sessions?scope=open');
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  Future<void> _remove(Map s) async {
    try {
      await ApiClient.instance.delete('/api/coaches/availability/${s['id']}');
      _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
          child: Text(day,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ));
      }
      out.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          dense: true,
          leading: Icon(
              s['delivery'] == 'online' ? Icons.videocam : Icons.place,
              size: 20),
          title: Text(fmtDate(context, local, 'h:mm a')),
          subtitle: Text(
              '1-on-1 · ${s['delivery'] == 'online' ? tr(context, "Online") : tr(context, "In-person")}'),
          trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _remove(s)),
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
                          HeroPanel(
                              title: tr(context, 'Sessions'),
                              icon: Icons.event_available),
                          EmptyState(
                            icon: Icons.event_busy,
                            message: tr(context,
                                'No open slots.\n\nSlots are generated automatically from your Availability — set your weekly hours in the Availability tab. Booked sessions appear under Requests.'),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                              HeroPanel(
                                title: tr(context, 'Sessions'),
                                subtitle: '${sessions.length}',
                                icon: Icons.event_available,
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  tr(context,
                                      'Your open bookable times, generated from your Availability. Booked sessions move to Requests. Delete a slot to make a one-off exception.'),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
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

// ---------------- Availability: a weekly calendar (v0.14 item 16) ----------
//
// Coaches set hours against REAL DATES, one week at a time, laid out like a
// spreadsheet: days across the top, hours down the side. Tap a cell to open or
// close that hour; drag down the column to paint a block. "Copy last week"
// exists because most weeks repeat.
//
// Booked hours are locked — they show with a lock and cannot be cleared, which
// is why the week view returns generated sessions alongside the blocks.

class _AvailabilityTab extends StatefulWidget {
  const _AvailabilityTab();
  @override
  State<_AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends State<_AvailabilityTab> {
  Map? data;
  bool loading = true, busy = false;
  String? error;
  late DateTime weekStart;

  /// Hour rows shown in the grid. 6am–11pm covers every realistic session.
  static const int firstHour = 6;
  static const int lastHour = 23;

  @override
  void initState() {
    super.initState();
    weekStart = _mondayOf(DateTime.now());
    _load();
  }

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: (day.weekday - 1) % 7));
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = Map<String, dynamic>.from(await ApiClient.instance
          .get('/api/coaches/availability/week?start=${_iso(weekStart)}'));
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    if (mounted) setState(() => loading = false);
  }

  void _feedback(Map res) {
    final removed = int.tryParse('${res['removed'] ?? 0}') ?? 0;
    final kept = int.tryParse('${res['keptBooked'] ?? 0}') ?? 0;
    final parts = <String>[];
    if (removed > 0)
      parts.add('$removed ${tr(context, 'unbooked sessions removed')}');
    if (kept > 0)
      parts.add(
          '$kept ${tr(context, kept == 1 ? 'booked session kept' : 'booked sessions kept')}');
    if (parts.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    }
  }

  Future<void> _call(Future<dynamic> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final res = await fn();
      if (res is Map) _feedback(res);
      await _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---- data helpers ---------------------------------------------------------

  List get _days => (data?['days'] as List?) ?? [];
  List get _sessions => (data?['sessions'] as List?) ?? [];
  int get _sessionMinutes => (data?['sessionMinutes'] as int?) ?? 50;

  /// The availability block covering this date+hour, if any.
  Map? _blockAt(Map day, int hour) {
    for (final b in (day['blocks'] as List? ?? [])) {
      final s = int.parse('${b['start_time']}'.substring(0, 2));
      final e = int.parse('${b['end_time']}'.substring(0, 2));
      final eMin = int.parse('${b['end_time']}'.substring(3, 5));
      if (hour >= s && (hour < e || (hour == e && eMin > 0))) return b;
    }
    return null;
  }

  /// True when a generated session in this hour already has a booking.
  bool _isBooked(String date, int hour) {
    for (final s in _sessions) {
      if (Number(s['booked']) == 0) continue;
      final local = DateTime.parse('${s['start_at']}').toLocal();
      if (_iso(local) == date && local.hour == hour) return true;
    }
    return false;
  }

  // ignore: non_constant_identifier_names
  int Number(dynamic v) => int.tryParse('$v') ?? 0;

  // ---- actions --------------------------------------------------------------

  /// Tapping an empty cell opens that hour; tapping a filled one closes it.
  Future<void> _toggleCell(Map day, int hour) async {
    final date = '${day['date']}';
    if (day['isPast'] == true) return;
    final block = _blockAt(day, hour);

    if (block == null) {
      await _call(
          () => ApiClient.instance.post('/api/coaches/availability/day', {
                'date': date,
                'startTime': '${hour.toString().padLeft(2, '0')}:00',
                'endTime': '${(hour + 1).toString().padLeft(2, '0')}:00',
                'delivery': 'online',
              }));
      return;
    }

    if (_isBooked(date, hour)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              'That hour has a booked session and cannot be removed.'))));
      return;
    }

    final s = int.parse('${block['start_time']}'.substring(0, 2));
    final e = int.parse('${block['end_time']}'.substring(0, 2));

    // Removing the only hour deletes the block; removing an edge shrinks it;
    // removing the middle is refused rather than silently splitting the day.
    if (e - s <= 1) {
      await _call(() => ApiClient.instance
          .delete('/api/coaches/availability/day/${block['id']}'));
    } else if (hour == s) {
      await _call(() => ApiClient.instance.put(
          '/api/coaches/availability/day/${block['id']}',
          {'startTime': '${(s + 1).toString().padLeft(2, '0')}:00'}));
    } else if (hour == e - 1) {
      await _call(() => ApiClient.instance.put(
          '/api/coaches/availability/day/${block['id']}',
          {'endTime': '${hour.toString().padLeft(2, '0')}:00'}));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(
              context, 'Remove hours from the start or the end of a block.'))));
    }
  }

  /// Long-press a block to switch it between online and in-person.
  Future<void> _toggleDelivery(Map block) async {
    final online = block['delivery'] == 'online';
    await _call(() => ApiClient.instance.put(
        '/api/coaches/availability/day/${block['id']}',
        {'delivery': online ? 'in_person' : 'online'}));
  }

  Future<void> _addRange(Map day) async {
    TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 21, minute: 0);
    String delivery = 'online';
    final date = '${day['date']}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                title: Text('${tr(ctx, 'Add hours')} — $date'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: start);
                        if (t != null) setS(() => start = t);
                      },
                      child: Text(start.format(ctx)),
                    )),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('–')),
                    Expanded(
                        child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: end);
                        if (t != null) setS(() => end = t);
                      },
                      child: Text(end.format(ctx)),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: 'online',
                          label: Text(tr(ctx, 'Online')),
                          icon: const Icon(Icons.videocam, size: 16)),
                      ButtonSegment(
                          value: 'in_person',
                          label: Text(tr(ctx, 'In-person')),
                          icon: const Icon(Icons.place, size: 16)),
                    ],
                    selected: {delivery},
                    onSelectionChanged: (v) => setS(() => delivery = v.first),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr(ctx, 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(tr(ctx, 'Add'))),
                ],
              )),
    );
    if (ok != true) return;
    String hhmm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    await _call(() => ApiClient.instance.post('/api/coaches/availability/day', {
          'date': date,
          'startTime': hhmm(start),
          'endTime': hhmm(end),
          'delivery': delivery
        }));
  }

  Future<void> _copyLastWeek() => _call(() => ApiClient.instance.post(
      '/api/coaches/availability/copy-week', {'targetWeek': _iso(weekStart)}));

  Future<void> _clearWeek() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Clear this week?')),
        content: Text(tr(ctx,
            'All open hours this week are removed. Booked sessions are kept.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Clear week')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _call(() => ApiClient.instance
        .delete('/api/coaches/availability/week?start=${_iso(weekStart)}'));
  }

  Future<void> _setDuration() async {
    final current = _sessionMinutes;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(ctx, 'Session duration')),
        children: [30, 45, 50, 60, 90]
            .map((m) => RadioListTile<int>(
                  value: m,
                  groupValue: current,
                  title: Text('$m ${tr(ctx, 'min')}'),
                  onChanged: (v) => Navigator.pop(ctx, v),
                ))
            .toList(),
      ),
    );
    if (picked == null || picked == current) return;
    await _call(() => ApiClient.instance
        .put('/api/coaches/availability/settings', {'sessionMinutes': picked}));
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (loading) return const SkeletonList(count: 4);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);

    final light = Theme.of(context).brightness == Brightness.light;
    final dayFmt = DateFormat('EEE');
    final dayNumFmt = DateFormat('d');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        // ---- week switcher ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: tr(context, 'Previous week'),
              onPressed: busy
                  ? null
                  : () {
                      setState(() => weekStart =
                          weekStart.subtract(const Duration(days: 7)));
                      _load();
                    },
            ),
            Expanded(
              child: Column(children: [
                Text(
                  '${DateFormat('d MMM').format(weekStart)} – '
                  '${DateFormat('d MMM').format(weekStart.add(const Duration(days: 6)))}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
                Text(tr(context, 'Tap an hour to open or close it'),
                    style: TextStyle(
                        fontSize: 11, color: c.muted)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: tr(context, 'Next week'),
              onPressed: busy
                  ? null
                  : () {
                      setState(() =>
                          weekStart = weekStart.add(const Duration(days: 7)));
                      _load();
                    },
            ),
          ]),
        ),

        // ---- actions ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.timer_outlined, size: 16),
              label: Text('$_sessionMinutes ${tr(context, 'min')}'),
              onPressed: busy ? null : _setDuration,
            ),
            ActionChip(
              avatar: const Icon(Icons.copy_all, size: 16),
              label: Text(tr(context, 'Copy last week')),
              onPressed: busy ? null : _copyLastWeek,
            ),
            ActionChip(
              avatar: const Icon(Icons.clear_all, size: 16),
              label: Text(tr(context, 'Clear week')),
              onPressed: busy ? null : _clearWeek,
            ),
          ]),
        ),

        const SizedBox(height: 10),

        // ---- the grid ----
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Column(children: [
              // header row: day names
              Row(children: [
                const SizedBox(width: 38),
                ..._days.map((d) {
                  final date = DateTime.parse('${d['date']}');
                  final isToday = _iso(date) == _iso(DateTime.now());
                  return Expanded(
                    child: Column(children: [
                      Text(dayFmt.format(date),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: d['isPast'] == true
                                  ? c.faint
                                  : Theme.of(context).colorScheme.onSurface)),
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: isToday
                            ? BoxDecoration(
                                gradient: Brand.gradientFor(
                                    light ? Brightness.light : Brightness.dark),
                                shape: BoxShape.circle)
                            : null,
                        child: Text(dayNumFmt.format(date),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isToday
                                    ? Colors.white
                                    : (d['isPast'] == true
                                        ? c.faint
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface))),
                      ),
                    ]),
                  );
                }),
              ]),
              const SizedBox(height: 6),
              // hour rows
              ...List.generate(lastHour - firstHour + 1, (i) {
                final hour = firstHour + i;
                return Row(children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                          fontSize: 9, color: c.muted),
                    ),
                  ),
                  ..._days.map((d) => Expanded(child: _cell(d, hour, light))),
                ]);
              }),
            ]),
          ),
        ),

        // ---- legend + per-day "add hours" ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            _legend(Brand.magenta, tr(context, 'Online')),
            _legend(Brand.orange, tr(context, 'In-person')),
            _legend(c.success, tr(context, 'Booked')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text(
            tr(context,
                'Long-press a block to switch it between online and in-person. Booked hours are locked.'),
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ),
        const SizedBox(height: 8),
        ..._days.where((d) => d['isPast'] != true).map((d) => ListTile(
              dense: true,
              leading: const Icon(Icons.add_circle_outline, size: 20),
              title: Text(
                '${tr(context, 'Add hours')} — ${DateFormat('EEEE d MMM').format(DateTime.parse('${d['date']}'))}',
                style: const TextStyle(fontSize: 13),
              ),
              onTap: busy ? null : () => _addRange(d),
            )),
      ]),
    );
  }

  Widget _legend(Color c, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _cell(Map day, int hour, bool light) {
    final c = AppColors.of(context);
    final date = '${day['date']}';
    final past = day['isPast'] == true;
    final block = _blockAt(day, hour);
    final booked = block != null && _isBooked(date, hour);
    final online = block?['delivery'] == 'online';

    Color bg;
    if (past) {
      bg = light ? const Color(0xFFF1EFF4) : const Color(0xFF121218);
    } else if (booked) {
      bg = c.success.withValues(alpha: light ? 0.30 : 0.38);
    } else if (block != null) {
      bg = (online ? Brand.magenta : Brand.orange)
          .withValues(alpha: light ? 0.28 : 0.42);
    } else {
      bg = light ? const Color(0xFFFAF9FC) : const Color(0xFF17171E);
    }

    return GestureDetector(
      onTap: past || busy ? null : () => _toggleCell(day, hour),
      onLongPress:
          (block == null || past || busy) ? null : () => _toggleDelivery(block),
      child: Container(
        height: 22,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: light ? const Color(0xFFE6E3EC) : c.border,
            width: 0.5,
          ),
        ),
        child: booked
            ? Icon(Icons.lock, size: 10, color: c.success)
            : null,
      ),
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
      rows = await ApiClient.instance.get('/api/coaches/clients');
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final df = DateFormat('d MMM, h:mm a');
    final visible = rows
        .where((r) => (r['is_completed'] == true) == showCompleted)
        .toList();
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
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: visible.map<Widget>((r) {
                              final used = r['classes_consumed'];
                              final total = r['classes_total'];
                              return BrandCard(
                                accent: r['is_completed'] == true
                                    ? c.faint
                                    : c.success,
                                onTap: () => Navigator.push(
                                    context,
                                    fadeSlideRoute(
                                      CoachMemberDetail(
                                        memberId: '${r['member_id']}',
                                        memberName:
                                            '${r['first_name']} ${r['last_name']}',
                                      ),
                                    )),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          GradientAvatar(
                                              initials:
                                                  '${(r['first_name'] ?? '?').toString()[0]}${(r['last_name'] ?? '?').toString()[0]}',
                                              size: 38),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      '${r['first_name']} ${r['last_name']}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall),
                                                  Text(
                                                      '${r['package_name']}${r['is_single'] == true ? ' (trial)' : ''}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                                ]),
                                          ),
                                          Chip(
                                            label: Text('$used / $total used'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor:
                                                (r['is_completed'] == true
                                                        ? Colors.grey
                                                        : Colors.green)
                                                    .withValues(alpha: 0.15),
                                          ),
                                        ]),
                                        const SizedBox(height: 8),
                                        Text(
                                            '📞 ${r['phone']}  ·  ✉️ ${r['email']}'),
                                        if (r['location'] != null)
                                          Text('📍 ${r['location']}'),
                                        if (r['expires_at'] != null)
                                          Text(
                                              'Expires: ${DateFormat('d MMM yyyy').format(DateTime.parse(r['expires_at']).toLocal())}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        if (r['next_session'] != null)
                                          Text(
                                              'Next session: ${df.format(DateTime.parse(r['next_session']).toLocal())}'),
                                        if (r['next_session'] == null &&
                                            r['last_session'] != null)
                                          Text(
                                              'Last session: ${df.format(DateTime.parse(r['last_session']).toLocal())}'),
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
      data = Map<String, dynamic>.from(
          await ApiClient.instance.get('/api/coaches/dashboard?days=$days'));
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
            HeroStat(
                value: '${d['completed']}',
                label: tr(context, 'Completed'),
                animate: true),
            const SizedBox(width: 10),
            HeroStat(
                value: '${d['activeClients']}',
                label: tr(context, 'Clients'),
                animate: true),
            const SizedBox(width: 10),
            HeroStat(
                value: '⭐ ${d['avgRating']}', label: tr(context, 'Rating')),
          ]),
        ),
        Center(
            child: RangePicker(
                days: days,
                onChanged: (v) {
                  setState(() => days = v);
                  _load();
                })),
        const SizedBox(height: 12),
        StatGrid(cards: [
          // (v0.14 item 17) "Upcoming" counts BOOKED sessions only — open
          // slots are availability, not appointments.
          StatCard(
              label: tr(context, 'Upcoming sessions'),
              value: '${d['upcomingBooked'] ?? d['upcomingSessions']}',
              icon: Icons.event,
              color: Brand.magenta),
          StatCard(
              label: 'Pending requests',
              value: '${d['pendingRequests']}',
              icon: Icons.inbox,
              color: Brand.orange),
          StatCard(
              label: 'Completed (last ${d['days']}d)',
              value: '${d['completed']}',
              icon: Icons.check_circle,
              color: c.success),
          StatCard(
              label: 'Active clients',
              value: '${d['activeClients']}',
              icon: Icons.groups,
              color: Brand.magenta),
          StatCard(
              label: 'Completion rate',
              value:
                  d['completionRate'] == null ? '—' : '${d['completionRate']}%',
              icon: Icons.trending_up,
              color: Brand.orange),
          StatCard(
              label: 'Rating',
              value: '⭐ ${d['avgRating']} (${d['ratingCount']})',
              icon: Icons.star,
              color: c.warning),
          // (v0.10) Sessions owed from same-day cancellations.
          StatCard(
            label: tr(context, 'Sessions owed'),
            value: '${d['penaltySessions'] ?? 0}',
            icon: Icons.gavel,
            color: (int.tryParse('${d['penaltySessions'] ?? 0}') ?? 0) > 0
                ? c.danger
                : c.faint,
          ),
        ]),
        const SizedBox(height: 8),
        SimpleBarChart(title: 'Completed sessions per week', data: weekly),
        const SizedBox(height: 4),
        Text(
            'Cancelled: ${d['cancelled']} · Rejected: ${d['rejected']} in the last ${d['days']} days',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
      ]),
    );
  }
}
