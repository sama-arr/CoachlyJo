import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/error_retry_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';

/// (v0.10 items 1-3) Admin editor for everything the home page shows:
/// welcome text, "how it works" steps, rules & regulations, and the optional
/// intro video URL — each in English and Arabic. Editing here changes the app
/// immediately; no rebuild needed.
class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key});
  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen> {
  List blocks = [];
  String videoUrl = '';
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
      final res = Map<String, dynamic>.from(
          await ApiClient.instance.get('/api/admin/content'));
      blocks = res['blocks'] as List;
      videoUrl = '${res['videoUrl'] ?? ''}';
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    if (mounted) setState(() => loading = false);
  }

  void _toast(String m) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _editVideo() async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: videoUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Intro video'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Paste a video link (YouTube, Vimeo, direct MP4). Leave empty to hide the video block.',
              style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 10),
          TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Video URL')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (url == null) return;
    try {
      await ApiClient.instance
          .put('/api/admin/content-video', {'videoUrl': url});
      _toast(url.isEmpty ? 'Video hidden.' : 'Video link saved.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editBlock(Map b) async {
    final titleEn = TextEditingController(text: '${b['title_en']}');
    final titleAr = TextEditingController(text: '${b['title_ar']}');
    final bodyEn = TextEditingController(text: '${b['body_en']}');
    final bodyAr = TextEditingController(text: '${b['body_ar']}');
    bool active = b['is_active'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (_, setS) => AlertDialog(
                title: Text('Edit — ${b['key']}'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: titleEn,
                          decoration: const InputDecoration(
                              labelText: 'Title (English)')),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleAr,
                        textDirection: TextDirection.rtl,
                        decoration:
                            const InputDecoration(labelText: 'Title (Arabic)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyEn,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: 'Body (English)',
                            helperText:
                                'Use • at the start of a line for bullet points'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyAr,
                        maxLines: 6,
                        textDirection: TextDirection.rtl,
                        decoration:
                            const InputDecoration(labelText: 'Body (Arabic)'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Visible in the app'),
                        value: active,
                        onChanged: (v) => setS(() => active = v),
                      ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save')),
                ],
              )),
    );
    if (saved != true) return;
    try {
      await ApiClient.instance.put('/api/admin/content/${b['id']}', {
        'titleEn': titleEn.text,
        'titleAr': titleAr.text,
        'bodyEn': bodyEn.text,
        'bodyAr': bodyAr.text,
        'isActive': active,
      });
      _toast('Saved.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _addBlock() async {
    final c = AppColors.of(context);
    final key = TextEditingController();
    final titleEn = TextEditingController();
    final bodyEn = TextEditingController();
    String audience = 'member';
    String kind = 'rule';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (_, setS) => AlertDialog(
                title: const Text('New content block'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        controller: key,
                        decoration: const InputDecoration(
                            labelText: 'Key',
                            helperText: 'Unique id, e.g. rule_refunds'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: audience,
                        decoration:
                            const InputDecoration(labelText: 'Shown to'),
                        items: const [
                          DropdownMenuItem(
                              value: 'member', child: Text('Members')),
                          DropdownMenuItem(
                              value: 'coach', child: Text('Coaches')),
                          DropdownMenuItem(value: 'both', child: Text('Both')),
                        ],
                        onChanged: (v) => setS(() => audience = v ?? 'member'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'rule', child: Text('Rule')),
                          DropdownMenuItem(
                              value: 'step', child: Text('How-it-works step')),
                          DropdownMenuItem(
                              value: 'intro', child: Text('Intro')),
                        ],
                        onChanged: (v) => setS(() => kind = v ?? 'rule'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                          controller: titleEn,
                          decoration: const InputDecoration(
                              labelText: 'Title (English)')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: bodyEn,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              labelText: 'Body (English)')),
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Add the Arabic text afterwards with Edit.',
                            style: TextStyle(fontSize: 11, color: c.muted)),
                      ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Create')),
                ],
              )),
    );
    if (ok != true || key.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.post('/api/admin/content', {
        'key': key.text.trim(),
        'audience': audience,
        'kind': kind,
        'titleEn': titleEn.text,
        'bodyEn': bodyEn.text,
        'sortOrder': 99,
      });
      _toast('Created.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deleteBlock(Map b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this block?'),
        content: Text('"${b['title_en']}" will be removed from the home page.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.delete('/api/admin/content/${b['id']}');
      _toast('Deleted.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home & rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBlock,
        icon: const Icon(Icons.add),
        label: const Text('New block'),
      ),
      body: GlowBackground(
        child: loading
            ? const SkeletonList()
            : error != null
                ? ErrorRetry(message: error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        padding: const EdgeInsets.only(bottom: 90),
                        children: [
                          HeroPanel(
                            title: 'Home & rules',
                            subtitle:
                                'Edit what members and coaches see on their home page',
                            icon: Icons.article,
                          ),
                          Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: const GradientIconBadge(
                                  icon: Icons.play_circle_fill, size: 32),
                              title: const Text('Intro video'),
                              subtitle: Text(
                                  videoUrl.isEmpty
                                      ? 'Not set — video block hidden'
                                      : videoUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: _editVideo,
                            ),
                          ),
                          ..._section('Intro', 'intro'),
                          ..._section('How it works', 'step'),
                          ..._section('Rules & regulations', 'rule'),
                        ]),
                  ),
      ),
    );
  }

  List<Widget> _section(String title, String kind) {
    final c = AppColors.of(context);
    final rows = blocks.where((b) => b['kind'] == kind).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const GradientRule(width: 40),
        ]),
      ),
      ...rows.asMap().entries.map((e) {
        final b = e.value;
        final inactive = b['is_active'] != true;
        return FadeInUp(
          index: e.key,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              title: Text('${b['title_en']}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: inactive ? c.faint : null)),
              subtitle: Text(
                '${b['audience']} · ${'${b['body_en']}'.replaceAll('\n', ' ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Wrap(spacing: 0, children: [
                if (inactive) StatusPill(label: 'hidden', color: c.faint),
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _editBlock(b)),
                IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteBlock(b)),
              ]),
              onTap: () => _editBlock(b),
            ),
          ),
        );
      }),
    ];
  }
}
