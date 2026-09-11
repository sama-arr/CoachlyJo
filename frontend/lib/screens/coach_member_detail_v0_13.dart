import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// (v0.9 item 2) Member detail for a coach: contact info, the fitness
/// questionnaire the member filled at registration, and their packages with
/// this coach. Reachable from the Requests card and the Clients tab.
///
/// The backend enforces the privacy gate — a coach can only open a member who
/// has a package or a booking with them.
class CoachMemberDetail extends StatefulWidget {
  final String memberId;
  final String memberName;
  const CoachMemberDetail({super.key, required this.memberId, required this.memberName});
  @override
  State<CoachMemberDetail> createState() => _CoachMemberDetailState();
}

class _CoachMemberDetailState extends State<CoachMemberDetail> {
  Map? data;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = await ApiClient.instance.get('/api/coaches/members/${widget.memberId}');
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.memberName)),
      body: GlowBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : _content(),
      ),
    );
  }

  Widget _content() {
    final p = data!['profile'] as Map;
    final q = data!['questionnaire'] as Map;
    final answers = (q['answers'] as List?) ?? [];
    final packages = (data!['packages'] as List?) ?? [];
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        HeroPanel(
          title: '${p['first_name']} ${p['last_name']}',
          subtitle: p['location']?.toString(),
          icon: Icons.person,
        ),

        // ---- contact ----
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const GradientIconBadge(icon: Icons.contact_phone, size: 30),
                const SizedBox(width: 10),
                Text(tr(context, 'Contact'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              if (p['phone'] != null) _row(Icons.phone, '${p['phone']}'),
              if (p['email'] != null) _row(Icons.email_outlined, '${p['email']}'),
              if (p['nationality'] != null) _row(Icons.flag_outlined, '${p['nationality']}'),
            ]),
          ),
        ),

        // ---- questionnaire ----
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const GradientIconBadge(icon: Icons.assignment_outlined, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr(context, 'Fitness questionnaire'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ]),
              const SizedBox(height: 4),
              const GradientRule(width: 40),
              const SizedBox(height: 10),
              if (answers.isEmpty)
                Text(tr(context, 'This member has not filled the questionnaire.'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6)))
              else
                ...answers.map<Widget>((a) {
                  final label = isAr && (a['labelAr'] ?? '').toString().trim().isNotEmpty
                      ? a['labelAr'].toString()
                      : a['labelEn'].toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9A9AA6))),
                      const SizedBox(height: 2),
                      Text('${a['answer']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }),
            ]),
          ),
        ),

        // ---- packages with this coach ----
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const GradientIconBadge(icon: Icons.card_membership, size: 30),
                const SizedBox(width: 10),
                Text(tr(context, 'Packages'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              if (packages.isEmpty)
                Text(tr(context, 'No packages yet.'), style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6)))
              else
                ...packages.map<Widget>((pk) {
                  final done = (pk['classes_consumed'] ?? 0) >= (pk['classes_total'] ?? 0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pkgName(context, pk), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${pk['classes_consumed']} / ${pk['classes_total']} ${tr(context, 'used')}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF9A9AA6))),
                        ]),
                      ),
                      StatusPill(
                        label: trStatus(context, pk['status']),
                        color: done ? const Color(0xFF6E6E7A)
                            : pk['status'] == 'active' ? const Color(0xFF3ED598) : Brand.orange,
                      ),
                    ]),
                  );
                }),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: const Color(0xFF9A9AA6)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
