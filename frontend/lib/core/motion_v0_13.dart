import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme_v0_13.dart';

/// =============================================================================
/// CoachlyJo motion & interaction kit (v0.10 item 4).
///
/// Small, dependency-free widgets that make the app feel alive:
///   * FadeInUp        — staggered entrance for list items
///   * AnimatedCounter — hero numbers count up instead of snapping
///   * ProgressRing    — classes used vs remaining at a glance
///   * SkeletonBox/List— shimmer placeholders instead of a bare spinner
///   * PressableCard   — scale + haptic feedback on tap
///   * fadeSlideRoute  — consistent page transitions
/// =============================================================================

/// Entrance animation: fades and slides content up. `index` staggers a list
/// so items arrive in sequence rather than all at once.
class FadeInUp extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  const FadeInUp({super.key, required this.child, this.index = 0,
      this.duration = const Duration(milliseconds: 340)});
  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    // Cap the stagger so long lists don't crawl in.
    final delay = Duration(milliseconds: math.min(widget.index, 8) * 45);
    Future.delayed(delay, () { if (mounted) _c.forward(); });
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
}

/// Counts up to [value] when it first appears or changes.
class AnimatedCounter extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  const AnimatedCounter({super.key, required this.value, this.style, this.prefix = '', this.suffix = ''});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// Circular progress ring — used for classes used vs total on a package.
class ProgressRing extends StatelessWidget {
  final int used;
  final int total;
  final double size;
  final Color? color;
  const ProgressRing({super.key, required this.used, required this.total, this.size = 58, this.color});
  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1 : total;
    final pct = (used / safeTotal).clamp(0.0, 1.0);
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: size * 0.09,
              backgroundColor: const Color(0xFF2A2A34),
              valueColor: AlwaysStoppedAnimation<Color>(c),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${total - used}',
                style: TextStyle(fontSize: size * 0.28, fontWeight: FontWeight.w800, height: 1)),
            Text('left', style: TextStyle(fontSize: size * 0.16, color: const Color(0xFF9A9AA6))),
          ]),
        ]),
      ),
    );
  }
}

/// Shimmering placeholder block.
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBox({super.key, this.height = 14, this.width, this.radius = 8});
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: const [Color(0xFF1A1A21), Color(0xFF26262F), Color(0xFF1A1A21)],
            ),
          ),
        );
      },
    );
  }
}

/// A few skeleton cards — shown while a list loads.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: count,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF23232C)),
        ),
        child: Row(children: [
          const SkeletonBox(height: 44, width: 44, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              SkeletonBox(height: 13, width: 140),
              SizedBox(height: 8),
              SkeletonBox(height: 11, width: 90),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Card that scales slightly and gives haptic feedback when pressed.
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PressableCard({super.key, required this.child, this.onTap});
  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null ? null : () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Page transition used across the app: fade + a small upward slide.
Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
