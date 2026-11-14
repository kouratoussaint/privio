import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/privio_brand.dart';
import 'motion.dart';

/// Lot 7.2b2 : illustrations animées dessinées par l'application (aucune image animée
/// téléchargée). Elles respirent doucement, se figent si le téléphone demande moins
/// d'animations et pendant les tests automatiques.

/// Logo Privio qui respire, entouré d'un halo qui s'élargit (démarrage, accueil, verrou).
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({super.key, this.size = 112});

  final double size;

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin, LoopingAnimation {
  @override
  Duration get loopDuration => const Duration(milliseconds: 2400);

  @override
  double get still => 0;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final box = widget.size * 1.35;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: loop,
        builder: (_, child) {
          final t = loop.value;
          final breathe = 1 + 0.035 * math.sin(t * 2 * math.pi);
          return CustomPaint(
            painter: _HaloPainter(t: t, color: color, inner: widget.size / 2),
            child: Center(
              child: Transform.scale(scale: breathe, child: child),
            ),
          );
        },
        child: PrivioSymbol(size: widget.size),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.t, required this.color, required this.inner});

  final double t;
  final Color color;
  final double inner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    for (final phase in [0.0, 0.5]) {
      final k = (t + phase) % 1;
      final r = inner * 0.9 + (outer - inner * 0.9) * k;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.22 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.t != t || old.color != color;
}

/// Manière dont une [FloatingIcon] bouge.
enum IconMotion {
  /// Flotte de haut en bas (illustrations des écrans vides, de l'aide).
  float,

  /// Bat comme une sonnerie (notifications).
  ring,

  /// Apparaît puis s'efface (message éphémère).
  vanish,

  /// Pulse doucement (cadenas, micro, SMS reçu).
  pulse,
}

/// Icône posée sur un disque teinté, animée en boucle.
class FloatingIcon extends StatefulWidget {
  const FloatingIcon({
    super.key,
    required this.icon,
    this.size = 56,
    this.motion = IconMotion.float,
    this.color,
    this.disc = true,
  });

  final IconData icon;
  final double size;
  final IconMotion motion;
  final Color? color;

  /// Disque teinté derrière l'icône.
  final bool disc;

  @override
  State<FloatingIcon> createState() => _FloatingIconState();
}

class _FloatingIconState extends State<FloatingIcon>
    with SingleTickerProviderStateMixin, LoopingAnimation {
  @override
  Duration get loopDuration => switch (widget.motion) {
    IconMotion.float => const Duration(milliseconds: 3000),
    IconMotion.ring => const Duration(milliseconds: 2200),
    IconMotion.vanish => const Duration(milliseconds: 2600),
    IconMotion.pulse => const Duration(milliseconds: 1800),
  };

  @override
  double get still => switch (widget.motion) {
    IconMotion.vanish => 0.35,
    IconMotion.ring => 0.9,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final icon = Icon(widget.icon, size: widget.size, color: color);
    final animated = AnimatedBuilder(
      animation: loop,
      builder: (_, child) {
        final t = loop.value;
        final wave = math.sin(t * 2 * math.pi);
        return switch (widget.motion) {
          IconMotion.float => Transform.translate(offset: Offset(0, -4 * wave), child: child),
          // Quelques battements, puis une pause.
          IconMotion.ring => Transform.rotate(
            angle: t < 0.4 ? 0.3 * math.sin(t / 0.4 * 6 * math.pi) * (1 - t / 0.4) : 0,
            alignment: Alignment.topCenter,
            child: child,
          ),
          IconMotion.vanish => Opacity(
            opacity: t < 0.15
                ? t / 0.15
                : t < 0.6
                ? 1
                : t < 0.85
                ? 1 - (t - 0.6) / 0.25
                : 0,
            child: Transform.scale(scale: t < 0.6 ? 1 : 1 - 0.2 * ((t - 0.6) / 0.4), child: child),
          ),
          IconMotion.pulse => Transform.scale(scale: 1 + 0.06 * wave, child: child),
        };
      },
      child: icon,
    );
    if (!widget.disc) return ExcludeSemantics(child: animated);
    return ExcludeSemantics(
      child: Container(
        width: widget.size * 1.9,
        height: widget.size * 1.9,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
        child: animated,
      ),
    );
  }
}

/// Trois points qui rebondissent (chargement).
class LoadingDots extends StatefulWidget {
  const LoadingDots({super.key, this.label = 'Chargement…', this.color});

  final String label;
  final Color? color;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin, LoopingAnimation {
  @override
  Duration get loopDuration => const Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: AnimatedBuilder(
        animation: loop,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(
                  0,
                  -6 * math.max(0, math.sin((loop.value - i * 0.15) * 2 * math.pi)),
                ),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Coche qui se dessine dans un cercle (réussite) : une seule fois.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        painter: _CheckPainter(
          t: Curves.easeOutCubic.transform(_c.value),
          color: widget.color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Le cercle d'abord, puis la coche.
    final circle = (t / 0.55).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: s * 0.44),
      -math.pi / 2,
      2 * math.pi * circle,
      false,
      stroke,
    );
    final tick = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (tick == 0) return;
    final path = Path()
      ..moveTo(s * 0.28, s * 0.52)
      ..lineTo(s * 0.44, s * 0.67)
      ..lineTo(s * 0.73, s * 0.37);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * tick), stroke);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// Lignes « fantômes » qui scintillent pendant le chargement d'une liste.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 7, this.bubbles = false});

  final int rows;

  /// Forme de bulles de discussion (sinon : lignes avec photo).
  final bool bubbles;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin, LoopingAnimation {
  @override
  Duration get loopDuration => const Duration(milliseconds: 1400);

  @override
  double get still => 0;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);
    Widget bar(double w, double h, {double r = 6}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(r)),
    );
    final rows = [
      for (var i = 0; i < widget.rows; i++)
        if (widget.bubbles)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: bar(120.0 + (i * 37) % 110, 38, r: 16),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                bar(48, 48, r: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(110.0 + (i * 29) % 80, 12),
                      const SizedBox(height: 8),
                      bar(170.0 + (i * 41) % 90, 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
    ];
    return Semantics(
      label: 'Chargement…',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: loop,
          builder: (_, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final x = -1 + 3 * loop.value;
              return LinearGradient(
                begin: Alignment(x - 1, 0),
                end: Alignment(x, 0),
                colors: [base, base.withValues(alpha: 0.2), base],
              ).createShader(rect);
            },
            child: child,
          ),
          child: ListView(physics: const NeverScrollableScrollPhysics(), children: rows),
        ),
      ),
    );
  }
}
