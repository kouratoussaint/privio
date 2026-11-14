import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';

/// Lot 7.2b2 : animations de la discussion.

/// Coches de distribution qui se dessinent (une : envoyé ; deux : reçu ou lu).
class AnimatedTicks extends StatelessWidget {
  const AnimatedTicks({super.key, required this.twice, required this.color, this.size = 14});

  final bool twice;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // Une nouvelle coche (ou un changement de couleur : lu) redessine le tracé.
    key: ValueKey('$twice$color'),
    tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
    duration: Motion.of(context, Motion.medium),
    curve: Curves.easeOut,
    builder: (_, t, _) => CustomPaint(
      size: Size(size * (twice ? 1.35 : 1), size),
      painter: _TicksPainter(progress: t, twice: twice, color: color),
    ),
  );
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.progress, required this.twice, required this.color});

  final double progress;
  final bool twice;
  final Color color;

  Path _check(double dx, double h) => Path()
    ..moveTo(dx + h * 0.12, h * 0.55)
    ..lineTo(dx + h * 0.38, h * 0.8)
    ..lineTo(dx + h * 0.9, h * 0.22);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paths = [_check(0, h), if (twice) _check(h * 0.42, h)];
    for (final (i, path) in paths.indexed) {
      // La seconde coche suit la première.
      final local = twice ? ((progress - i * 0.35) / 0.65).clamp(0.0, 1.0) : progress;
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * local), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) =>
      old.progress != progress || old.twice != twice || old.color != color;
}

/// Trois points qui sautillent (« en train d'écrire »).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color, this.size = 4});

  final Color color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin, LoopingAnimation {
  @override
  Duration get loopDuration => const Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: loop,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(right: widget.size * 0.6),
            child: Transform.translate(
              offset: Offset(
                0,
                -widget.size * 0.9 * math.max(0, math.sin((loop.value - i * 0.15) * 2 * math.pi)),
              ),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Bulle qui s'efface : dissolution douce (message expiré, discussion vidée, supprimé chez
/// moi), puis la place se referme.
class DissolveOut extends StatefulWidget {
  const DissolveOut({super.key, required this.child, this.delay = Duration.zero, this.onDone});

  final Widget child;

  /// Attente avant la dissolution (cascade quand toute la discussion est vidée).
  final Duration delay;
  final VoidCallback? onDone;

  static const duration = Duration(milliseconds: 520);

  @override
  State<DissolveOut> createState() => _DissolveOutState();
}

class _DissolveOutState extends State<DissolveOut> with SingleTickerProviderStateMixin {
  // L'attente fait partie de l'animation (pas de minuterie à part) : elle s'arrête avec
  // l'écran, et les tests attendent sa fin.
  late final _total = widget.delay + DissolveOut.duration;
  late final _c = AnimationController(vsync: this, duration: _total);
  late final double _start = widget.delay.inMicroseconds / _total.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return const SizedBox.shrink();
    double span(double a) => _start + (1 - _start) * a;
    final fade = CurvedAnimation(
      parent: _c,
      curve: Interval(span(0), span(0.7), curve: Curves.easeIn),
    );
    final close = CurvedAnimation(
      parent: _c,
      curve: Interval(span(0.55), 1, curve: Curves.easeInOut),
    );
    return SizeTransition(
      sizeFactor: ReverseAnimation(close),
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: fade,
        builder: (_, child) => Opacity(
          opacity: 1 - fade.value,
          child: Transform.scale(
            scale: 1 - 0.06 * fade.value,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 4 * fade.value, sigmaY: 4 * fade.value),
              child: child,
            ),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// « Supprimé pour tout le monde » : la bulle se froisse et se réduit, puis l'indication
/// « Message supprimé » apparaît.
class CrumpleSwitch extends StatelessWidget {
  const CrumpleSwitch({super.key, required this.deleted, required this.child});

  final bool deleted;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.of(context, Motion.slow),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, a) => child.key == const ValueKey('deleted')
        ? FadeTransition(opacity: a, child: child)
        : FadeTransition(
            opacity: a,
            child: RotationTransition(
              turns: Tween(begin: -0.03, end: 0.0).animate(a),
              child: ScaleTransition(scale: Tween(begin: 0.4, end: 1.0).animate(a), child: child),
            ),
          ),
    child: KeyedSubtree(key: ValueKey(deleted ? 'deleted' : 'shown'), child: child),
  );
}

/// Double appui : l'émoji grandit et s'envole au-dessus de la bulle.
void showReactionBurst(BuildContext context, GlobalKey? anchor, String emoji) {
  if (Motion.reduced(context) || anchor?.currentContext == null) return;
  final box = anchor!.currentContext!.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context);
  if (box == null || overlay == null || !box.hasSize) return;
  final center = box.localToGlobal(box.size.center(Offset.zero));
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: center.dx - 40,
      top: center.dy - 40,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOut,
          onEnd: entry.remove,
          builder: (_, t, _) => Opacity(
            opacity: t < 0.6 ? 1 : (1 - (t - 0.6) / 0.4),
            child: Transform.translate(
              offset: Offset(0, -36 * t),
              child: Transform.scale(
                scale: 0.4 + 1.2 * Curves.elasticOut.transform(math.min(1, t * 1.6)),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40))),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

/// « Vider la discussion » depuis une fiche : un coup de balai traverse l'écran.
void showSweep(BuildContext context) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null || Motion.reduced(context)) return;
  final color = Theme.of(context).colorScheme.primary;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final width = MediaQuery.sizeOf(ctx).width;
      return Positioned.fill(
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            onEnd: entry.remove,
            builder: (_, t, _) => Stack(
              children: [
                // Traînée de poussière qui s'efface derrière le balai.
                for (var i = 0; i < 7; i++)
                  Positioned(
                    left: (width + 120) * t - 60 - i * 26,
                    top: MediaQuery.sizeOf(ctx).height * (0.42 + 0.025 * (i % 3)),
                    child: Opacity(
                      opacity: (1 - t) * (1 - i / 8),
                      child: Container(
                        width: 8 - i * 0.6,
                        height: 8 - i * 0.6,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: (width + 120) * t - 80,
                  top: MediaQuery.sizeOf(ctx).height * 0.38,
                  child: Transform.rotate(
                    angle: -0.35 + 0.25 * math.sin(t * math.pi * 3),
                    child: Icon(Icons.cleaning_services_rounded, size: 56, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
}
