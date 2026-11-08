import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/api_v0_13.dart';
import '../core/i18n_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/countries_v0_13.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool isCoach = false;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController(); // calendar (date only), items 10,11
  // (v0.14 item 9) Nationality defaults to Jordan — almost every member is
  // Jordanian — and is searchable because the list is ~200 entries long.
  String? _nationality = 'Jordan';
  List<dynamic> _questions = [];
  final Map<String, dynamic> _answers = {};
  final List<Map<String, dynamic>> _docs = [];

  bool _busy = false;
  String? _error;
  String? _userId;
  String? _devOtp;
  final _otp = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  Future<void> _loadRefData() async {
    try {} catch (_) {}
    try {
      _questions = await ApiClient.instance.get('/api/auth/questionnaire');
    } catch (_) {}
    if (mounted) setState(() {});
  }

  bool _validEmail(String e) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e);
  bool _validPhone(String p) =>
      RegExp(r'^0\d{9}$').hasMatch(p); // 07XXXXXXXX (10 digits)

  Future<void> _pickDocument(String docType) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Photos'),
              onTap: () => Navigator.pop(ctx, 'photos'),
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Choose from Files'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    String fileName;
    String mimeType;
    List<int> bytes;

    if (source == 'photos') {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image == null) return;

      fileName = image.name;
      bytes = await image.readAsBytes();

      final ext = image.name.split('.').last.toLowerCase();
      mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final f = result.files.first;
      if (f.bytes == null) return;

      fileName = f.name;
      bytes = f.bytes!;

      final ext = (f.extension ?? '').toLowerCase();

      const mimeByExt = {
        'pdf': 'application/pdf',
        'doc': 'application/msword',
        'docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
      };

      mimeType = mimeByExt[ext] ?? 'application/octet-stream';
    }

    setState(() {
      _docs.removeWhere((d) => d['docType'] == docType);

      _docs.add({
        'docType': docType,
        'fileName': fileName,
        'mimeType': mimeType,
        'dataBase64': base64Encode(bytes),
      });
    });
  }

  String? _validate() {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty)
      return 'First and last name are required';
    if (!_validEmail(_email.text.trim()))
      return 'Enter a valid email (example@abc.com)';
    if (!_validPhone(_phone.text.trim()))
      return 'Phone must be 10 digits starting with 0 (e.g. 0791234567)';
    if (_password.text.length < 8)
      return 'Password must be at least 8 characters';
    if (_nationality == null) return 'Please select your nationality';
    if (isCoach && _nationality == null)
      return 'Please select your nationality';
    return null;
  }

  Future<void> _register() async {
    final v = _validate();
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path =
          isCoach ? '/api/auth/register/coach' : '/api/auth/register/member';

      final body = {
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'password': _password.text,
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'nationality': _nationality,
      };
      final res = await ApiClient.instance.post(path, body);
      setState(() {
        _userId = res['user']['id'];
        _devOtp = res['devOtp']?.toString();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach server. Check API_BASE_URL.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await ApiClient.instance.post(
        '/api/auth/resend-verification',
        {
          'userId': _userId,
        },
      );

      if (!mounted) return;

      setState(() {
        _otp.clear();
        _devOtp = res['devOtp']?.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              res['message'] ??
                  'A new verification code has been sent to your email.',
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Cannot reach server.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verifyAndLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/api/auth/verify', {
        'userId': _userId,
        'code': _otp.text.trim(),
        'channel': 'email',
      });
      await context.read<AuthState>().login(_email.text.trim(), _password.text);
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verifying = _userId != null;
    return Scaffold(
      appBar: AppBar(title: Text(verifying ? 'Verify' : 'Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: verifying ? _verifyForm() : _registerForm()),
      ),
    );
  }

  Widget _registerForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(tr(context, 'Member'))),
          ButtonSegment(value: true, label: Text(tr(context, 'Coach')))
        ],
        selected: {isCoach},
        onSelectionChanged: (s) => setState(() => isCoach = s.first),
      ),
      const SizedBox(height: 16),
      _f(_first, 'First name'),
      _f(_last, 'Last name'),
      _f(_email, 'Email', keyboard: TextInputType.emailAddress),
      _f(_phone, 'Phone (07XXXXXXXX)', keyboard: TextInputType.phone),
      _f(_password, 'Password (min 8)', obscure: true),
      _nationalityField(),
      // (v0.14 items 1, 2) Date of birth, area, the fitness questionnaire and
      // coach documents all moved to the Complete Profile step inside the app.
      // Testers abandoned the old eight-field signup form.
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          tr(context, 'You will add a few more details after signing in.'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6)),
        ),
      ),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton(
          onPressed: _busy ? null : _register,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr(context, 'Create account'))),
    ]);
  }

  Widget _nationalityField() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: _pickNationality,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: tr(context, 'Nationality'),
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.search),
            ),
            child: Text(_nationality ?? tr(context, 'Tap to select')),
          ),
        ),
      );

  /// Searchable country picker — typing filters the list as you go.
  Future<void> _pickNationality() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(builder: (c, setS) {
          final list = kCountries
              .where((x) => x.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: tr(ctx, 'Search nationality'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setS(() => query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(list[i]),
                    trailing: list[i] == _nationality
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    onTap: () => Navigator.pop(ctx, list[i]),
                  ),
                ),
              ),
            ]),
          );
        });
      },
    );
    if (picked != null) setState(() => _nationality = picked);
  }

  List<Widget> _questionFields() {
    if (_questions.isEmpty) return [];
    return [
      Align(
          alignment: Alignment.centerLeft,
          child: Text(tr(context, 'A few quick questions'),
              style: Theme.of(context).textTheme.titleSmall)),
      const SizedBox(height: 4),
      ..._questions.map<Widget>((q) => _questionField(q)),
    ];
  }

  Widget _questionField(Map q) {
    final key = q['key'];
    final label = q['label_en'] + (q['required'] == true ? ' *' : '');
    switch (q['input_type']) {
      case 'dropdown':
        final opts = (q['options'] as List?) ?? [];
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              items: opts
                  .map<DropdownMenuItem<String>>((o) => DropdownMenuItem(
                      value: o.toString(), child: Text(o.toString())))
                  .toList(),
              onChanged: (v) => _answers[key] = v,
            ));
      case 'number':
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              onChanged: (v) => _answers[key] = num.tryParse(v),
            ));
      default:
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              onChanged: (v) => _answers[key] = v,
            ));
    }
  }

  List<Widget> _coachDocs() {
    const docTypes = {
      'degree_certificate': "Bachelor's Degree",
      'additional_certification': 'Additional Certification',
      'experience_proof': 'Proof of 2+ years experience',
    };
    return [
      Align(
          alignment: Alignment.centerLeft,
          child: Text(tr(context, 'Documents (pdf, doc, docx, jpg, png)'),
              style: Theme.of(context).textTheme.titleSmall)),
      const SizedBox(height: 4),
      ...docTypes.entries.map((e) {
        final picked =
            _docs.firstWhere((d) => d['docType'] == e.key, orElse: () => {});
        return Card(
            child: ListTile(
          dense: true,
          title: Text(e.value),
          subtitle: picked.isEmpty
              ? Text(tr(context, 'No file selected'))
              : Text(picked['fileName'],
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: TextButton.icon(
              onPressed: () => _pickDocument(e.key),
              icon: const Icon(Icons.upload_file),
              label: Text(tr(context, 'Choose'))),
        ));
      }),
      const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'You will be visible once an admin approves your account.',
              style: TextStyle(fontStyle: FontStyle.italic))),
    ];
  }

  Widget _verifyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            context,
            'Enter the verification code sent to your email.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _email.text.trim(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_devOtp != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'DEV code: $_devOtp',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 12),
        _f(
          _otp,
          'OTP code',
          keyboard: TextInputType.number,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyAndLogin,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  tr(context, 'Verify & continue'),
                ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _resendOtp,
          child: Text(
            tr(context, 'Resend OTP'),
          ),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label,
          {bool obscure = false, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: keyboard,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder())),
      );
}
