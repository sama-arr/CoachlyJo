import 'package:flutter/material.dart';
import '../core/upload_picker_v0_13.dart';
import 'dart:convert';
import '../core/api_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import '../core/gym_art_v0_13.dart';
import '../core/i18n_v0_13.dart';
import '../core/error_retry_v0_13.dart';

/// =============================================================================
/// Complete Profile (v0.14 items 2, 4, 11).
///
/// Registration now asks five questions; everything else is collected here.
/// The server refuses bookings and purchases until this is done, so the tab
/// stays pinned on the home screen with a badge until it is.
///
/// Members: date of birth, area of Amman, fitness questionnaire.
/// Coaches: date of birth, years of experience, specialties, documents
/// (required — an admin cannot verify a coach without them) and an optional
/// photo. Experience and specialties are used to write the bio automatically.
/// =============================================================================
class CompleteProfileScreen extends StatefulWidget {
  final String role; // 'member' | 'coach'
  final VoidCallback? onCompleted;
  const CompleteProfileScreen(
      {super.key, required this.role, this.onCompleted});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  bool loading = true, saving = false;
  String? error, formError;
  List locations = [];
  List questions = [];

  // shared
  DateTime? dob;
  // member
  String? location;
  final Map<String, dynamic> answers = {};
  // coach
  final _years = TextEditingController();
  final Set<String> specialties = {};
  final List<PickedUpload> bachelorDocs = [];
  final List<PickedUpload> otherDocs = [];
  final List<PickedUpload> experienceDocs = [];
  PickedUpload? photo;

  static const coachSpecialties = [
    'Strength training',
    'Weight loss',
    'Muscle building',
    'Functional fitness',
    'CrossFit',
    'Boxing',
    'Yoga',
    'Pilates',
    'Mobility',
    'Rehabilitation',
    'Nutrition coaching',
    'Cardio & endurance',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _years.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.role == 'member') {
        locations = await ApiClient.instance.get('/api/auth/locations');
        questions = await ApiClient.instance.get('/api/auth/questionnaire');
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Cannot reach server.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 14),
      helpText: tr(context, 'Date of birth'),
    );
    if (picked != null) setState(() => dob = picked);
  }

  /// (v0.15 item 1) Camera, gallery or files — a coach holding a paper
  /// certificate can photograph it instead of having to scan it first.
  Future<void> _pickDocuments(List<PickedUpload> target) async {
    final picked = await pickUploads(context);
    if (picked.isNotEmpty) setState(() => target.addAll(picked));
  }

  /// The profile photo accepts camera and gallery (a PDF makes no sense here).
  Future<void> _pickPhoto() async {
    final picked =
        await pickUploads(context, imagesOnly: true, allowMultiple: false);
    if (picked.isNotEmpty) setState(() => photo = picked.first);
  }

  String? _validate() {
    if (dob == null) return tr(context, 'Please choose your date of birth');
    if (widget.role == 'member') {
      if (location == null) return tr(context, 'Please choose your area');
      final unanswered = questions.where((q) =>
          q['required'] == true &&
          (answers[q['key']] == null || '${answers[q['key']]}'.trim().isEmpty));
      if (unanswered.isNotEmpty)
        return tr(context, 'Please answer all the questions');
    } else {
      final y = int.tryParse(_years.text.trim());
      if (y == null || y < 0 || y > 70)
        return tr(context, 'Please enter your years of experience');
      if (specialties.isEmpty)
        return tr(context, 'Please choose at least one specialty');
      if (bachelorDocs.isEmpty) {
        return tr(context, 'Please upload your Bachelor’s Degree');
      }

      if (experienceDocs.isEmpty) {
        return tr(context, 'Please upload your Certificate of Experience');
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => formError = problem);
      return;
    }
    setState(() {
      saving = true;
      formError = null;
    });

    try {
      final dobStr = dob!.toIso8601String().substring(0, 10);
      if (widget.role == 'member') {
        await ApiClient.instance.post('/api/profile/member', {
          'dateOfBirth': dobStr,
          'location': location,
          'assessment': answers,
        });
      } else {
        await ApiClient.instance.post('/api/profile/coach', {
          'dateOfBirth': dobStr,
          'yearsExperience': int.parse(_years.text.trim()),
          'specialties': specialties.toList(),
          'documents': [
            ...bachelorDocs.map((f) => f.toJson(docType: 'degree_certificate')),
            ...otherDocs
                .map((f) => f.toJson(docType: 'additional_certification')),
            ...experienceDocs.map((f) => f.toJson(docType: 'experience_proof')),
          ],
        });
        // Photo is optional and uploaded separately so a failure here never
        // costs the coach their completed profile.
        if (photo != null) {
          try {
            await ApiClient.instance.post('/api/profile/coach/photo', {
              'mimeType': photo!.mimeType,
              'dataBase64': photo!.dataBase64,
            });
          } on ApiException catch (_) {
            /* profile is saved; photo can be retried */
          }
        }
      }
      if (!mounted) return;
      widget.onCompleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'Profile completed. You are all set!'))));
    } on ApiException catch (e) {
      if (mounted) setState(() => formError = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _documentUploadCard({
    required String title,
    required List<PickedUpload> files,
    required bool isRequired,
    required int index,
  }) {
    final c = AppColors.of(context);
    return FadeInUp(
      index: index,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const GradientIconBadge(
                    icon: Icons.folder_open,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(context, title),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    tr(context, isRequired ? 'Required' : 'Optional'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isRequired
                          ? Theme.of(context).colorScheme.error
                          : c.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr(context, 'PDF, Word, JPG or PNG. Up to 10 MB each.'),
                style: TextStyle(
                  fontSize: 11,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 10),
              ...files.asMap().entries.map(
                    (e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.description_outlined,
                        size: 20,
                      ),
                      title: Text(
                        e.value.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            files.removeAt(e.key);
                          });
                        },
                      ),
                    ),
                  ),
              OutlinedButton.icon(
                onPressed: () => _pickDocuments(files),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(tr(context, 'Add document')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (loading) return const SkeletonList(count: 3);
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final isCoach = widget.role == 'coach';

    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      FadeInUp(
        child: GymBanner(
          title: tr(context, 'Complete your profile'),
          subtitle: isCoach
              ? tr(context,
                  'We need a few details and your certificates before an admin can approve you.')
              : tr(context,
                  'A few more details so your coach can train you safely.'),
          art: isCoach ? GymArt.trophy : GymArt.athlete,
        ),
      ),

      // ---- date of birth (both roles) ----
      FadeInUp(
          index: 1,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading:
                  const GradientIconBadge(icon: Icons.cake_outlined, size: 32),
              title: Text(tr(context, 'Date of birth')),
              subtitle: Text(dob == null
                  ? tr(context, 'Not set')
                  : dob!.toIso8601String().substring(0, 10)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDob,
            ),
          )),

      if (!isCoach) ...[
        // ---- area ----
        FadeInUp(
            index: 2,
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const GradientIconBadge(
                            icon: Icons.place_outlined, size: 32),
                        const SizedBox(width: 12),
                        Text(tr(context, 'Your area'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: location,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: tr(context, 'Area in Amman')),
                        items: locations
                            .map<DropdownMenuItem<String>>(
                                (l) => DropdownMenuItem<String>(
                                      value: '${l['name_en']}',
                                      child: Text(
                                          Localizations.localeOf(context)
                                                      .languageCode ==
                                                  'ar'
                                              ? '${l['name_ar'] ?? l['name_en']}'
                                              : '${l['name_en']}',
                                          overflow: TextOverflow.ellipsis),
                                    ))
                            .toList(),
                        onChanged: (v) => setState(() => location = v),
                      ),
                    ]),
              ),
            )),

        // ---- questionnaire ----
        FadeInUp(
            index: 3,
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const GradientIconBadge(
                            icon: Icons.assignment_outlined, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tr(context, 'Fitness questionnaire'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(tr(context, 'Only your coach sees these answers.'),
                          style: TextStyle(fontSize: 11, color: c.muted)),
                      const SizedBox(height: 10),
                      ...questions.map<Widget>((q) => _questionField(q)),
                    ]),
              ),
            )),
      ],

      if (isCoach) ...[
        // ---- experience ----
        FadeInUp(
            index: 2,
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const GradientIconBadge(
                            icon: Icons.workspace_premium_outlined, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tr(context, 'Years of experience'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _years,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr(context, 'Years of experience'),
                          helperText: tr(context,
                              'Used to write your profile bio automatically.'),
                        ),
                      ),
                    ]),
              ),
            )),

        // ---- specialties ----
        FadeInUp(
            index: 3,
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const GradientIconBadge(
                            icon: Icons.fitness_center, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tr(context, 'What is your specialty?'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: coachSpecialties.map((sp) {
                            final on = specialties.contains(sp);
                            return FilterChip(
                              label: Text(tr(context, sp),
                                  style: const TextStyle(fontSize: 12)),
                              selected: on,
                              onSelected: (v) => setState(() => v
                                  ? specialties.add(sp)
                                  : specialties.remove(sp)),
                            );
                          }).toList()),
                    ]),
              ),
            )),

// ---- Bachelor's Degree ----
        _documentUploadCard(
          title: "Bachelor's Degree",
          files: bachelorDocs,
          isRequired: true,
          index: 4,
        ),

// ---- Other Documents ----
        _documentUploadCard(
          title: 'Other Documents',
          files: otherDocs,
          isRequired: false,
          index: 5,
        ),

// ---- Certificate of Experience ----
        _documentUploadCard(
          title: 'Certificate of Experience',
          files: experienceDocs,
          isRequired: true,
          index: 6,
        ),

        // ---- photo (optional) ----
        FadeInUp(
            index: 7,
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: const GradientIconBadge(
                    icon: Icons.photo_camera_outlined, size: 32),
                title: Text(tr(context, 'Profile photo')),
                subtitle: Text(photo == null
                    ? tr(context, 'Optional — members see this on your profile')
                    : photo!.fileName),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickPhoto,
              ),
            )),
      ],

      if (formError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(formError!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 13)),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: GradientButton(
          onPressed: saving ? null : _submit,
          child: saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(tr(context, 'Save and continue')),
        ),
      ),
    ]);
  }

  /// Renders one questionnaire question according to its configured input type.
  Widget _questionField(Map q) {
    final key = '${q['key']}';
    final label = Localizations.localeOf(context).languageCode == 'ar' &&
            '${q['label_ar'] ?? ''}'.isNotEmpty
        ? '${q['label_ar']}'
        : '${q['label_en']}';
    final type = '${q['input_type'] ?? 'text'}';
    final options = (q['options'] as List?) ?? [];

    if (type == 'dropdown' && options.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: answers[key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: options
              .map<DropdownMenuItem<String>>((o) => DropdownMenuItem<String>(
                  value: '$o',
                  child: Text('$o', overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => answers[key] = v),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        keyboardType:
            type == 'number' ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => answers[key] = v,
      ),
    );
  }
}
