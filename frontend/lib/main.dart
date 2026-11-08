import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/auth_state_v0_13.dart';
import 'core/theme_v0_13.dart';
import 'core/i18n_v0_13.dart';
import 'core/push_v0_13.dart';
import 'screens/login_screen_v0_13.dart';
import 'screens/member_home_v0_13.dart';
import 'screens/coach_home_v0_13.dart';
import 'screens/admin_home_v0_13.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // (v0.14 item 13) Fails soft when Firebase is not configured yet.
  await PushService.instance.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()..loadFromStorage()),
        ChangeNotifierProvider(create: (_) => AppLang()..load()),
        ChangeNotifierProvider(create: (_) => AppTheme()..load()),
      ],
      child: const FitnessApp(),
    ),
  );
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    // v0.6: CoachlyJo brand — dark theme, magenta #F20FB6 + orange #FF770F on
    // near-black. Role accents are applied per-home in _Root below.
    // v0.7: locale follows the language switch (English / Arabic with RTL).
    final lang = context.watch<AppLang>();
    // (v0.14 item 12) The user picks system / light / dark in Settings.
    final theme = context.watch<AppTheme>();
    return MaterialApp(
      locale: Locale(lang.code),
      title: Brand.appName,
      debugShowCheckedModeBanner: false,
      theme: coachlyTheme(brightness: Brightness.light),
      darkTheme: coachlyTheme(brightness: Brightness.dark),
      themeMode: theme.themeMode,
      // Arabic + English support incl. RTL (spec §16.1).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: const _Root(),
    );
  }
}

/// Routes to the right home based on auth + role.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.isLoggedIn) return const LoginScreen();
    // Subtle role identity: members lean magenta, coaches lean orange,
    // admin keeps the neutral dual-brand look.
    switch (auth.role) {
      case 'member':
        return Builder(builder: (ctx) => Theme(
              data: coachlyTheme(
                  accent: Brand.magenta, brightness: Theme.of(ctx).brightness),
              child: const MemberHome(),
            ));
      case 'coach':
        return Builder(builder: (ctx) => Theme(
              data: coachlyTheme(
                  accent: Brand.orange, brightness: Theme.of(ctx).brightness),
              child: const CoachHome(),
            ));
      case 'admin':
        return const AdminHome();
      default:
        return const LoginScreen();
    }
  }
}
