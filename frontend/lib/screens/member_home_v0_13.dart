import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../core/api_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/i18n_v0_13.dart';
import '../core/motion_v0_13.dart';
import 'home_screen_v0_13.dart';
import 'notifications_v0_13.dart';
import 'complete_profile_v0_13.dart';
import 'app_drawer_v0_13.dart';
import '../core/link_text_v0_13.dart';
import 'settings_screen_v0_13.dart';

class MemberHome extends StatefulWidget {
  const MemberHome({super.key});
  @override
  State<MemberHome> createState() => _MemberHomeState();
}

class _MemberHomeState extends State<MemberHome> {
  int _tab = 0;
  // (v0.14 item 2) Profile completion is mandatory; the tab stays until done.
  bool? _profileComplete;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final st = await ApiClient.instance.get('/api/profile/status');
      if (mounted) setState(() => _profileComplete = st['complete'] == true);
    } catch (_) {
      if (mounted)
        setState(() => _profileComplete = true); // never lock on a network blip
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsProfile = _profileComplete == false;
    // (v0.10 item 1) Home is the first tab: what CoachlyJo is + the rules.
    final pages = [
      const HomeScreen(audience: 'member'),
      if (needsProfile)
        CompleteProfileScreen(
            role: 'member',
            onCompleted: () {
              setState(() {
                _profileComplete = true;
                _tab = 0;
              });
            }),
      const _CoachesTab(),
      const _PackagesTab(),
      const _BookingsTab()
    ];
    final titles = [
      tr(context, 'Home'),
      if (needsProfile) tr(context, 'Complete profile'),
      tr(context, 'Find a Coach'),
      tr(context, 'Packages'),
      tr(context, 'Bookings'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab.clamp(0, titles.length - 1)]),
        actions: const [NotificationBell()],
      ),
      // (v0.14 item 21) Hamburger opens a slide-out drawer.
      drawer: const AppDrawer(role: 'member'),
      body: GlowBackground(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.clamp(0, pages.length - 1),
        onDestinationSelected: (i) => setState(() => _tab = i),
        // (v0.14 item 15) Only the selected tab shows its label, so the bar
        // never squeezes icons and text together.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              tooltip: tr(context, 'Home'),
              label: tr(context, 'Home')),
          if (needsProfile)
            NavigationDestination(
                icon: Badge(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  smallSize: 8,
                  child: const Icon(Icons.assignment_ind_outlined),
                ),
                selectedIcon: const Icon(Icons.assignment_ind),
                tooltip: tr(context, 'Complete profile'),
                label: tr(context, 'Profile')),
          NavigationDestination(
              icon: const Icon(Icons.search),
              tooltip: tr(context, 'Coaches'),
              label: tr(context, 'Coaches')),
          NavigationDestination(
              icon: const Icon(Icons.card_membership),
              tooltip: tr(context, 'Packages'),
              label: tr(context, 'Packages')),
          NavigationDestination(
              icon: const Icon(Icons.event),
              tooltip: tr(context, 'Bookings'),
              label: tr(context, 'Bookings')),
        ],
      ),
    );
  }
}

// ---------------- Shared purchase flow (v0.4 items 6, 7) ----------------
// Packages are bought FOR a specific coach and require a proof-of-payment
// image. Used from the Packages tab (with coach picker) and from a coach's
// page (coach preselected).
Future<void> startPackagePurchase(BuildContext context,
    {Map? preselectedCoach, required VoidCallback onDone}) async {
  List catalogue = [];
  List coaches = [];
  String paymentNote = '';
  try {
    catalogue = await ApiClient.instance.get('/api/members/packages/catalogue');
    coaches = preselectedCoach != null
        ? [preselectedCoach]
        : await ApiClient.instance.get('/api/members/coaches');
    // (v0.5 item 2) Bank details are shown BEFORE the proof upload.
    final note = await ApiClient.instance.get('/api/members/payment-note');
    if (context.mounted)
      paymentNote = noteBody(context, Map<String, dynamic>.from(note));
  } on ApiException catch (e) {
    if (context.mounted) _showError(context, e.message);
    return;
  }
  if (!context.mounted) return;
  if (coaches.isEmpty) {
    _showError(context, 'No approved coaches available yet.');
    return;
  }

  Map? coach = preselectedCoach ?? (coaches.length == 1 ? coaches.first : null);
  String?
      mode; // (v0.6 item 5) member explicitly picks Online / In-person first — no default
  Map? pkg;
  XFile? proofFile;

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> pickProof() async {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );

        if (image != null) {
          setS(() => proofFile = image);
        }
      }

      Future<void> submit() async {
        if (coach == null || pkg == null || proofFile == null) return;
        final f = proofFile!;
        final bytes = await f.readAsBytes();
        final ext = f.name.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        try {
          await ApiClient.instance.post('/api/members/packages/request', {
            'packageDefId': pkg!['id'],
            'coachId': coach!['user_id'],
            'proof': {
              'fileName': f.name,
              'mimeType': mime,
              'dataBase64': base64Encode(bytes),
            },
          });
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          onDone();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(tr(context, 'Request submitted')),
              content: Text(tr(context,
                  'Your proof of payment was submitted. The package activates once the admin confirms the payment.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr(context, 'OK')))
              ],
            ),
          );
        } on ApiException catch (e) {
          if (ctx.mounted) _showError(ctx, e.message);
        }
      }

      final canSubmit = coach != null && pkg != null && proofFile != null;
      return AlertDialog(
        title: Text(tr(ctx, 'Buy a package')),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    tr(context,
                        'Packages are purchased for one specific coach — you will use all its classes with them.'),
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map>(
                  value: coach,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr(context, 'Coach')),
                  items: coaches
                      .map<DropdownMenuItem<Map>>((c) => DropdownMenuItem<Map>(
                            value: c,
                            child: Text('${c['first_name']} ${c['last_name']}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: preselectedCoach != null
                      ? null
                      : (v) => setS(() => coach = v),
                ),
                const SizedBox(height: 12),
                // (v0.6 item 5) Step 1: pick the session type — no default, the
                // member must choose. Step 2: class-count options for that type.
                Text(tr(context, 'Session type'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'online',
                        label: Text(tr(context, 'Online')),
                        icon: const Icon(Icons.videocam, size: 18)),
                    ButtonSegment(
                        value: 'in_person',
                        label: Text(tr(context, 'In-person')),
                        icon: const Icon(Icons.place, size: 18)),
                  ],
                  selected: mode == null ? const {} : {mode!},
                  onSelectionChanged: (sel) => setS(() {
                    mode = sel.isEmpty ? null : sel.first;
                    pkg = null; // class choice resets when the type changes
                  }),
                ),
                const SizedBox(height: 10),
                if (mode == null)
                  Text(
                      tr(context,
                          'Choose Online or In-person to see the class options.'),
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic))
                else ...[
                  Text(tr(context, 'Classes'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...catalogue.where((d) => d['mode'] == mode).map((d) {
                    final selected = pkg != null && pkg!['id'] == d['id'];
                    final count = d['class_count'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setS(() => pkg = d),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Theme.of(ctx).colorScheme.outline,
                              width: selected ? 1.6 : 1,
                            ),
                            color: selected
                                ? Theme.of(ctx)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                          child: Row(children: [
                            Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                                color: selected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        d['is_single'] == true
                                            ? tr(ctx, 'Single session')
                                            : '$count ${tr(ctx, 'classes')}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${tr(ctx, 'Valid')} ${d['validity_weeks']} ${tr(ctx, 'weeks')}',
                                        style: const TextStyle(fontSize: 11)),
                                  ]),
                            ),
                            Text('${d['price']} ${d['currency']}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(ctx).colorScheme.primary)),
                          ]),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                // (v0.5 item 2 / v0.6 step flow) Bank details + proof appear once
                // the member has chosen a package.
                if (pkg != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              tr(ctx,
                                  'Please pay to the following bank details:'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                              paymentNote.isEmpty
                                  ? tr(
                                      ctx, 'Contact admin for payment details.')
                                  : paymentNote,
                              style: const TextStyle(fontSize: 12)),
                        ]),
                  ),
                  const SizedBox(height: 12),
                  Text(tr(ctx, 'Then upload your proof of payment (required)'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                        proofFile == null
                            ? tr(ctx, 'No image selected')
                            : proofFile!.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: proofFile == null
                                ? Theme.of(ctx).colorScheme.error
                                : null),
                      ),
                    ),
                    TextButton.icon(
                        onPressed: pickProof,
                        icon: const Icon(Icons.upload_file),
                        label: Text(tr(ctx, 'Upload'))),
                  ]),
                ],
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(ctx, 'Cancel'))),
          SizedBox(
              width: 110,
              child: GradientButton(
                onPressed: canSubmit ? submit : null,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(tr(ctx, 'Submit')),
              )),
        ],
      );
    }),
  );
}

// (item 5) Errors surface as popup dialogs instead of inline banners.
void _showError(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Cannot complete'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('OK'))
      ],
    ),
  );
}

// ---------------- Coaches ----------------
class _CoachesTab extends StatefulWidget {
  const _CoachesTab();
  @override
  State<_CoachesTab> createState() => _CoachesTabState();
}

class _CoachesTabState extends State<_CoachesTab> {
  List coaches = [];
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
      coaches = await ApiClient.instance.get('/api/members/coaches');
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
    if (loading) return const SkeletonList();
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    if (coaches.isEmpty) {
      return ListView(children: [
        EmptyState(
            icon: Icons.search,
            message: tr(context, 'No approved coaches available yet.')),
      ]);
    }
    // (v0.8) Coaches presented as brand cards with gradient-ring avatars.
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: coaches.length,
        itemBuilder: (_, i) {
          final c = coaches[i];
          final rating = double.tryParse('${c['avg_rating']}') ?? 0;
          return FadeInUp(
              index: i,
              child: BrandCard(
                onTap: () => Navigator.push(
                    context, fadeSlideRoute(_CoachSessions(coach: c))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    GradientAvatar(
                        initials: '${c['first_name'][0]}${c['last_name'][0]}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['first_name']} ${c['last_name']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text('${c['nationality']}',
                                style: TextStyle(fontSize: 12, color: c.muted)),
                            const SizedBox(height: 6),
                            Row(children: [
                              const Icon(Icons.star_rounded,
                                  size: 15, color: Brand.orange),
                              const SizedBox(width: 3),
                              Text(rating > 0 ? rating.toStringAsFixed(1) : '—',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              Text('  (${c['rating_count']})',
                                  style:
                                      TextStyle(fontSize: 11, color: c.muted)),
                            ]),
                          ]),
                    ),
                    Icon(Icons.chevron_right, color: c.faint),
                  ]),
                ),
              ));
        },
      ),
    );
  }
}

class _CoachSessions extends StatefulWidget {
  final Map coach;
  const _CoachSessions({required this.coach});
  @override
  State<_CoachSessions> createState() => _CoachSessionsState();
}

class _CoachSessionsState extends State<_CoachSessions> {
  List sessions = [];
  Map? profile;
  List reviews = [];
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
      final prof = await ApiClient.instance
          .get('/api/members/coaches/${widget.coach['user_id']}/profile');
      profile = prof['coach'];
      reviews = prof['reviews'] ?? [];
      sessions = await ApiClient.instance
          .get('/api/members/coaches/${widget.coach['user_id']}/sessions');
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  Future<void> _book(Map s) async {
    try {
      await ApiClient.instance.post('/api/bookings', {'sessionId': s['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'Booked! Awaiting coach acceptance.'))));
      _load();
    } on ApiException catch (e) {
      // (item 5) e.g. "You can only book an online session" — now a popup.
      if (mounted) _showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM, h:mm a');
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${widget.coach['first_name']} ${widget.coach['last_name']}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? ErrorRetry(message: error!, onRetry: _load)
              : ListView(children: [
                  // Profile header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(
                                radius: 28,
                                child: Text(
                                    '${profile?['first_name']?[0] ?? '?'}',
                                    style: const TextStyle(fontSize: 22))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${profile?['first_name']} ${profile?['last_name']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    Text(
                                        '⭐ ${profile?['avg_rating']} (${profile?['rating_count']} reviews) · ${profile?['nationality'] ?? ''}'),
                                  ]),
                            ),
                          ]),
                          if ((profile?['bio_en'] ?? '').toString().isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(profile!['bio_en'])),
                          const SizedBox(height: 12),
                          // (item 7) Buy a package with THIS coach.
                          FilledButton.icon(
                            onPressed: () => startPackagePurchase(context,
                                preselectedCoach: {
                                  'user_id': widget.coach['user_id'],
                                  'first_name': widget.coach['first_name'],
                                  'last_name': widget.coach['last_name'],
                                },
                                onDone: _load),
                            icon: const Icon(Icons.card_membership),
                            label: Text(
                                'Buy a package with ${widget.coach['first_name']}'),
                          ),
                        ]),
                  ),
                  const Divider(),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(tr(context, 'Upcoming sessions'),
                              style: Theme.of(context).textTheme.titleMedium))),
                  if (sessions.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No upcoming sessions.'))
                  else
                    ...sessions.map<Widget>((s) {
                      final full = (s['seats_left'] ?? 0) <= 0;
                      final isGroup = s['is_group'] == true;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: Icon(s['delivery'] == 'online'
                              ? Icons.videocam
                              : Icons.place),
                          title: Text(df
                              .format(DateTime.parse(s['start_at']).toLocal())),
                          subtitle: Text(
                              '${isGroup ? "Group" : "1-on-1"} · ${s['delivery']} · seats left: ${s['seats_left']}'),
                          trailing: FilledButton(
                              onPressed: full ? null : () => _book(s),
                              child: Text(tr(context, 'Book'))),
                        ),
                      );
                    }),
                  const Divider(),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(tr(context, 'Reviews'),
                              style: Theme.of(context).textTheme.titleMedium))),
                  if (reviews.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(tr(context, 'No reviews yet.')))
                  else
                    ...reviews.map<Widget>((r) => ListTile(
                          leading: const Icon(Icons.star, color: Colors.amber),
                          title: Text(
                              '${r['rating']}/5 · ${r['member_first'] ?? 'Member'}'),
                          subtitle:
                              r['comment'] != null ? Text(r['comment']) : null,
                        )),
                  const SizedBox(height: 24),
                ]),
    );
  }
}

// ---------------- Packages ----------------
class _PackagesTab extends StatefulWidget {
  const _PackagesTab();
  @override
  State<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends State<_PackagesTab> {
  List mine = []; // active + in-progress packages
  List past =
      []; // (v0.6 item 1) exhausted / expired / cancelled — loaded on expand
  bool pastLoaded = false, pastLoading = false;
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
      mine = await ApiClient.instance
          .get('/api/members/packages/mine?scope=active');
      if (pastLoaded)
        past = await ApiClient.instance
            .get('/api/members/packages/mine?scope=past');
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  int get _totalRemaining =>
      mine.fold<int>(0, (n, p) => n + (int.tryParse('${p['remaining']}') ?? 0));
  int get _totalPending =>
      mine.fold<int>(0, (n, p) => n + (int.tryParse('${p['pending']}') ?? 0));

  Future<void> _loadPast() async {
    if (pastLoading) return;
    setState(() => pastLoading = true);
    try {
      past =
          await ApiClient.instance.get('/api/members/packages/mine?scope=past');
      pastLoaded = true;
    } on ApiException catch (_) {}
    if (mounted) setState(() => pastLoading = false);
  }

  // (item 6) Re-upload proof after the admin rejected it.
  Future<void> _reupload(Map p) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (image == null) return;

    final bytes = await image.readAsBytes();
    final ext = image.name.split('.').last.toLowerCase();

    try {
      await ApiClient.instance.post('/api/members/packages/${p['id']}/proof', {
        'proof': {
          'fileName': image.name,
          'mimeType': ext == 'png' ? 'image/png' : 'image/jpeg',
          'dataBase64': base64Encode(bytes),
        },
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'New proof submitted — awaiting review.'),
          ),
        ),
      );

      _load();
    } on ApiException catch (e) {
      if (mounted) _showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startPackagePurchase(context, onDone: _load),
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(tr(context, 'Buy a package')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding:
                const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 88),
            children: [
              // (v0.8) Hero summary: total classes left across active packages.
              HeroPanel(
                title: tr(context, 'My Packages'),
                subtitle: mine.isEmpty
                    ? null
                    : '${mine.length} ${tr(context, 'active')}',
                icon: Icons.card_membership,
                child: mine.isEmpty
                    ? null
                    : Row(children: [
                        HeroStat(
                            value: '$_totalRemaining',
                            label: tr(context, 'Remaining'),
                            animate: true),
                        const SizedBox(width: 10),
                        HeroStat(
                            value: '$_totalPending',
                            label: tr(context, 'Pending'),
                            animate: true),
                      ]),
              ),
              if (mine.isEmpty)
                EmptyState(
                  icon: Icons.card_membership,
                  message: tr(context,
                      'No packages yet. Packages are purchased per coach — tap "Buy a package" to start.'),
                ),
              ...mine.asMap().entries.map(
                  (e) => FadeInUp(index: e.key, child: _packageCard(e.value))),
              const SizedBox(height: 12),
              // (v0.6 item 1) Past packages: never deleted, tucked into history.
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(tr(context, 'Past packages'),
                      style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(tr(context, 'Finished, expired and cancelled'),
                      style: const TextStyle(fontSize: 12)),
                  onExpansionChanged: (open) {
                    if (open && !pastLoaded) _loadPast();
                  },
                  children: [
                    if (pastLoading)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator())),
                    if (pastLoaded && past.isEmpty)
                      EmptyState(
                          icon: Icons.inventory_2,
                          message: tr(context, 'No past packages yet.')),
                    ...past.map((p) => Opacity(
                        opacity: 0.75, child: _packageCard(p, isPast: true))),
                  ],
                ),
              ),
            ]),
      ),
    );
  }

  Widget _packageCard(Map p, {bool isPast = false}) {
    final c = AppColors.of(context);
    final rejected = p['payment_rejection_reason'] != null;
    final coachName = p['coach_first'] != null
        ? '${p['coach_first']} ${p['coach_last']}'
        : '—';
    final edge = isPast
        ? c.outline
        : p['status'] == 'active'
            ? Colors.green
            : Brand.orange;
    return StatusEdgeCard(
      color: edge,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(pkgName(context, p),
                    style: Theme.of(context).textTheme.titleSmall)),
            _statusPill(p['status']),
          ]),
          const SizedBox(height: 4),
          Text(
              '${tr(context, 'Coach')}: $coachName · ${p['mode'] == 'online' ? tr(context, 'Online') : tr(context, 'In-person')}'),
          const SizedBox(height: 6),
          Row(children: [
            // (v0.10 item 4) Progress ring: classes used vs remaining.
            ProgressRing(
              used: int.tryParse('${p['classes_consumed'] ?? 0}') ?? 0,
              total: int.tryParse('${p['classes_total'] ?? 0}') ?? 0,
              size: 54,
              color: isPast ? c.faint : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${p['classes_consumed']} / ${p['classes_total']} ${tr(context, 'used')}',
                        style: const TextStyle(fontSize: 12)),
                    Text('${tr(context, 'Pending')}: ${p['pending']}',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
            ),
          ]),
          Text(_dates(p), style: Theme.of(context).textTheme.bodySmall),
          if (p['status'] == 'pending_payment' && !rejected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  tr(context, 'Proof submitted — awaiting admin confirmation.'),
                  style: const TextStyle(
                      fontStyle: FontStyle.italic, fontSize: 12)),
            ),
          if (rejected) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${tr(context, 'Payment proof rejected')}: ${p['payment_rejection_reason']}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _reupload(p),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(tr(context, 'Re-upload proof')),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _dates(Map p) {
    String fmt(String? iso) => iso == null
        ? '—'
        : fmtDate(context, DateTime.parse(iso).toLocal(), 'd MMM yyyy');
    if (p['status'] == 'active' || p['status'] == 'expired') {
      return '${tr(context, 'Activated')}: ${fmt(p['activated_at'])} · ${tr(context, 'Expires')}: ${fmt(p['expires_at'])}';
    }
    return '${tr(context, 'Requested')}: ${fmt(p['requested_at'])}';
  }

  Widget _statusPill(String s) {
    final c = AppColors.of(context);
    final color = s == 'active'
        ? c.success
        : (s == 'expired' || s == 'cancelled')
            ? c.danger
            : Brand.orange;
    return StatusPill(label: trStatus(context, s), color: color);
  }
}

// ---------------- Bookings ----------------
class _BookingsTab extends StatefulWidget {
  const _BookingsTab();
  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> {
  List bookings = []; // upcoming: pending + accepted, future (v0.6 item 2)
  List history = []; // completed / cancelled / rejected / past — on expand
  bool historyLoaded = false, historyLoading = false;
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
      bookings =
          await ApiClient.instance.get('/api/members/bookings?scope=upcoming');
      if (historyLoaded)
        history =
            await ApiClient.instance.get('/api/members/bookings?scope=history');
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    setState(() => loading = false);
  }

  Future<void> _loadHistory() async {
    if (historyLoading) return;
    setState(() => historyLoading = true);
    try {
      history =
          await ApiClient.instance.get('/api/members/bookings?scope=history');
      historyLoaded = true;
    } on ApiException catch (_) {}
    if (mounted) setState(() => historyLoading = false);
  }

  Future<void> _cancel(Map b) async {
    final c = AppColors.of(context);
    // (v0.10 item 2) Published policy: cancelling more than 24h ahead is free,
    // inside 24h deducts the class, and a member gets 3 cancellations per
    // package. The 4th is blocked here and on the server.
    final start = DateTime.tryParse(b['start_at'] ?? '')?.toLocal();
    final hoursUntil =
        start == null ? 99 : start.difference(DateTime.now()).inMinutes / 60.0;
    final late = hoursUntil < 24;
    final used = int.tryParse('${b['pkg_cancels_used'] ?? 0}') ?? 0;
    final left = (3 - used).clamp(0, 3);

    if (left == 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'Cancel this booking?')),
          content: Text(
              tr(ctx, 'You have used all 3 cancellations for this package.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'OK')))
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Cancel this booking?')),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(late
                  ? tr(ctx,
                      'This session starts within 24 hours. Cancelling now WILL deduct a class from your package.')
                  : tr(ctx,
                      'This session is more than 24 hours away, so no class will be deducted.')),
              const SizedBox(height: 10),
              Text('${left - 1} ${tr(ctx, 'cancellations left')}',
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'Keep booking'))),
          FilledButton(
            style: late
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Yes, cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.post('/api/bookings/${b['id']}/cancel');
      _load();
    } on ApiException catch (e) {
      if (mounted) _showError(context, e.message);
    }
  }

  Future<void> _review(Map b) async {
    int rating = 5;
    final comment = TextEditingController();
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(tr(context, 'Rate your session')),
              content: StatefulBuilder(
                  builder: (c, setS) =>
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                                5,
                                (i) => IconButton(
                                      onPressed: () =>
                                          setS(() => rating = i + 1),
                                      icon: Icon(
                                          i < rating
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: Colors.amber),
                                    ))),
                        TextField(
                            controller: comment,
                            decoration: InputDecoration(
                                labelText: tr(context, 'Comment (optional)'))),
                      ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () async {
                      await ApiClient.instance.post(
                          '/api/bookings/${b['id']}/review',
                          {'rating': rating, 'comment': comment.text});
                      if (context.mounted) Navigator.pop(context);
                      _load();
                    },
                    child: const Text('Submit')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          children: [
            HeroPanel(
              title: tr(context, 'Upcoming'),
              subtitle: bookings.isEmpty ? null : '${bookings.length}',
              icon: Icons.event_available,
            ),
            if (bookings.isEmpty)
              EmptyState(
                icon: Icons.event_busy,
                message: tr(context,
                    'No upcoming sessions. Find a coach and book your next session!'),
              ),
            ...bookings.asMap().entries.map(
                (e) => FadeInUp(index: e.key, child: _bookingCard(e.value))),
            const SizedBox(height: 12),
            // (v0.6 item 2) Everything not upcoming lives in a collapsed history.
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(tr(context, 'History'),
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(
                    tr(context, 'Completed, cancelled and rejected sessions'),
                    style: const TextStyle(fontSize: 12)),
                onExpansionChanged: (open) {
                  if (open && !historyLoaded) _loadHistory();
                },
                children: [
                  if (historyLoading)
                    const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator())),
                  if (historyLoaded && history.isEmpty)
                    EmptyState(
                        icon: Icons.history,
                        message: tr(context, 'No past sessions yet.')),
                  ...history.map(
                      (b) => Opacity(opacity: 0.8, child: _bookingCard(b))),
                ],
              ),
            ),
          ]),
    );
  }

  Widget _bookingCard(Map b) {
    final c = AppColors.of(context);
    final status = b['status'];
    final noShow = b['completion_kind'] == 'no_show';
    final edge = status == 'accepted'
        ? Colors.green
        : status == 'pending'
            ? Brand.orange
            : status == 'completed'
                ? (noShow ? Colors.redAccent : Brand.magenta)
                : c.outline;
    return StatusEdgeCard(
        color: edge,
        child: ListTile(
          title: Text('${b['coach_first']} ${b['coach_last']}'),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDate(context, DateTime.parse(b['start_at']).toLocal(),
                'EEE d MMM, h:mm a')),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StatusPill(
                label:
                    noShow ? tr(context, 'No-show') : trStatus(context, status),
                color: edge,
              ),
            ),
            if (status == 'rejected' && b['rejection_reason'] != null)
              Text('${tr(context, 'Reason')}: ${b['rejection_reason']}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            if (b['zoom_join_url'] != null && status == 'accepted')
              LinkText(
                  url: b['zoom_join_url'],
                  label: tr(context, 'Join Zoom session')),
          ]),
          trailing: status == 'completed'
              ? (noShow
                  ? null
                  : (b['reviewed'] == true
                      ? Chip(label: Text(tr(context, 'Reviewed')))
                      : TextButton(
                          onPressed: () => _review(b),
                          child: Text(tr(context, 'Review')))))
              : (status == 'pending' || status == 'accepted')
                  ? TextButton(
                      onPressed: () => _cancel(b),
                      child: Text(tr(context, 'Cancel')))
                  : null,
        ));
  }
}
