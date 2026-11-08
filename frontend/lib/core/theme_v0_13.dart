import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'motion_v0_13.dart';
import 'api_v0_13.dart';
export 'background_v0_13.dart';

/// =============================================================================
/// CoachlyJo brand theme (v0.6).
///
/// Palette (client-specified):
///   magenta  #F20FB6  — primary brand color
///   orange   #FF770F  — secondary brand color
///   background: near-black #0B0B0F (pure black flattens depth; cards float
///   on #16161C surfaces).
///
/// Design language:
///   * One signature magenta→orange gradient, used SPARINGLY where it counts:
///     the CoachlyJo wordmark, primary CTAs, selected states and stat accents.
///     Everything else stays calm so the gradient pops.
///   * Subtle role accenting: member screens lean magenta, coach screens lean
///     orange, admin stays neutral with both. Same app, per-side identity.
/// =============================================================================

class Brand {
  /// Brand colors as specified by the client.
  static const magentaPure = Color(0xFFF20FB6);
  static const orangePure = Color(0xFFFF770F);

  /// (v0.10) Slightly dimmed working tones — the pure colors were too hot on
  /// large surfaces. Same hues, lower luminance/saturation, so the brand still
  /// reads but long sessions stay comfortable. The pure colors remain
  /// available for small accents (icons, the wordmark gradient).
  static const magenta = Color(0xFFC91E97);
  static const orange = Color(0xFFD9700F);
  static const background = Color(0xFF0A0A0E);
  static const surface = Color(0xFF15151B);
  static const surfaceHigh = Color(0xFF1D1D25);

  static const gradient = LinearGradient(
    colors: [magenta, orange],  // dimmed working tones
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Full-strength gradient, used sparingly (wordmark, icon badges).
  static const gradientVivid = LinearGradient(
    colors: [magentaPure, orangePure],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const appName = 'CoachlyJo';

  // ---- (v0.14 item 12) Light palette ----------------------------------------
  // The brand hues are darkened for light mode: #C91E97 on white is readable,
  // but the orange needs taking down or it vibrates against pale surfaces.
  static const magentaLight = Color(0xFFB01485);
  static const orangeLight = Color(0xFFB85C06);
  static const backgroundLight = Color(0xFFF7F6F9);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceHighLight = Color(0xFFF0EEF4);
  static const onSurfaceLight = Color(0xFF1B1B22);
  static const mutedLight = Color(0xFF6B6B7A);

  /// Brand gradient for the active brightness.
  static LinearGradient gradientFor(Brightness b) => b == Brightness.light
      ? const LinearGradient(
          colors: [magentaLight, orangeLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight)
      : gradient;
}

/// Builds the CoachlyJo dark theme with the given accent as primary.
/// member -> magenta, coach -> orange, admin/login -> magenta primary with
/// orange secondary (the neutral "both" identity).
ThemeData coachlyTheme({Color accent = Brand.magenta, Brightness brightness = Brightness.dark}) {
  if (brightness == Brightness.light) return _coachlyLightTheme(accent);
  final secondary = accent == Brand.orange ? Brand.magenta : Brand.orange;
  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    surface: Brand.surface,
    onSurface: const Color(0xFFEDEDF2),
    surfaceContainerHighest: Brand.surfaceHigh,
    secondaryContainer: accent.withValues(alpha: 0.18),
    onSecondaryContainer: const Color(0xFFF5E9F1),
    error: const Color(0xFFFF5470),
    outline: const Color(0xFF3A3A46),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFEDEDF2)),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.surface,
      indicatorColor: accent.withValues(alpha: 0.32),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? accent : const Color(0xFF9A9AA6),
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        color: states.contains(WidgetState.selected) ? accent : const Color(0xFF9A9AA6),
      )),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.22) : Brand.surface),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : const Color(0xFF9A9AA6)),
        side: WidgetStateProperty.all(const BorderSide(color: Color(0xFF3A3A46))),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.surfaceHigh,
      side: const BorderSide(color: Color(0xFF2A2A34)),
      labelStyle: const TextStyle(color: Color(0xFFEDEDF2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A46)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A46)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Brand.surfaceHigh,
      contentTextStyle: TextStyle(color: Color(0xFFEDEDF2)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF23232C)),
    listTileTheme: const ListTileThemeData(iconColor: Color(0xFFB9B9C6)),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: Color(0xFFB9B9C6),
      collapsedIconColor: Color(0xFF9A9AA6),
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

/// The CoachlyJo wordmark: brand-gradient text. Use on login and headers.
class CoachlyWordmark extends StatelessWidget {
  final double fontSize;
  const CoachlyWordmark({super.key, this.fontSize = 40});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => Brand.gradientVivid.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        Brand.appName,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Primary CTA with the signature gradient. Falls back to a disabled grey
/// fill when onPressed is null.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? Brand.gradient : null,
        color: enabled ? null : const Color(0xFF2A2A34),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: padding,
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: enabled ? Colors.white : const Color(0xFF6E6E7A),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin gradient underline accent — used under section titles for brand touch.
class GradientRule extends StatelessWidget {
  final double width;
  const GradientRule({super.key, this.width = 42});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// NOTE (v0.11): GlowBackground moved to background_v0_13.dart, where it became
// an animated aurora scene. It is re-exported here so existing imports of
// theme_v0_13.dart keep working unchanged.

/// (v0.7 item 1) Section header with a soft gradient wash + accent rule —
/// gives each tab a colored identity zone without a heavy app bar.
class BrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const BrandHeader({super.key, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Brand.magenta.withValues(alpha: 0.14),
            Brand.orange.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        const GradientRule(width: 56),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA6))),
          ),
      ]),
    );
  }
}

/// (v0.7 item 1) Status edge: a 4px colored strip on the start side of a card.
class StatusEdgeCard extends StatelessWidget {
  final Color color;
  final Widget child;
  const StatusEdgeCard({super.key, required this.color, required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}

// =============================================================================
// v0.8 — richer visual language. v0.7 kept the brand too quiet; these widgets
// put real color into the surfaces people look at most, while keeping text
// contrast high on the dark base.
// =============================================================================

/// Gradient-filled rounded icon badge — used as the visual anchor of section
/// headers, settings rows and empty states.
class GradientIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  const GradientIconBadge({super.key, required this.icon, this.size = 38});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(color: Brand.magenta.withValues(alpha: 0.24), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Hero panel: the top-of-screen summary block. Deep gradient wash, brand
/// border and a soft glow — the first thing the eye lands on.
class HeroPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget? child;
  const HeroPanel({super.key, required this.title, this.subtitle, this.icon, this.trailing, this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Brand.magenta.withValues(alpha: 0.22),
            Brand.orange.withValues(alpha: 0.14),
            Brand.surface.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.magenta.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(color: Brand.magenta.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[GradientIconBadge(icon: icon!), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: Color(0xFFCFCFDA))),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        if (child != null) Padding(padding: const EdgeInsets.only(top: 14), child: child!),
      ]),
    );
  }
}

/// A big number + label pill used inside HeroPanel (remaining classes etc).
class HeroStat extends StatelessWidget {
  final String value;
  final String label;
  /// (v0.10) When the value is numeric, count up to it instead of snapping.
  final bool animate;
  const HeroStat({super.key, required this.value, required this.label, this.animate = false});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(children: [
          if (animate && num.tryParse(value) != null)
            AnimatedCounter(
              value: num.parse(value),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
            )
          else
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFFCFCFDA))),
        ]),
      ),
    );
  }
}

/// Card with a gradient-tinted surface — for content cards that deserve more
/// presence than the flat surface (coach cards, package cards).
class BrandCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  const BrandCard({
    super.key,
    required this.child,
    this.accent,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final a = accent ?? Theme.of(context).colorScheme.primary;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a.withValues(alpha: 0.14), Brand.surface, Brand.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.withValues(alpha: 0.28)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

/// Avatar with a gradient ring — gives coaches/members a branded identity.
class GradientAvatar extends StatelessWidget {
  final String initials;
  final double size;
  const GradientAvatar({super.key, required this.initials, this.size = 46});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
      child: Container(
        decoration: const BoxDecoration(color: Brand.surface, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.34, color: Colors.white),
        ),
      ),
    );
  }
}

/// Colored status pill (replaces the flat grey Chip).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Empty-state block with a gradient badge — replaces bare grey text.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  /// (v0.14 item 19) Optional gym illustration instead of a plain icon badge.
  final Widget? art;
  const EmptyState({super.key, required this.icon, required this.message, this.art});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(children: [
        art ?? GradientIconBadge(icon: icon, size: 56),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).brightness == Brightness.light
                    ? Brand.mutedLight : const Color(0xFF9A9AA6),
                height: 1.4)),
      ]),
    );
  }
}

// =============================================================================
// (v0.14 item 12) Light theme.
//
// Not a tinted copy of the dark one: surfaces, borders, muted text and the
// brand tones are all chosen for contrast on white. The same widgets
// (HeroPanel, BrandCard, StatusPill…) read their colours from the active
// ColorScheme, so both themes stay in step as screens change.
// =============================================================================
ThemeData _coachlyLightTheme(Color accent) {
  // Map the dark working tones onto their light-mode equivalents.
  final a = accent == Brand.orange ? Brand.orangeLight : Brand.magentaLight;
  final secondary = accent == Brand.orange ? Brand.magentaLight : Brand.orangeLight;

  final scheme = ColorScheme.light(
    primary: a,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    surface: Brand.surfaceLight,
    onSurface: Brand.onSurfaceLight,
    surfaceContainerHighest: Brand.surfaceHighLight,
    secondaryContainer: a.withValues(alpha: 0.10),
    onSecondaryContainer: Brand.onSurfaceLight,
    error: const Color(0xFFC62348),
    outline: const Color(0xFFD6D3DE),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.backgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: Brand.onSurfaceLight),
      iconTheme: IconThemeData(color: Brand.onSurfaceLight),
    ),
    cardTheme: CardThemeData(
      color: Brand.surfaceLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: a.withValues(alpha: 0.14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.surfaceLight,
      indicatorColor: a.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? a : Brand.mutedLight,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? a : Brand.mutedLight,
          )),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: a,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? a.withValues(alpha: 0.12) : Brand.surfaceLight),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? a : Brand.mutedLight),
        side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFD6D3DE))),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.surfaceHighLight,
      side: const BorderSide(color: Color(0xFFD6D3DE)),
      labelStyle: const TextStyle(color: Brand.onSurfaceLight),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD6D3DE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD6D3DE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: a, width: 1.6),
      ),
      labelStyle: const TextStyle(color: Brand.mutedLight),
      hintStyle: const TextStyle(color: Brand.mutedLight),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surfaceLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF2A2A34),
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE6E3EC)),
    listTileTheme: const ListTileThemeData(iconColor: Brand.mutedLight),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: Brand.mutedLight,
      collapsedIconColor: Brand.mutedLight,
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

/// (v0.14 item 12) Theme choice: system, light or dark. Saved per device and
/// mirrored to the account so it follows the user to a new phone.
class AppTheme extends ChangeNotifier {
  static const _key = 'coachlyjo_theme';
  String mode = 'dark';   // 'system' | 'light' | 'dark'

  ThemeMode get themeMode => mode == 'light'
      ? ThemeMode.light
      : mode == 'system'
          ? ThemeMode.system
          : ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = prefs.getString(_key) ?? 'dark';
    notifyListeners();
  }

  Future<void> set(String m, {bool syncToServer = true}) async {
    if (!['system', 'light', 'dark'].contains(m)) return;
    mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m);
    if (syncToServer) {
      // Best effort: the local choice is what the app renders from.
      try {
        await ApiClient.instance.put('/api/profile/theme', {'theme': m});
      } catch (_) {}
    }
  }
}
