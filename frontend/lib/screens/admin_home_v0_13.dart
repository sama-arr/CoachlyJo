import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/config_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import 'admin_packages_v0_13.dart';
import 'admin_content_v0_13.dart';
import 'app_drawer_v0_13.dart';
import 'notifications_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/simple_charts_v0_13.dart';
import 'settings_screen_v0_13.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: const [NotificationBell()],
      ),
      drawer: const AppDrawer(role: 'admin'),
      body: GlowBackground(child: [const _PendingCoaches(), const _PendingPackages(), const AdminPackagesScreenBody(), const _Reports(), const _People(), const _Structure()][_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        // (v0.14 item 15) Six tabs only fit if just the selected one is labelled.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.verified_user), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.payments), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Packages'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.people), label: 'People'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Setup'),
        ],
      ),
    );
  }
}

// ---------------- Binary viewing helpers (v0.4 items 1, 6) ----------------
// Images preview inline (fetched with the auth header); PDFs/docs open in an
// external viewer via a tokenized URL, since external apps can't set headers.
Future<void> viewBinary(BuildContext context, String path, String? mimeType, String title) async {
  final token = ApiClient.instance.token;
  if ((mimeType ?? '').startsWith('image/')) {
    Uint8List? bytes;
    String? err;
    try {
      final r = await http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: {'Authorization': 'Bearer $token'});
      if (r.statusCode == 200) {
        bytes = r.bodyBytes;
      } else {
        err = 'Could not load image (${r.statusCode})';
      }
    } catch (_) {
      err = 'Cannot reach server.';
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, overflow: TextOverflow.ellipsis),
        content: bytes != null
            ? InteractiveViewer(child: Image.memory(bytes))
            : Text(err ?? 'Unknown error'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  } else {
    // PDFs / Word docs: hand a tokenized URL to the system viewer/browser.
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path?token=$token');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the document')));
    }
  }
}

/// Tappable row for a coach document (item 1).
class _DocRow extends StatelessWidget {
  final Map doc;
  const _DocRow({required this.doc});
  @override
  Widget build(BuildContext context) {
    // Keys differ between endpoints: pending list uses camelCase, summary snake_case.
    final id = doc['id'];
    final type = doc['docType'] ?? doc['doc_type'] ?? 'document';
    final name = doc['fileName'] ?? doc['file_name'] ?? '—';
    final mime = doc['mimeType'] ?? doc['mime_type'];
    final size = doc['byteSize'] ?? doc['byte_size'] ?? 0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon((mime ?? '').toString().startsWith('image/') ? Icons.image : Icons.description, size: 20),
      title: Text('$type: $name', style: const TextStyle(fontSize: 13)),
      subtitle: Text('${((size as num) / 1024).round()} KB'),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () => viewBinary(context, '/api/admin/documents/$id/download', mime, name.toString()),
    );
  }
}

// ---------------- Approvals ----------------
class _PendingCoaches extends StatefulWidget {
  const _PendingCoaches();
  @override
  State<_PendingCoaches> createState() => _PendingCoachesState();
}

class _PendingCoachesState extends State<_PendingCoaches> {
  List coaches = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      coaches = await ApiClient.instance.get('/api/admin/coaches/pending');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _approve(Map c) async {
    await ApiClient.instance.post('/api/admin/coaches/${c['user_id']}/approve');
    _load();
  }

  Future<void> _reject(Map c) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reject coach'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Reason')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Reject')),
      ],
    ));
    if (reason == null || reason.isEmpty) return;
    await ApiClient.instance.post('/api/admin/coaches/${c['user_id']}/reject', {'reason': reason});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    if (coaches.isEmpty) return const Center(child: Text('No pending coaches.'));
    return RefreshIndicator(onRefresh: _load, child: ListView(children: coaches.map<Widget>((c) {
      final docs = (c['documents'] as List?) ?? [];
      return Card(margin: const EdgeInsets.all(12), child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c['first_name']} ${c['last_name']}', style: Theme.of(context).textTheme.titleMedium),
          Text('${c['email']} · ${c['phone']}'),
          Text('Nationality: ${c['nationality']}'),
          if ((c['bio_en'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4), child: Text(c['bio_en'], style: const TextStyle(fontStyle: FontStyle.italic))),
          const SizedBox(height: 8),
          Text('Documents (${docs.length}) — tap to view:'),
          ...docs.map((d) => _DocRow(doc: d)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => _reject(c), child: const Text('Reject')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _approve(c), child: const Text('Approve')),
          ]),
        ],
      )));
    }).toList()));
  }
}

// ---------------- Payments (v0.4 item 6) ----------------
class _PendingPackages extends StatefulWidget {
  const _PendingPackages();
  @override
  State<_PendingPackages> createState() => _PendingPackagesState();
}

class _PendingPackagesState extends State<_PendingPackages> {
  List pkgs = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      pkgs = await ApiClient.instance.get('/api/admin/packages/pending');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _activate(Map p) async {
    try {
      await ApiClient.instance.post('/api/admin/packages/${p['id']}/activate');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package activated; expiry clock started.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Reject the submitted PROOF with a reason; member can re-upload (item 6).
  Future<void> _rejectPayment(Map p) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reject payment proof'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(
          hintText: 'Reason (shown to the member)', helperText: 'The member can re-upload a new proof.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Reject proof')),
      ],
    ));
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ApiClient.instance.post('/api/admin/packages/${p['id']}/reject-payment', {'reason': reason.trim()});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Cancel the request outright (payment never arriving).
  Future<void> _cancelRequest(Map p) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Cancel request?'),
      content: Text('Cancel "${p['name_en']}" for ${p['member_first']} ${p['member_last']}? This ends the request; they would need to purchase again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel request')),
      ],
    ));
    if (ok != true) return;
    await ApiClient.instance.post('/api/admin/packages/${p['id']}/reject');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package request cancelled.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    if (pkgs.isEmpty) return const Center(child: Text('No packages awaiting payment.'));
    return RefreshIndicator(onRefresh: _load, child: ListView(children: pkgs.map<Widget>((p) {
      final rejected = p['payment_rejection_reason'] != null;
      final coachName = p['coach_first'] != null ? '${p['coach_first']} ${p['coach_last']}' : '—';
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${p['name_en']} — ${p['price']} ${p['currency']}',
                  style: Theme.of(context).textTheme.titleSmall)),
              if (rejected)
                Chip(label: const Text('awaiting re-upload'), visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.orange.withValues(alpha: 0.15)),
            ]),
            Text('${p['member_first']} ${p['member_last']} · ${p['email']}'),
            Text('Coach: $coachName · ${p['classes_total']} classes · valid ${p['validity_weeks']} weeks'),
            if (rejected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Rejected: ${p['payment_rejection_reason']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: p['has_proof'] == true
                    ? () => viewBinary(context, '/api/admin/packages/${p['id']}/payment-proof',
                        p['proof_mime'], p['proof_file_name'] ?? 'Payment proof')
                    : null,
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('View proof'),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'rejectProof' ? _rejectPayment(p) : _cancelRequest(p),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rejectProof', child: Text('Reject proof (member re-uploads)')),
                  PopupMenuItem(value: 'cancel', child: Text('Cancel request')),
                ],
              ),
              FilledButton(onPressed: () => _activate(p), child: const Text('Activate')),
            ]),
          ]),
        ),
      );
    }).toList()));
  }
}

// ---------------- Reports + Dashboards (v0.4 item 8) ----------------
class _Reports extends StatefulWidget {
  const _Reports();
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  int days = 30;
  Map? overview;
  Map? detailed;
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      overview = Map<String, dynamic>.from(await ApiClient.instance.get('/api/admin/reports/overview'));
      detailed = Map<String, dynamic>.from(await ApiClient.instance.get('/api/admin/reports/detailed?days=$days'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final d = detailed!;
    final t = (d['totals'] as Map?) ?? {};
    final revenue = ((d['revenueByWeek'] as List?) ?? [])
        .map((w) => MapEntry('${w['week']}', num.tryParse('${w['revenue']}') ?? 0))
        .toList();
    final sessions = ((d['sessionsByWeek'] as List?) ?? [])
        .map((w) => MapEntry('${w['week']}', (w['completed'] as num?) ?? 0))
        .toList();
    final sales = (d['salesByPackage'] as List?) ?? [];
    final leaderboard = (d['coachLeaderboard'] as List?) ?? [];
    final ov = overview!;
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
      Center(child: RangePicker(days: days, onChanged: (v) { setState(() => days = v); _load(); })),
      const SizedBox(height: 12),
      StatGrid(cards: [
        StatCard(label: 'Revenue (last ${d['days']}d)', value: '${t['revenue_in_range'] ?? 0} JOD', icon: Icons.payments, color: Colors.green),
        StatCard(label: 'Sessions completed', value: '${t['sessions_in_range'] ?? 0}', icon: Icons.check_circle),
        StatCard(label: 'Active / total members', value: '${t['active_members'] ?? 0} / ${t['total_members'] ?? 0}', icon: Icons.people),
        StatCard(label: 'Approved coaches', value: '${t['approved_coaches'] ?? 0}', icon: Icons.sports_gymnastics),
        StatCard(label: 'Pending payments', value: '${t['pending_payments'] ?? 0}', icon: Icons.hourglass_top, color: Colors.orange),
        StatCard(label: 'Pending coaches', value: '${t['pending_coaches'] ?? 0}', icon: Icons.pending_actions, color: Colors.orange),
      ]),
      const SizedBox(height: 8),
      SimpleBarChart(title: 'Revenue per week (JOD)', data: revenue),
      const SizedBox(height: 8),
      SimpleBarChart(title: 'Completed sessions per week', data: sessions),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Package sales (last ${d['days']}d)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (sales.isEmpty) const Text('No activated purchases in this period')
        else ...sales.map((s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('${s['name_en']}', overflow: TextOverflow.ellipsis)),
            Text('${s['sold']} sold · ${s['revenue']} JOD'),
          ]),
        )),
      ]))),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Coach performance (last ${d['days']}d)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (leaderboard.isEmpty) const Text('No approved coaches yet')
        else ...leaderboard.map((c) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('${(c['first_name'] ?? '?').toString()[0]}')),
          title: Text('${c['first_name']} ${c['last_name']}'),
          subtitle: Text('⭐ ${c['avg_rating']} (${c['rating_count']}) · cancelled ${c['cancelled_in_range']}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${c['completed_in_range']} done', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${c['active_clients']} clients', style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
      ]))),
      const SizedBox(height: 8),
      _section('Coaches by status', (ov['coachesByStatus'] as List?) ?? [], 'status', 'n'),
      _section('Bookings by status', (ov['bookingsByStatus'] as List?) ?? [], 'status', 'n'),
      const SizedBox(height: 24),
    ]));
  }

  Widget _section(String title, List rows, String k, String v) {
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (rows.isEmpty) const Text('No data')
      else ...rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${r[k]}'),
          Text('${r[v]}'),
        ]),
      )),
    ])));
  }
}

// ---------------- Setup / structure ----------------
class _Structure extends StatefulWidget {
  const _Structure();
  @override
  State<_Structure> createState() => _StructureState();
}

class _StructureState extends State<_Structure> {
  Map? settings;
  bool loading = true;
  String? error;

  static const _dows = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      settings = Map<String, dynamic>.from(await ApiClient.instance.get('/api/admin/settings'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _editSettings() async {
    final dayStart = TextEditingController(text: (settings!['day_start_time'] ?? '').toString());
    final dayEnd = TextEditingController(text: (settings!['day_end_time'] ?? '').toString());
    final tz = TextEditingController(text: (settings!['timezone'] ?? '').toString());
    final currency = TextEditingController(text: (settings!['currency'] ?? '').toString());
    int weekStart = settings!['week_start_dow'] ?? 6;

    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Session structure (§5.1)'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(
          value: weekStart,
          decoration: const InputDecoration(labelText: 'Week starts on'),
          items: List.generate(7, (i) => DropdownMenuItem(value: i, child: Text(_dows[i]))),
          onChanged: (v) => setS(() => weekStart = v ?? 6),
        ),
        TextField(controller: dayStart, decoration: const InputDecoration(labelText: 'Day start (HH:MM, e.g. 06:00)')),
        TextField(controller: dayEnd, decoration: const InputDecoration(labelText: 'Day end (HH:MM, e.g. 00:00)')),
        TextField(controller: tz, decoration: const InputDecoration(labelText: 'Timezone')),
        TextField(controller: currency, decoration: const InputDecoration(labelText: 'Currency')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          await ApiClient.instance.put('/api/admin/settings', {
            'weekStartDow': weekStart,
            'dayStartTime': dayStart.text.trim(),
            'dayEndTime': dayEnd.text.trim(),
            'timezone': tz.text.trim(),
            'currency': currency.text.trim(),
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Save')),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final s = settings!;
    return Scaffold(
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Session structure', style: Theme.of(context).textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.edit), onPressed: _editSettings),
          ]),
          Text('Week starts: ${_dows[s['week_start_dow'] ?? 6]}'),
          Text('Day window: ${s['day_start_time']} → ${s['day_end_time']}'),
          Text('Timezone: ${s['timezone']}'),
          Text('Currency: ${s['currency']}'),
        ]))),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.card_membership),
          title: const Text('Packages'),
          subtitle: const Text('Edit price, classes, validity, mode, active'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _PackagesAdmin())),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.location_city),
          title: const Text('Locations'),
          subtitle: const Text('Add / remove the registration location list'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _LocationsAdmin())),
        )),
        const SizedBox(height: 8),
        // (v0.10) Home page + rules editor and coach penalties.
        Card(child: ListTile(
          leading: const GradientIconBadge(icon: Icons.article, size: 32),
          title: const Text('Home & rules'),
          subtitle: const Text('Welcome text, how-it-works steps, rules, intro video'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, fadeSlideRoute(const AdminContentScreen())),
        )),
        // (v0.15) Integration health — makes a missing environment variable
        // obvious instead of letting it fail silently, as ZOOM_HOST_USER did.
        Card(child: ListTile(
          leading: const GradientIconBadge(icon: Icons.monitor_heart_outlined, size: 32),
          title: const Text('Integration health'),
          subtitle: const Text('Zoom, email, push and schema status'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, fadeSlideRoute(const _IntegrationHealthScreen())),
        )),
        // (v0.14 item 6) Contact details shown on the app's Contact Us screen.
        Card(child: ListTile(
          leading: const GradientIconBadge(icon: Icons.support_agent, size: 32),
          title: const Text('Contact details'),
          subtitle: const Text('Email, phone, WhatsApp and Instagram shown to users'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, fadeSlideRoute(const _ContactSettingsScreen())),
        )),
        Card(child: ListTile(
          leading: const GradientIconBadge(icon: Icons.person_remove, size: 32),
          title: const Text('Account deletion requests'),
          subtitle: const Text('Requests submitted from the public web form'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, fadeSlideRoute(const _DeletionRequestsScreen())),
        )),
        Card(child: ListTile(
          leading: const GradientIconBadge(icon: Icons.gavel, size: 32),
          title: const Text('Coach penalties'),
          subtitle: const Text('Sessions owed from same-day coach cancellations'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, fadeSlideRoute(const _PenaltiesScreen())),
        )),
        const SizedBox(height: 8),
        // v0.5: slot templates retired — coaches manage their own weekly
        // availability from the coach app (Availability tab).
        const Card(child: Padding(padding: EdgeInsets.all(12), child: Text(
          'Scheduling is managed by each coach from their Availability tab. '
          'Sessions are generated automatically from coach weekly hours.',
          style: TextStyle(fontSize: 12, color: Colors.grey)))),
        const SizedBox(height: 80),
      ])),
    );
  }
}

// ---------------- People directory + profiles ----------------
class _People extends StatefulWidget {
  const _People();
  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  bool showCoaches = true;
  List rows = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      rows = await ApiClient.instance.get(showCoaches ? '/api/admin/coaches' : '/api/admin/members');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Coaches')),
          ButtonSegment(value: false, label: Text('Members')),
        ],
        selected: {showCoaches},
        onSelectionChanged: (s) { setState(() => showCoaches = s.first); _load(); },
      )),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? ErrorRetry(message: error!, onRetry: _load)
        : RefreshIndicator(onRefresh: _load, child: ListView(children: rows.map<Widget>((r) => ListTile(
            leading: CircleAvatar(child: Text('${(r['first_name'] ?? '?').toString()[0]}')),
            title: Text('${r['first_name']} ${r['last_name']}'),
            subtitle: Text(showCoaches
              ? '${r['email']} · ⭐ ${r['avg_rating']} (${r['rating_count']}) · ${r['status']}'
              : '${r['email']} · ${r['phone']} · ${r['bookings_count']} bookings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              showCoaches ? _CoachSummary(coachId: r['user_id']) : _MemberSummary(memberId: r['user_id']))),
          )).toList())),
      ),
    ]);
  }
}

class _CoachSummary extends StatefulWidget {
  final String coachId;
  const _CoachSummary({required this.coachId});
  @override
  State<_CoachSummary> createState() => _CoachSummaryState();
}

class _CoachSummaryState extends State<_CoachSummary> {
  Map? data;
  List members = [];   // (v0.9 item 4) everyone who bought a package with this coach
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = Map<String, dynamic>.from(await ApiClient.instance.get('/api/admin/coaches/${widget.coachId}/summary'));
      members = await ApiClient.instance.get('/api/admin/coaches/${widget.coachId}/members');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coach profile')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? ErrorRetry(message: error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final c = AppColors.of(context);
    final p = data!['profile'];
    final today = data!['today'];
    final reviews = (data!['reviews'] as List?) ?? [];
    final documents = (data!['documents'] as List?) ?? [];
    final byStatus = (today['bookingsByStatus'] as List?) ?? [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${p['first_name']} ${p['last_name']}', style: Theme.of(context).textTheme.titleLarge),
      Text('${p['email']} · ${p['phone']}'),
      Text('Nationality: ${p['nationality']} · Status: ${p['status']}'),
      Text('⭐ ${p['avg_rating']} (${p['rating_count']} reviews)'),
      const Divider(height: 28),
      // (v0.9 item 4) Members who bought a package with this coach.
      Row(children: [
        Expanded(child: Text('Members (${members.length})', style: Theme.of(context).textTheme.titleMedium)),
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminPackagesScreen(
              coachId: widget.coachId,
              title: '${p['first_name']} ${p['last_name']} — packages',
            ),
          )),
          icon: const Icon(Icons.inventory_2, size: 16),
          label: const Text('Packages'),
        ),
      ]),
      if (members.isEmpty) const Text('No members yet')
      else ...members.map((m) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          dense: true,
          leading: GradientAvatar(
            initials: '${(m['first_name'] ?? '?').toString()[0]}${(m['last_name'] ?? '?').toString()[0]}',
            size: 36),
          title: Text('${m['first_name']} ${m['last_name']}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${m['packages']} package(s) · ${m['classes_used']}/${m['classes_bought']} classes used\n'
              '${m['revenue']} JOD · ${m['phone'] ?? ''}'),
          isThreeLine: true,
          trailing: m['has_active'] == true
              ? StatusPill(label: 'active', color: c.success)
              : StatusPill(label: 'past', color: c.faint),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => _MemberSummary(memberId: m['member_id']))),
        ),
      )),
      const Divider(height: 28),
      // (v0.4 item 1) Documents viewable from the profile.
      Text('Documents', style: Theme.of(context).textTheme.titleMedium),
      if (documents.isEmpty) const Text('No documents uploaded')
      else ...documents.map((d) => _DocRow(doc: d)),
      const Divider(height: 28),
      Text("Today's summary", style: Theme.of(context).textTheme.titleMedium),
      Text('Sessions today: ${today['sessions']}'),
      if (byStatus.isEmpty) const Text('No bookings today')
      else ...byStatus.map((b) => Text('• ${b['status']}: ${b['n']}')),
      const Divider(height: 28),
      Text('Reviews', style: Theme.of(context).textTheme.titleMedium),
      if (reviews.isEmpty) const Text('No reviews yet')
      else ...reviews.map((r) => ListTile(
        dense: true, leading: const Icon(Icons.star, color: Colors.amber),
        title: Text('${r['rating']}/5 · ${r['member_first'] ?? 'Member'}'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r['session_at'] != null) Text('Session: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(r['session_at']).toLocal())} · ${r['session_delivery'] ?? ''}'),
          if (r['comment'] != null) Text(r['comment']),
        ]),
        isThreeLine: r['comment'] != null,
      )),
    ]);
  }
}

class _MemberSummary extends StatefulWidget {
  final String memberId;
  const _MemberSummary({required this.memberId});
  @override
  State<_MemberSummary> createState() => _MemberSummaryState();
}

class _MemberSummaryState extends State<_MemberSummary> {
  Map? data;
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = Map<String, dynamic>.from(await ApiClient.instance.get('/api/admin/members/${widget.memberId}/summary'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Member profile')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? ErrorRetry(message: error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final p = data!['profile'];
    final bookings = (data!['bookingsByStatus'] as List?) ?? [];
    final packages = (data!['packages'] as List?) ?? [];
    final assessment = data!['assessment'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${p['first_name']} ${p['last_name']}', style: Theme.of(context).textTheme.titleLarge),
      Text('${p['email']} · ${p['phone']}'),
      Text('Location: ${p['location'] ?? '—'}'),
      const Divider(height: 28),
      Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
      if (bookings.isEmpty) const Text('None') else ...bookings.map((b) => Text('• ${b['status']}: ${b['n']}')),
      const Divider(height: 28),
      Text('Packages', style: Theme.of(context).textTheme.titleMedium),
      if (packages.isEmpty) const Text('None')
      else ...packages.map((pk) {
        // (v0.9 item 3) Tap a package to add/deduct classes, move coach or cancel.
        return Card(child: ListTile(
          dense: true,
          title: Text('${pk['name_en']} · ${pk['status']}'),
          subtitle: Text('Coach: ${pk['coach_first'] ?? '—'} ${pk['coach_last'] ?? ''} · remaining ${pk['remaining']}/${pk['classes_total']}'),
          trailing: const Icon(Icons.tune, size: 18),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminPackagesScreen(
              title: '${p['first_name']} ${p['last_name']} — packages',
              memberQuery: '${p['first_name']} ${p['last_name']}',
            ),
          )).then((_) => _load()),
        ));
      }),
      if (assessment != null) ...[
        const Divider(height: 28),
        Text('Questionnaire', style: Theme.of(context).textTheme.titleMedium),
        Text('${assessment['responses']}'),
      ],
    ]);
  }
}

/// (v0.15) Integration health. The v0.14 Zoom outage was one missing
/// environment variable that nothing surfaced; this screen reports what the
/// running server actually has configured.
class _IntegrationHealthScreen extends StatefulWidget {
  const _IntegrationHealthScreen();
  @override
  State<_IntegrationHealthScreen> createState() => _IntegrationHealthScreenState();
}

class _IntegrationHealthScreenState extends State<_IntegrationHealthScreen> {
  Map? data;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = Map<String, dynamic>.from(
          await ApiClient.instance.get('/api/health/integrations'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Widget _tile(String name, bool ok, String detail, {String? warning}) {
    final c = AppColors.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? c.success : c.danger, size: 26),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail, style: TextStyle(fontSize: 12, color: c.muted)),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(warning, style: TextStyle(fontSize: 12, color: c.warning)),
            ),
        ]),
        isThreeLine: warning != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final zoom = (data?['zoom'] as Map?) ?? {};
    final push = (data?['push'] as Map?) ?? {};
    final schema = (data?['schema'] as Map?) ?? {};
    final missing = (zoom['missing'] as List?) ?? [];
    final noLink = zoom['sessionsWithoutLink'] ?? 0;
    final devices = (push['devices'] as Map?) ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Integration health')),
      body: GlowBackground(
        child: loading
            ? const SkeletonList(count: 4)
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text('Environment: ${data?['environment'] ?? '—'}',
                            style: TextStyle(fontSize: 12, color: c.muted)),
                      ),
                      _tile(
                        'Zoom',
                        zoom['configured'] == true,
                        zoom['configured'] == true
                            ? 'Meetings are created automatically.'
                            : 'Missing: ${missing.join(', ')}',
                        warning: noLink is int && noLink > 0
                            ? '$noLink confirmed online session(s) have no meeting link.'
                            : (zoom['placeholdersAllowed'] == true
                                ? 'Placeholder links are enabled — never leave this on in production.'
                                : null),
                      ),
                      _tile('Email (SMTP)', (data?['email'] as Map?)?['configured'] == true,
                          (data?['email'] as Map?)?['configured'] == true
                              ? 'Verification and reset emails are being sent.'
                              : 'Not configured — codes appear in the server log only.'),
                      _tile('Push notifications', push['configured'] == true,
                          push['configured'] == true
                              ? 'Registered devices — android: ${devices['android'] ?? 0}, ios: ${devices['ios'] ?? 0}'
                              : 'Firebase credentials not set; notifications stay in-app.'),
                      _tile('Database schema', schema['upToDate'] == true,
                          'Database v${schema['current'] ?? '?'} · app expects v${schema['expected'] ?? '?'}',
                          warning: schema['upToDate'] == true ? null : 'Run: npm run migrate'),
                    ]),
                  ),
      ),
    );
  }
}

/// (v0.14 item 6) Admin editor for the Contact Us details. The phone number
/// and Instagram handle can be filled in later without an app release.
class _ContactSettingsScreen extends StatefulWidget {
  const _ContactSettingsScreen();
  @override
  State<_ContactSettingsScreen> createState() => _ContactSettingsScreenState();
}

class _ContactSettingsScreenState extends State<_ContactSettingsScreen> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();
  bool loading = true, saving = false;
  String? error, message;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _email.dispose(); _phone.dispose(); _whatsapp.dispose(); _instagram.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final c = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/contact'));
      _email.text = '${c['email'] ?? ''}';
      _phone.text = '${c['phone'] ?? ''}';
      _whatsapp.text = '${c['whatsapp'] ?? ''}';
      _instagram.text = '${c['instagram'] ?? ''}';
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    setState(() { saving = true; message = null; });
    try {
      await ApiClient.instance.put('/api/admin/contact', {
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'instagram': _instagram.text.trim().replaceAll('@', ''),
      });
      setState(() => message = 'Saved. Users see these immediately.');
    } on ApiException catch (e) {
      setState(() => message = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact details')),
      body: GlowBackground(
        child: loading
            ? const SkeletonList(count: 2)
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : ListView(padding: const EdgeInsets.all(16), children: [
                    Text(
                      'These appear on the Contact us screen in the app. Leave a field '
                      'empty to hide that row.',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Support email', helperText: 'Opens the mail app when tapped'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Phone', helperText: 'Dials when tapped, e.g. +962 7 9000 0000'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _whatsapp,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'WhatsApp', helperText: 'Number in international format'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _instagram,
                      decoration: const InputDecoration(
                          labelText: 'Instagram handle', helperText: 'Without the @'),
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(message!, style: const TextStyle(fontSize: 13)),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving ? null : _save,
                      child: saving
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ]),
      ),
    );
  }
}

/// (v0.13) Deletion requests from the public /delete-account page. Google Play
/// requires that route; the admin verifies the person and completes it here,
/// which runs the same deletion the in-app button does.
class _DeletionRequestsScreen extends StatefulWidget {
  const _DeletionRequestsScreen();
  @override
  State<_DeletionRequestsScreen> createState() => _DeletionRequestsScreenState();
}

class _DeletionRequestsScreenState extends State<_DeletionRequestsScreen> {
  List rows = [];
  String status = 'open';
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try { rows = await ApiClient.instance.get('/api/admin/deletion-requests?status=$status'); }
    on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _act(Map r, bool complete) async {
    if (complete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this account?'),
          content: Text('Verify this request came from the account owner before continuing.\n\n'
              '${r['email']}\n\n'
              '${r['matched_user_id'] == null ? 'No active account matches this email — the request will simply be closed.' : 'The matching account and its personal data will be erased and upcoming sessions cancelled.'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete account'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ApiClient.instance.post(
          '/api/admin/deletion-requests/${r['id']}/${complete ? 'complete' : 'reject'}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(complete ? 'Account deleted and request closed.' : 'Request rejected.')));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final df = DateFormat('d MMM yyyy, h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Deletion requests')),
      body: GlowBackground(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Open')),
                ButtonSegment(value: 'done', label: Text('Done')),
                ButtonSegment(value: 'rejected', label: Text('Rejected')),
              ],
              selected: {status},
              onSelectionChanged: (s) { setState(() => status = s.first); _load(); },
            ),
          ),
          Expanded(
            child: loading
                ? const SkeletonList()
                : error != null
                    ? ErrorRetry(message: error!, onRetry: _load)
                    : rows.isEmpty
                        ? const EmptyState(icon: Icons.inbox, message: 'No requests here.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(children: rows.asMap().entries.map<Widget>((e) {
                              final r = e.value;
                              final matched = r['matched_user_id'] != null;
                              return FadeInUp(index: e.key, child: Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                child: ListTile(
                                  leading: GradientIconBadge(
                                      icon: matched ? Icons.person_remove : Icons.help_outline, size: 32),
                                  title: Text('${r['email']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(matched ? 'Matches an active ${r['matched_role']} account' : 'No active account with this email',
                                        style: const TextStyle(fontSize: 12)),
                                    if ('${r['note'] ?? ''}'.isNotEmpty)
                                      Text('${r['note']}', style: TextStyle(fontSize: 11, color: c.muted)),
                                    Text(df.format(DateTime.parse(r['created_at']).toLocal()),
                                        style: TextStyle(fontSize: 10, color: c.faint)),
                                  ]),
                                  isThreeLine: true,
                                  trailing: status != 'open' ? null : Wrap(children: [
                                    IconButton(
                                      tooltip: 'Complete',
                                      icon: Icon(Icons.check, color: c.success),
                                      onPressed: () => _act(r, true),
                                    ),
                                    IconButton(
                                      tooltip: 'Reject',
                                      icon: Icon(Icons.close, color: c.danger),
                                      onPressed: () => _act(r, false),
                                    ),
                                  ]),
                                ),
                              ));
                            }).toList()),
                          ),
          ),
        ]),
      ),
    );
  }
}

/// (v0.10 item 2) Coach penalties: one session owed per same-day cancellation.
/// CoachlyJo has no payout ledger yet, so the admin settles these manually and
/// marks them done here.
class _PenaltiesScreen extends StatefulWidget {
  const _PenaltiesScreen();
  @override
  State<_PenaltiesScreen> createState() => _PenaltiesScreenState();
}

class _PenaltiesScreenState extends State<_PenaltiesScreen> {
  List rows = [];
  bool loading = true;
  bool showSettled = false;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      rows = await ApiClient.instance.get('/api/admin/penalties?settled=${showSettled}');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _settle(Map p) async {
    try {
      await ApiClient.instance.post('/api/admin/penalties/${p['id']}/settle');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as settled.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final df = DateFormat('d MMM yyyy, h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Coach penalties')),
      body: GlowBackground(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Owed')),
                ButtonSegment(value: true, label: Text('Settled')),
              ],
              selected: {showSettled},
              onSelectionChanged: (s) { setState(() => showSettled = s.first); _load(); },
            ),
          ),
          Expanded(
            child: loading
                ? const SkeletonList()
                : error != null
                    ? ErrorRetry(message: error!, onRetry: _load)
                    : rows.isEmpty
                        ? const EmptyState(icon: Icons.verified, message: 'Nothing here — no sessions owed.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(children: rows.asMap().entries.map<Widget>((e) {
                              final p = e.value;
                              return FadeInUp(
                                index: e.key,
                                child: Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  child: ListTile(
                                    leading: const GradientIconBadge(icon: Icons.gavel, size: 32),
                                    title: Text('${p['coach_first']} ${p['coach_last']} — ${p['sessions']} session(s)',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${p['reason']}', style: const TextStyle(fontSize: 12)),
                                      if (p['session_at'] != null)
                                        Text('Session: ${df.format(DateTime.parse(p['session_at']).toLocal())}'
                                            '${p['member_first'] != null ? ' · ${p['member_first']} ${p['member_last']}' : ''}',
                                            style: TextStyle(fontSize: 11, color: c.muted)),
                                    ]),
                                    isThreeLine: true,
                                    trailing: p['settled_at'] == null
                                        ? TextButton(onPressed: () => _settle(p), child: const Text('Settle'))
                                        : StatusPill(label: 'settled', color: c.faint),
                                  ),
                                ),
                              );
                            }).toList()),
                          ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Package management ----------------
class _PackagesAdmin extends StatefulWidget {
  const _PackagesAdmin();
  @override
  State<_PackagesAdmin> createState() => _PackagesAdminState();
}

class _PackagesAdminState extends State<_PackagesAdmin> {
  List pkgs = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try { pkgs = await ApiClient.instance.get('/api/admin/packages'); }
    on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _edit(Map p) async {
    final price = TextEditingController(text: '${p['price']}');
    final classes = TextEditingController(text: '${p['class_count']}');
    final weeks = TextEditingController(text: '${p['validity_weeks']}');
    bool active = p['is_active'] == true;
    final saved = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text(p['name_en']),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (JOD)')),
        TextField(controller: classes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Classes')),
        TextField(controller: weeks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Validity (weeks)')),
        SwitchListTile(value: active, title: const Text('Active'), onChanged: (v) => setS(() => active = v)),
        const Text('Note: edits apply to new purchases only.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    )));
    if (saved != true) return;
    try {
      await ApiClient.instance.put('/api/admin/packages/${p['id']}', {
        'price': num.tryParse(price.text),
        'classCount': int.tryParse(classes.text),
        'validityWeeks': int.tryParse(weeks.text),
        'isActive': active,
      });
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// (v0.11 item 1) One button that always does the safe thing:
  ///   * never purchased -> confirm, then delete for good;
  ///   * has purchases   -> the API refuses and reports how many; we then offer
  ///     Archive, which hides it from members while their packages keep working.
  Future<void> _deleteOrArchive(Map p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p['name_en']}"?'),
        content: const Text('If this package has never been purchased it is deleted permanently. '
            'If members have bought it, you will be offered to archive it instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.instance.delete('/api/admin/packages/${p['id']}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package deleted.')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Purchased -> offer the archive path.
      final archive = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Archive instead?'),
          content: Text('${e.message}\n\nArchiving removes it from the member catalogue immediately. '
              'Members who already bought it keep their classes, and your reports stay accurate.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive')),
          ],
        ),
      );
      if (archive != true) return;
      try {
        await ApiClient.instance.delete('/api/admin/packages/${p['id']}?force=archive');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package archived.')));
        _load();
      } on ApiException catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e2.message)));
      }
    }
  }

  Future<void> _restore(Map p) async {
    try {
      await ApiClient.instance.post('/api/admin/packages/${p['id']}/restore');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package restored.')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _create() async {
    final nameEn = TextEditingController();
    final nameAr = TextEditingController();
    final price = TextEditingController();
    final classes = TextEditingController(text: '6');
    final weeks = TextEditingController(text: '8');
    String mode = 'online';
    bool single = false;
    final saved = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('New package'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameEn, decoration: const InputDecoration(labelText: 'Name (English)')),
        TextField(controller: nameAr, decoration: const InputDecoration(labelText: 'Name (Arabic)')),
        TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (JOD)')),
        TextField(controller: classes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Classes')),
        TextField(controller: weeks, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Validity (weeks)')),
        DropdownButtonFormField<String>(value: mode, decoration: const InputDecoration(labelText: 'Mode'),
          items: const [DropdownMenuItem(value: 'online', child: Text('Online')), DropdownMenuItem(value: 'in_person', child: Text('In-person'))],
          onChanged: (v) => setS(() => mode = v ?? 'online')),
        SwitchListTile(value: single, title: const Text('Single session (one trial per coach)'), onChanged: (v) => setS(() => single = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
      ],
    )));
    if (saved != true) return;
    try {
      await ApiClient.instance.post('/api/admin/packages', {
        'nameEn': nameEn.text.trim(), 'nameAr': nameAr.text.trim(),
        'price': num.tryParse(price.text), 'classCount': int.tryParse(classes.text),
        'validityWeeks': int.tryParse(weeks.text), 'mode': mode, 'isSingle': single,
      });
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Packages')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New package')),
      body: loading ? const SkeletonList()
        : error != null ? ErrorRetry(message: error!, onRetry: _load)
        : RefreshIndicator(onRefresh: _load, child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: pkgs.asMap().entries.map<Widget>((entry) {
              final p = entry.value;
              final archived = p['is_archived'] == true;
              final purchases = int.tryParse('${p['purchases'] ?? 0}') ?? 0;
              return FadeInUp(index: entry.key, child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Opacity(
                  opacity: archived ? 0.55 : 1,
                  child: ListTile(
                    leading: Icon(p['mode'] == 'online' ? Icons.videocam : Icons.place),
                    title: Row(children: [
                      Expanded(child: Text('${p['name_en']}')),
                      if (archived) StatusPill(label: 'archived', color: c.faint)
                      else if (p['is_active'] != true) const StatusPill(label: 'inactive', color: Brand.orange),
                    ]),
                    subtitle: Text('${p['class_count']} ${p['class_count'] == 1 ? "session" : "classes"} · '
                        '${p['price']} ${p['currency']} · ${p['validity_weeks']} wks · ${p['mode']}'
                        '${purchases > 0 ? ' · $purchases sold' : ' · never sold'}'),
                    trailing: Wrap(spacing: 0, children: [
                      if (archived)
                        IconButton(
                          tooltip: 'Restore to catalogue',
                          icon: const Icon(Icons.unarchive_outlined),
                          onPressed: () => _restore(p),
                        )
                      else ...[
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(p)),
                        IconButton(
                          tooltip: purchases > 0 ? 'Archive (already sold)' : 'Delete',
                          icon: Icon(purchases > 0 ? Icons.archive_outlined : Icons.delete_outline),
                          onPressed: () => _deleteOrArchive(p),
                        ),
                      ],
                    ]),
                  ),
                ),
              ));
            }).toList())),
    );
  }
}

// ---------------- Location management ----------------
class _LocationsAdmin extends StatefulWidget {
  const _LocationsAdmin();
  @override
  State<_LocationsAdmin> createState() => _LocationsAdminState();
}

class _LocationsAdminState extends State<_LocationsAdmin> {
  List locs = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try { locs = await ApiClient.instance.get('/api/admin/locations'); }
    on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    setState(() => loading = false);
  }

  Future<void> _add() async {
    final en = TextEditingController();
    final ar = TextEditingController();
    final saved = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('New location'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: en, decoration: const InputDecoration(labelText: 'Name (English)')),
        TextField(controller: ar, decoration: const InputDecoration(labelText: 'Name (Arabic)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
      ],
    ));
    if (saved != true || en.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.post('/api/admin/locations', {'nameEn': en.text.trim(), 'nameAr': ar.text.trim()});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(Map l) async {
    try { await ApiClient.instance.delete('/api/admin/locations/${l['id']}'); _load(); }
    on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locations')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add location')),
      body: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? ErrorRetry(message: error!, onRetry: _load)
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.only(bottom: 80), children: locs.map<Widget>((l) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              title: Text(l['name_en']),
              subtitle: Text(l['is_active'] == true ? 'active' : 'inactive'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(l)),
            ),
          )).toList())),
    );
  }
}
