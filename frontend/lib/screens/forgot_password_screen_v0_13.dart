import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// Forgot-password flow (v0.5 item 1) for members and coaches.
/// Step 1: enter email -> a 6-char code is emailed (neutral response either way).
/// Step 2: enter the code + new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeRequested = false;
  bool _busy = false;
  String? _info;
  String? _error;

  Future<void> _requestCode() async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final res = await ApiClient.instance.post('/api/auth/forgot-password', {'email': _email.text.trim()});
      setState(() {
        _codeRequested = true;
        _info = res['message'] ?? 'If this email is registered, a reset code has been sent.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ApiClient.instance.post('/api/auth/reset-password', {
        'email': _email.text.trim(),
        'code': _code.text.trim().toUpperCase(),
        'newPassword': _password.text,
        'confirmPassword': _confirm.text,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Password reset. You can log in with your new password.'))));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Forgot password'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                _codeRequested
                    ? tr(context, 'Enter the 6-character code from your email and choose a new password.')
                    : tr(context, 'Enter your account email and we will send you a reset code.'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                enabled: !_codeRequested,
                decoration: InputDecoration(labelText: tr(context, 'Email'), border: const OutlineInputBorder()),
              ),
              if (_codeRequested) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: tr(context, 'Reset code'), border: const OutlineInputBorder(),
                      helperText: tr(context, '6 characters, expires in 10 minutes')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr(context, 'New password (min 8)'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr(context, 'Confirm new password'), border: const OutlineInputBorder()),
                ),
              ],
              if (_info != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_info!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : (_codeRequested ? _reset : _requestCode),
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_codeRequested ? tr(context, 'Reset password') : tr(context, 'Send code')),
              ),
              if (_codeRequested)
                TextButton(
                  onPressed: _busy ? null : _requestCode,
                  child: Text(tr(context, 'Send a new code')),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
