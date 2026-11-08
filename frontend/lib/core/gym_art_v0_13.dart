import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme_v0_13.dart';

/// =============================================================================
/// CoachlyJo gym illustrations (v0.14 item 19).
///
/// Vector art drawn with CustomPainter rather than bundled images:
///   * no licensing questions, no photo credits, nothing to replace later;
///   * every piece uses the brand gradient, so it recolours itself when the
///     user switches between light and dark;
///   * a few KB of code instead of megabytes of PNGs in the app bundle.
///
/// Used on the home page, empty states and the profile-completion screens to
/// make the app look like a gym product rather than a form.
/// =============================================================================

enum GymArt { dumbbell, kettlebell, athlete, trophy, heartRate, stopwatch }

class GymIllustration extends StatelessWidget {
  final GymArt art;
  final double size;
  /// 0..1 — how strong the art reads against the background.
  final double opacity;
  const GymIllustration({super.key, required this.art, this.size = 120, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GymPainter(art: art, light: light, opacity: opacity),
      ),
    );
  }
}

class _GymPainter extends CustomPainter {
  final GymArt art;
  final bool light;
  final double opacity;
  _GymPainter({required this.art, required this.light, required this.opacity});

  Shader _brandShader(Rect r) => Brand.gradientFor(light ? Brightness.light : Brightness.dark)
      .createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = _brandShader(rect);
    final fill = Paint()..shader = _brandShader(rect);
    canvas.saveLayer(rect, Paint()..color = Colors.white.withValues(alpha: opacity));

    switch (art) {
      case GymArt.dumbbell:
        _dumbbell(canvas, size, stroke, fill);
        break;
      case GymArt.kettlebell:
        _kettlebell(canvas, size, stroke);
        break;
      case GymArt.athlete:
        _athlete(canvas, size, stroke, fill);
        break;
      case GymArt.trophy:
        _trophy(canvas, size, stroke, fill);
        break;
      case GymArt.heartRate:
        _heartRate(canvas, size, stroke);
        break;
      case GymArt.stopwatch:
        _stopwatch(canvas, size, stroke, fill);
        break;
    }
    canvas.restore();
  }

  // ---- dumbbell: two plates on a bar, drawn on a slight diagonal ------------
  void _dumbbell(Canvas canvas, Size s, Paint stroke, Paint fill) {
    canvas.save();
    canvas.translate(s.width / 2, s.height / 2);
    canvas.rotate(-math.pi / 9);
    canvas.translate(-s.width / 2, -s.height / 2);

    final cy = s.height * 0.5;
    final barW = s.width * 0.30;
    // bar
    canvas.drawLine(Offset(s.width * 0.35, cy), Offset(s.width * 0.65, cy),
        Paint()..shader = stroke.shader..strokeWidth = s.width * 0.075..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    // inner collars
    for (final x in [0.32, 0.68]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(s.width * x, cy), width: s.width * 0.055, height: s.height * 0.30),
          Radius.circular(s.width * 0.02)),
        fill);
    }
    // outer plates
    for (final x in [0.22, 0.78]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(s.width * x, cy), width: s.width * 0.11, height: s.height * 0.46),
          Radius.circular(s.width * 0.035)),
        fill);
    }
    canvas.restore();
    // motion lines
    final line = Paint()
      ..shader = stroke.shader
      ..strokeWidth = s.width * 0.022
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s.width * 0.10, s.height * 0.22), Offset(s.width * 0.24, s.height * 0.22), line);
    canvas.drawLine(Offset(s.width * 0.76, s.height * 0.80), Offset(s.width * 0.90, s.height * 0.80), line);
  }

  // ---- kettlebell -----------------------------------------------------------
  void _kettlebell(Canvas canvas, Size s, Paint stroke) {
    final handle = Path()
      ..moveTo(s.width * 0.34, s.height * 0.44)
      ..cubicTo(s.width * 0.30, s.height * 0.16, s.width * 0.70, s.height * 0.16,
                s.width * 0.66, s.height * 0.44);
    canvas.drawPath(handle, stroke);

    final body = Path()
      ..moveTo(s.width * 0.34, s.height * 0.44)
      ..cubicTo(s.width * 0.10, s.height * 0.60, s.width * 0.14, s.height * 0.90,
                s.width * 0.50, s.height * 0.90)
      ..cubicTo(s.width * 0.86, s.height * 0.90, s.width * 0.90, s.height * 0.60,
                s.width * 0.66, s.height * 0.44);
    canvas.drawPath(body, stroke);
  }

  // ---- athlete mid-lift -----------------------------------------------------
  void _athlete(Canvas canvas, Size s, Paint stroke, Paint fill) {
    // head
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.22), s.width * 0.085, fill);
    // torso
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.32), Offset(s.width * 0.50, s.height * 0.58), stroke);
    // arms raised holding a bar
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.40), Offset(s.width * 0.30, s.height * 0.26), stroke);
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.40), Offset(s.width * 0.70, s.height * 0.26), stroke);
    canvas.drawLine(Offset(s.width * 0.22, s.height * 0.22), Offset(s.width * 0.78, s.height * 0.22),
        Paint()..shader = stroke.shader..strokeWidth = s.width * 0.040..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    // legs in a squat
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.58), Offset(s.width * 0.34, s.height * 0.74), stroke);
    canvas.drawLine(Offset(s.width * 0.34, s.height * 0.74), Offset(s.width * 0.34, s.height * 0.88), stroke);
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.58), Offset(s.width * 0.66, s.height * 0.74), stroke);
    canvas.drawLine(Offset(s.width * 0.66, s.height * 0.74), Offset(s.width * 0.66, s.height * 0.88), stroke);
  }

  // ---- trophy (goals reached) ----------------------------------------------
  void _trophy(Canvas canvas, Size s, Paint stroke, Paint fill) {
    final cup = Path()
      ..moveTo(s.width * 0.32, s.height * 0.20)
      ..lineTo(s.width * 0.68, s.height * 0.20)
      ..lineTo(s.width * 0.64, s.height * 0.50)
      ..cubicTo(s.width * 0.62, s.height * 0.60, s.width * 0.38, s.height * 0.60,
                s.width * 0.36, s.height * 0.50)
      ..close();
    canvas.drawPath(cup, fill);
    // handles
    canvas.drawArc(Rect.fromLTWH(s.width * 0.16, s.height * 0.22, s.width * 0.20, s.height * 0.22),
        -math.pi / 2, math.pi, false, stroke);
    canvas.drawArc(Rect.fromLTWH(s.width * 0.64, s.height * 0.22, s.width * 0.20, s.height * 0.22),
        math.pi / 2, -math.pi, false, stroke);
    // stem + base
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.58), Offset(s.width * 0.50, s.height * 0.72), stroke);
    canvas.drawLine(Offset(s.width * 0.34, s.height * 0.80), Offset(s.width * 0.66, s.height * 0.80), stroke);
  }

  // ---- heart-rate trace (progress) -----------------------------------------
  void _heartRate(Canvas canvas, Size s, Paint stroke) {
    final p = Path()
      ..moveTo(s.width * 0.08, s.height * 0.52)
      ..lineTo(s.width * 0.30, s.height * 0.52)
      ..lineTo(s.width * 0.38, s.height * 0.30)
      ..lineTo(s.width * 0.48, s.height * 0.74)
      ..lineTo(s.width * 0.58, s.height * 0.44)
      ..lineTo(s.width * 0.66, s.height * 0.52)
      ..lineTo(s.width * 0.92, s.height * 0.52);
    canvas.drawPath(p, stroke);
  }

  // ---- stopwatch (session timing) ------------------------------------------
  void _stopwatch(Canvas canvas, Size s, Paint stroke, Paint fill) {
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.56), s.width * 0.30, stroke);
    canvas.drawLine(Offset(s.width * 0.42, s.height * 0.16), Offset(s.width * 0.58, s.height * 0.16), stroke);
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.16), Offset(s.width * 0.50, s.height * 0.26), stroke);
    // hands
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.56), Offset(s.width * 0.50, s.height * 0.38), stroke);
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.56), Offset(s.width * 0.64, s.height * 0.62), stroke);
    canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.56), s.width * 0.035, fill);
  }

  @override
  bool shouldRepaint(covariant _GymPainter old) =>
      old.art != art || old.light != light || old.opacity != opacity;
}

/// Wide decorative banner: a gym scene behind a gradient wash, used at the top
/// of the home page so the first screen looks like a fitness app.
class GymBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final GymArt art;
  const GymBanner({super.key, required this.title, this.subtitle, this.art = GymArt.dumbbell});

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [
                  Brand.magentaLight.withValues(alpha: 0.12),
                  Brand.orangeLight.withValues(alpha: 0.08),
                  Brand.surfaceLight,
                ]
              : [
                  Brand.magenta.withValues(alpha: 0.26),
                  Brand.orange.withValues(alpha: 0.16),
                  Brand.surface.withValues(alpha: 0.92),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (light ? Brand.magentaLight : Brand.magenta).withValues(alpha: light ? 0.18 : 0.28),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: light ? Brand.mutedLight : const Color(0xFFCFCFDA))),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        GymIllustration(art: art, size: 86, opacity: light ? 0.85 : 0.95),
      ]),
    );
  }
}
