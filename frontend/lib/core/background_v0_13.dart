import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_v0_13.dart';

/// =============================================================================
/// CoachlyJo animated background (v0.11 item 3).
///
/// Replaces the two static circles with a layered, slowly drifting scene:
///
///   1. deep base colour
///   2. five soft aurora blobs of different size/hue, each drifting on its own
///      slow elliptical path (28-second loop, deliberately barely perceptible)
///   3. two faint diagonal light streaks for depth
///   4. a very subtle grid, so large empty areas do not look flat
///   5. a fitness motif: a slow heartbeat/pulse line sweeping across the lower
///      third — the "alive" signature of the app
///
/// Everything is painted in ONE CustomPainter driven by a single ticker, so the
/// cost is one repaint per frame of simple shapes: no images, no shaders, no
/// extra packages. Motion respects the platform "reduce motion" setting.
/// =============================================================================
class GlowBackground extends StatefulWidget {
  final Widget child;
  /// Set false for a completely static background (used behind dialogs).
  final bool animate;
  const GlowBackground({super.key, required this.child, this.animate = true});

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" accessibility setting.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion && _c.isAnimating) _c.stop();

    final accent = Theme.of(context).colorScheme.primary;
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _AuroraPainter(
                t: reduceMotion ? 0.15 : _c.value,
                accent: accent,
                light: Theme.of(context).brightness == Brightness.light,
              ),
              isComplex: true,
              willChange: !reduceMotion,
            ),
          ),
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  /// 0..1 loop position.
  final double t;
  final Color accent;
  final bool light;
  _AuroraPainter({required this.t, required this.accent, required this.light});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final tau = math.pi * 2;

    // ---- 1. base ----
    // (v0.14 item 12) The aurora is far subtler on a light background: the same
    // blobs at full strength would look like smudges on white.
    canvas.drawRect(Offset.zero & size,
        Paint()..color = light ? Brand.backgroundLight : Brand.background);
    final intensity = light ? 0.35 : 1.0;

    // ---- 2. drifting aurora blobs ----
    // Each blob: base position, radius, colour, and its own phase/speed so the
    // scene never visibly repeats a pattern.
    final blobs = <_Blob>[
      _Blob(cx: 0.16, cy: 0.10, r: 0.62, color: Brand.magenta, alpha: 0.30, phase: 0.00, ampX: 0.05, ampY: 0.035),
      _Blob(cx: 0.88, cy: 0.82, r: 0.66, color: Brand.orange, alpha: 0.26, phase: 0.35, ampX: 0.045, ampY: 0.04),
      _Blob(cx: 0.82, cy: 0.16, r: 0.42, color: accent, alpha: 0.16, phase: 0.60, ampX: 0.06, ampY: 0.03),
      _Blob(cx: 0.10, cy: 0.72, r: 0.46, color: Brand.magentaPure, alpha: 0.13, phase: 0.18, ampX: 0.04, ampY: 0.05),
      _Blob(cx: 0.50, cy: 0.46, r: 0.55, color: Brand.orangePure, alpha: 0.09, phase: 0.78, ampX: 0.07, ampY: 0.045),
    ];

    for (final b in blobs) {
      final angle = (t + b.phase) * tau;
      final cx = (b.cx + math.cos(angle) * b.ampX) * w;
      final cy = (b.cy + math.sin(angle * 0.8) * b.ampY) * h;
      final radius = b.r * math.max(w, h) * 0.55;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withValues(alpha: b.alpha * intensity),
            b.color.withValues(alpha: b.alpha * 0.45 * intensity),
            b.color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }

    // ---- 3. diagonal light streaks ----
    for (var i = 0; i < 2; i++) {
      final shift = ((t + i * 0.5) % 1.0) * 1.6 - 0.3;
      final x = shift * w;
      final streak = Path()
        ..moveTo(x, -h * 0.1)
        ..lineTo(x + w * 0.22, -h * 0.1)
        ..lineTo(x - w * 0.14, h * 1.1)
        ..lineTo(x - w * 0.36, h * 1.1)
        ..close();
      canvas.drawPath(
        streak,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (light ? Colors.black : Colors.white).withValues(alpha: light ? 0.010 : 0.018),
              (light ? Colors.black : Colors.white).withValues(alpha: 0.004),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }

    // ---- 4. subtle grid ----
    final grid = Paint()
      ..color = (light ? Colors.black : Colors.white).withValues(alpha: light ? 0.022 : 0.014)
      ..strokeWidth = 1;
    const step = 46.0;
    for (double x = 0; x < w; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (double y = 0; y < h; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // (v0.14 item 18) The heartbeat motif was removed — testers found it
    // distracting. Gym imagery now lives in the content itself (see
    // gym_art_v0_13.dart) rather than animating behind every screen.
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.t != t || old.accent != accent || old.light != light;
}

class _Blob {
  final double cx, cy, r, alpha, phase, ampX, ampY;
  final Color color;
  const _Blob({
    required this.cx,
    required this.cy,
    required this.r,
    required this.color,
    required this.alpha,
    required this.phase,
    required this.ampX,
    required this.ampY,
  });
}
