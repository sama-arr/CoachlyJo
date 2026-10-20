import 'package:flutter/material.dart';
import '../core/api_v0_13.dart';
import '../core/i18n_v0_13.dart';

/// Forgot-password flow:
/// Step 1: enter email -> request reset code.
/// Step 2: enter OTP -> verify OTP with backend.
/// Step 3: after OTP is verified, open a separate page to set the new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _codeRequested = false;
  bool _busy = false;

  String? _info;
  String? _error;

  Future<void> _requestCode() async {
    final email = _email.text.trim();

    if (email.isEmpty) {
      setState(() => _error = tr(context, 'Please enter your email.'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      final res = await ApiClient.instance.post(
        '/api/auth/forgot-password',
        {
          'email': email,
        },
      );

      if (!mounted) return;

      setState(() {
        _codeRequested = true;
        _code.clear();
        _info = res['message'] ??
            'If this email is registered, a reset code has been sent.';
      });
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

  Future<void> _verifyCode() async {
    final email = _email.text.trim();
    final code = _code.text.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() => _error = tr(context, 'Please enter the reset code.'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      final res = await ApiClient.instance.post(
        '/api/auth/verify-reset-code',
        {
          'email': email,
          'code': code,
        },
      );

      final resetToken = res['resetToken']?.toString();

      if (resetToken == null || resetToken.isEmpty) {
        throw ApiException(500, 'Could not verify reset code.');
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _NewPasswordScreen(
            resetToken: resetToken,
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

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Forgot password')),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _codeRequested
                      ? tr(
                          context,
                          'Enter the 6-character code sent to your email.',
                        )
                      : tr(
                          context,
                          'Enter your account email and we will send you a reset code.',
                        ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_codeRequested,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Email'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: tr(context, 'Reset code'),
                      border: const OutlineInputBorder(),
                      helperText:
                          tr(context, '6 characters, expires in 10 minutes'),
                    ),
                  ),
                ],
                if (_info != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _info!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : (_codeRequested ? _verifyCode : _requestCode),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _codeRequested
                              ? tr(context, 'Verify code')
                              : tr(context, 'Send code'),
                        ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _requestCode,
                    child: Text(tr(context, 'Send a new code')),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _codeRequested = false;
                              _code.clear();
                              _info = null;
                              _error = null;
                            });
                          },
                    child: Text(tr(context, 'Change email')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separate page shown only after the OTP has been successfully verified.
class _NewPasswordScreen extends StatefulWidget {
  final String resetToken;

  const _NewPasswordScreen({
    required this.resetToken,
  });

  @override
  State<_NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<_NewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  String? _error;

  Future<void> _resetPassword() async {
    if (_password.text.length < 8) {
      setState(() {
        _error = tr(
          context,
          'New password must be at least 8 characters.',
        );
      });
      return;
    }

    if (_password.text != _confirm.text) {
      setState(() {
        _error = tr(
          context,
          'New password and confirmation do not match.',
        );
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ApiClient.instance.post(
        '/api/auth/reset-password',
        {
          'resetToken': widget.resetToken,
          'newPassword': _password.text,
          'confirmPassword': _confirm.text,
        },
      );

      if (!mounted) return;

      // Remove both password-reset pages and return to login.
      Navigator.of(context).pop();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Password reset. You can log in with your new password.',
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

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Create new password')),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    context,
                    'Your reset code has been verified. Choose your new password.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: _hidePassword,
                  decoration: InputDecoration(
                    labelText: tr(context, 'New password'),
                    helperText: tr(context, 'Minimum 8 characters'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },
                      icon: Icon(
                        _hidePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _hideConfirm,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Confirm new password'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _hideConfirm = !_hideConfirm;
                        });
                      },
                      icon: Icon(
                        _hideConfirm ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(tr(context, 'Update password')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
