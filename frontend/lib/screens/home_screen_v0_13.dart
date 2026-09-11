import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/i18n_v0_13.dart';
import '../core/link_text_v0_13.dart';

/// (v0.10 items 1-3) Home tab for members and coaches.
///
/// Everything on this page is admin-editable (Admin -> Setup -> Home & rules):
/// the welcome text, the "how it works" steps, the rules, and an optional
/// intro video URL. The video block stays hidden until a URL is set, so the
/// client can add it later without an app update.
class HomeScreen extends StatefulWidget {
  /// 'member' or 'coach' — decides which steps and rules are shown.
  final String audience;
  const HomeScreen({super.key, required this.audience});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map? data;
  bool loading = true;
  String? error;
  int _step = 0;
  final _steps = PageController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _steps.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      data = Map<String, dynamic>.from(
          await ApiClient.instance.get('/api/auth/content?audience=${widget.audience}'));
    } on ApiException catch (e) { error = e.message; }
    catch (_) { error = 'Cannot reach server.'; }
    if (mounted) setState(() => loading = false);
  }

  bool get _isAr => Localizations.localeOf(context).languageCode == 'ar';
  String _title(Map b) => _isAr && '${b['title_ar']}'.trim().isNotEmpty ? '${b['title_ar']}' : '${b['title_en']}';
  String _body(Map b) => _isAr && '${b['body_ar']}'.trim().isNotEmpty ? '${b['body_ar']}' : '${b['body_en']}';

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);

    final intro = (data!['intro'] as List?) ?? [];
    final steps = (data!['steps'] as List?) ?? [];
    final rules = (data!['rules'] as List?) ?? [];
    final videoUrl = '${data!['videoUrl'] ?? ''}';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        // ---- welcome ----
        FadeInUp(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Brand.magenta.withValues(alpha: 0.26),
                  Brand.orange.withValues(alpha: 0.16),
                  Brand.surface.withValues(alpha: 0.92),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Brand.magenta.withValues(alpha: 0.28)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CoachlyWordmark(fontSize: 34),
              const SizedBox(height: 10),
              if (intro.isNotEmpty) ...[
                Text(_title(intro.first),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(_body(intro.first),
                    style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFFCFCFDA))),
              ],
            ]),
          ),
        ),

        // ---- video (hidden until the admin sets a URL) ----
        if (videoUrl.isNotEmpty)
          FadeInUp(
            index: 1,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF23232C)),
              ),
              child: Row(children: [
                const GradientIconBadge(icon: Icons.play_circle_fill, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, 'Watch how CoachlyJo works'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    LinkText(url: videoUrl, label: tr(context, 'Play video')),
                  ]),
                ),
              ]),
            ),
          ),

        // ---- how it works (swipeable carousel) ----
        if (steps.isNotEmpty) ...[
          FadeInUp(
            index: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'How it works'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const GradientRule(width: 46),
              ]),
            ),
          ),
          SizedBox(
            height: 178,
            child: PageView.builder(
              controller: _steps,
              onPageChanged: (i) => setState(() => _step = i),
              itemCount: steps.length,
              itemBuilder: (_, i) {
                final s = steps[i] as Map;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Brand.magenta.withValues(alpha: 0.14), Brand.surface],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Brand.magenta.withValues(alpha: 0.22)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 30, height: 30,
                        decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_title(s),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Text(_body(s),
                          style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFFCFCFDA))),
                    ),
                  ]),
                );
              },
            ),
          ),
          // page dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(steps.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              width: i == _step ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                gradient: i == _step ? Brand.gradient : null,
                color: i == _step ? null : const Color(0xFF3A3A46),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
        ],

        // ---- rules & regulations ----
        if (rules.isNotEmpty) ...[
          FadeInUp(
            index: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const GradientIconBadge(icon: Icons.gavel, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr(context, 'Rules & regulations'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 6),
                const GradientRule(width: 46),
              ]),
            ),
          ),
          ...rules.asMap().entries.map((e) {
            final r = e.value as Map;
            return FadeInUp(
              index: 4 + e.key,
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    // The first rule opens by default so the policy is visible
                    // without a tap.
                    initiallyExpanded: e.key == 0,
                    leading: const Icon(Icons.policy_outlined, size: 20),
                    title: Text(_title(r),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(_body(r),
                            style: const TextStyle(fontSize: 13, height: 1.7, color: Color(0xFFCFCFDA))),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ]),
    );
  }
}
