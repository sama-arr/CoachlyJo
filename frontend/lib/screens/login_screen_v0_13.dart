import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_v0_13.dart';
import '../core/auth_state_v0_13.dart';
import '../core/version_v0_13.dart';
import 'register_screen_v0_13.dart';
import 'forgot_password_screen_v0_13.dart';
import '../core/theme_v0_13.dart';
import '../core/motion_v0_13.dart';
import 'account_v0_13.dart';
import '../core/i18n_v0_13.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_email.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Cannot reach server. Check API_BASE_URL.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppLang>();
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: () => lang.toggle(),
            icon: const Icon(Icons.language, size: 18),
            label: Text(lang.isAr ? 'English' : 'عربي'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GlowBackground(
          child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // v0.6 CoachlyJo branding: gradient wordmark + tagline.
                // (v0.8) Wordmark on a glowing brand halo.
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Brand.magenta.withValues(alpha: 0.22),
                          Brand.orange.withValues(alpha: 0.14),
                        ],
                      ),
                      border: Border.all(
                          color: Brand.magenta.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                            color: Brand.magenta.withValues(alpha: 0.25),
                            blurRadius: 30,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: const CoachlyWordmark(fontSize: 46),
                  ),
                ),
                const SizedBox(height: 10),
                Text(tr(context, 'Train with the right coach.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF9A9AA6), letterSpacing: 0.2)),
                const SizedBox(height: 32),
                TextField(
                    controller: _email,
                    decoration: InputDecoration(
                        labelText: tr(context, 'Email'),
                        border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: tr(context, 'Password'),
                        border: const OutlineInputBorder())),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                GradientButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(tr(context, 'Log in')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen())),
                  child: Text(tr(context, 'Create an account')),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen())),
                  child: Text(tr(context, 'Forgot password?')),
                ),
                // (v0.13) Reviewers open the policy before signing in, and
                // both stores expect it reachable from the app itself.
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(
                              const LegalScreen(onlyKey: 'legal_privacy'))),
                      child: Text(tr(context, 'Privacy Policy'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(
                              const LegalScreen(onlyKey: 'legal_terms'))),
                      child: Text(tr(context, 'Terms of Service'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                Text('${Brand.appName} $appVersion',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      )),
    );
  }
}
