import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';

/// (v0.9 items 3 & 5) Admin master view of every package in the system, with
/// full detail (member, coach, classes, price, dates, payment proof) and the
/// management actions: add / deduct classes, cancel, move to another coach.
/// Every mutation requires a reason and is written to the audit trail.
/// Embeddable variant used as an admin tab (no Scaffold of its own).
class AdminPackagesScreenBody extends StatelessWidget {
  const AdminPackagesScreenBody({super.key});
  @override
  Widget build(BuildContext context) => const AdminPackagesScreen(embedded: true);
}

class AdminPackagesScreen extends StatefulWidget {
  /// Optional pre-filter, e.g. opened from a coach profile.
  final String? coachId;
  final String? title;
  /// Pre-fills the search box, e.g. when opened from a member profile.
  final String? memberQuery;
  /// When embedded as a tab the screen renders without its own Scaffold/AppBar.
  final bool embedded;
  const AdminPackagesScreen({super.key, this.coachId, this.title, this.memberQuery, this.embedded = false});
  @override
  State<AdminPackagesScreen> createState() => _AdminPackagesScreenState();
}

class _AdminPackagesScreenState extends State<AdminPackagesScreen> {
  List rows = [];
  bool loading = true;
  String? error;
  String status = 'all';
  String mode = 'all';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.memberQuery != null) _search.text = widget.memberQuery!;
    _load();
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    final q = <String>[];
    if (widget.coachId != null) q.add('coachId=${widget.coachId}');
    if (status != 'all') q.add('status=$status');
    if (mode != 'all') q.add('mode=$mode');
    if (_search.text.trim().isNotEmpty) q.add('q=${Uri.encodeComponent(_search.text.trim())}');
    try {
      rows = await ApiClient.instance.get('/api/admin/member-packages${q.isEmpty ? '' : '?${q.join('&')}'}');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(children: [
          _filters(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? ErrorRetry(message: error!, onRetry: _load)
                    : rows.isEmpty
                        ? const EmptyState(icon: Icons.inventory_2, message: 'No packages match these filters.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: rows.map<Widget>(_card).toList(),
                            ),
                          ),
          ),
        ]);
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'All packages')),
      body: GlowBackground(child: content),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(children: [
        TextField(
          controller: _search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search member or coach…',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _load),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('All', status == 'all' && mode == 'all', () { setState(() { status = 'all'; mode = 'all'; }); _load(); }),
            const SizedBox(width: 6),
            _chip('Active', status == 'active', () { setState(() => status = 'active'); _load(); }),
            const SizedBox(width: 6),
            _chip('Pending payment', status == 'pending_payment', () { setState(() => status = 'pending_payment'); _load(); }),
            const SizedBox(width: 6),
            _chip('Cancelled', status == 'cancelled', () { setState(() => status = 'cancelled'); _load(); }),
            const SizedBox(width: 12),
            _chip('Online', mode == 'online', () { setState(() => mode = mode == 'online' ? 'all' : 'online'); _load(); }),
            const SizedBox(width: 6),
            _chip('In-person', mode == 'in_person', () { setState(() => mode = mode == 'in_person' ? 'all' : 'in_person'); _load(); }),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ActionChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        backgroundColor: selected ? Brand.magenta.withValues(alpha: 0.22) : null,
        side: BorderSide(color: selected ? Brand.magenta : const Color(0xFF3A3A46)),
        onPressed: onTap,
      );

  Color _statusColor(String s) => s == 'active' ? const Color(0xFF3ED598)
      : s == 'cancelled' ? const Color(0xFFFF5470)
      : Brand.orange;

  String _fmt(String? iso) => iso == null ? '—' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());

  Widget _card(dynamic p) {
    final remaining = p['remaining'];
    final total = p['classes_total'];
    final exhausted = (p['classes_consumed'] ?? 0) >= (total ?? 0);
    return BrandCard(
      accent: _statusColor(p['status']),
      onTap: () => _openDetail(p),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${p['member_first']} ${p['member_last']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            StatusPill(
              label: exhausted && p['status'] == 'active' ? 'finished' : p['status'],
              color: exhausted && p['status'] == 'active' ? const Color(0xFF6E6E7A) : _statusColor(p['status']),
            ),
          ]),
          const SizedBox(height: 2),
          Text('${p['package_name']} · ${p['mode'] == 'online' ? 'Online' : 'In-person'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6))),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.sports, size: 14, color: Color(0xFF9A9AA6)),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Coach: ${p['coach_first'] ?? '—'} ${p['coach_last'] ?? ''}',
                  style: const TextStyle(fontSize: 12)),
            ),
            Text('${p['price']} ${p['currency']}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.orange)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _mini('$remaining', 'left'),
            _mini('${p['classes_consumed']}', 'used'),
            _mini('${p['classes_pending']}', 'held'),
            _mini('$total', 'total'),
          ]),
          const SizedBox(height: 8),
          Text('Bought ${_fmt(p['requested_at'])}'
              '${p['expires_at'] != null ? ' · Expires ${_fmt(p['expires_at'])}' : ''}'
              '${(p['adjustments'] ?? 0) > 0 ? ' · ${p['adjustments']} admin edit(s)' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9A9AA6))),
        ]),
      ),
    );
  }

  Widget _mini(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9A9AA6))),
        ]),
      );

  // ---------------------------------------------------------------- actions

  Future<void> _openDetail(dynamic p) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.surfaceHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => _DetailSheet(
          package: p,
          controller: controller,
          onChanged: () { Navigator.pop(ctx); _load(); },
        ),
      ),
    );
  }
}

/// Bottom sheet: full package detail, admin actions and the audit trail.
class _DetailSheet extends StatefulWidget {
  final dynamic package;
  final ScrollController controller;
  final VoidCallback onChanged;
  const _DetailSheet({required this.package, required this.controller, required this.onChanged});
  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  List history = [];
  List coaches = [];
  bool busy = false;

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    try {
      history = await ApiClient.instance.get('/api/admin/member-packages/${widget.package['id']}/history');
      if (mounted) setState(() {});
    } on ApiException catch (_) {}
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFF5A1020) : null,
    ));
  }

  /// Asks for the mandatory reason before any mutation.
  Future<String?> _askReason(String title, String actionLabel, {String? warning}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (warning != null) ...[
            Text(warning, style: const TextStyle(fontSize: 12, color: Color(0xFFFFC542))),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason (required)'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Recorded in the package history with your name.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9A9AA6))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _adjust(int delta) async {
    final reason = await _askReason(
      delta > 0 ? 'Add ${delta.abs()} class(es)' : 'Deduct ${delta.abs()} class(es)',
      delta > 0 ? 'Add' : 'Deduct',
    );
    if (reason == null) return;
    setState(() => busy = true);
    try {
      await ApiClient.instance.post('/api/admin/member-packages/${widget.package['id']}/adjust-classes',
          {'delta': delta, 'reason': reason});
      _toast(delta > 0 ? 'Classes added.' : 'Class deducted.');
      widget.onChanged();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _askReason('Cancel this package', 'Cancel package',
        warning: 'The member loses the remaining classes. Blocked while they still have upcoming bookings.');
    if (reason == null) return;
    setState(() => busy = true);
    try {
      await ApiClient.instance.post('/api/admin/member-packages/${widget.package['id']}/cancel', {'reason': reason});
      _toast('Package cancelled.');
      widget.onChanged();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _move() async {
    try {
      coaches = await ApiClient.instance.get('/api/admin/coaches');
    } on ApiException catch (e) {
      _toast(e.message, error: true);
      return;
    }
    final approved = coaches.where((c) => c['status'] == 'approved' && c['user_id'] != widget.package['coach_id']).toList();
    if (!mounted) return;
    if (approved.isEmpty) { _toast('No other approved coach available.', error: true); return; }

    Map? target;
    final picked = await showDialog<Map>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (c, setS) => AlertDialog(
        title: const Text('Move to another coach'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Any upcoming bookings with the current coach will be released (no class deducted).',
              style: TextStyle(fontSize: 12, color: Color(0xFFFFC542))),
          const SizedBox(height: 10),
          DropdownButtonFormField<Map>(
            value: target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'New coach'),
            items: approved
                .map<DropdownMenuItem<Map>>((c2) => DropdownMenuItem<Map>(
                      value: c2,
                      child: Text('${c2['first_name']} ${c2['last_name']}', overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setS(() => target = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => target == null ? null : Navigator.pop(ctx, target), child: const Text('Continue')),
        ],
      )),
    );
    if (picked == null) return;
    final reason = await _askReason('Move to ${picked['first_name']} ${picked['last_name']}', 'Move');
    if (reason == null) return;
    setState(() => busy = true);
    try {
      final res = await ApiClient.instance.post('/api/admin/member-packages/${widget.package['id']}/reassign',
          {'coachId': picked['user_id'], 'reason': reason});
      final released = res['releasedBookings'] ?? 0;
      _toast(released > 0 ? 'Package moved · $released booking(s) released' : 'Package moved.');
      widget.onChanged();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    final cancelled = p['status'] == 'cancelled';
    return ListView(controller: widget.controller, padding: const EdgeInsets.all(16), children: [
      Center(
        child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFF3A3A46), borderRadius: BorderRadius.circular(2))),
      ),
      const SizedBox(height: 14),
      Text('${p['member_first']} ${p['member_last']}',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      Text('${p['member_email']} · ${p['member_phone'] ?? ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6))),
      const SizedBox(height: 12),
      const GradientRule(width: 48),
      const SizedBox(height: 12),
      _kv('Package', '${p['package_name']}'),
      _kv('Coach', '${p['coach_first'] ?? '—'} ${p['coach_last'] ?? ''}'),
      _kv('Mode', p['mode'] == 'online' ? 'Online' : 'In-person'),
      _kv('Price paid', '${p['price']} ${p['currency']}'),
      _kv('Classes', '${p['classes_consumed']} used · ${p['classes_pending']} held · ${p['remaining']} left of ${p['classes_total']}'),
      _kv('Sessions completed', '${p['sessions_done']}'),
      _kv('Status', p['status']),
      _kv('Payment proof', p['has_proof'] == true ? 'Uploaded' : 'Not uploaded'),
      if (p['payment_rejection_reason'] != null) _kv('Proof rejected', '${p['payment_rejection_reason']}'),
      const SizedBox(height: 16),

      // ---- actions ----
      if (!cancelled) ...[
        const Text('Admin actions', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: busy ? null : () => _adjust(1),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add class'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _adjust(-1),
            icon: const Icon(Icons.remove, size: 18),
            label: const Text('Deduct class'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : _move,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Move coach'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF5470)),
            onPressed: busy ? null : _cancel,
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Cancel package'),
          ),
        ]),
        const SizedBox(height: 18),
      ],

      // ---- audit trail ----
      const Text('History', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (history.isEmpty)
        const Text('No admin changes yet.', style: TextStyle(fontSize: 12, color: Color(0xFF9A9AA6)))
      else
        ...history.map<Widget>((h) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_actionLabel(h['action'])}: ${h['before_value'] ?? '—'} → ${h['after_value'] ?? '—'}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${h['reason']}', style: const TextStyle(fontSize: 12)),
                Text('${h['admin_email']} · ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(h['created_at']).toLocal())}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9A9AA6))),
              ]),
            )),
      const SizedBox(height: 20),
    ]);
  }

  String _actionLabel(String a) => {
        'add_classes': 'Classes added',
        'deduct_classes': 'Classes deducted',
        'cancel': 'Cancelled',
        'move_coach': 'Moved to another coach',
        'extend_expiry': 'Expiry changed',
      }[a] ?? a;

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6)))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
