import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lot 7.2b2 : règles communes des animations de Privio.
///
/// * courtes (moins de 450 ms), pour rester fluides sur les téléphones d'entrée de gamme ;
/// * « Réduire les animations » du téléphone respecté : plus de mouvement, seulement l'état
///   final ;
/// * les animations en boucle (illustrations, points d'écriture, chargement) sont figées
///   pendant les tests automatiques ([loopsEnabled]), sinon l'attente de fin d'animation des
///   tests ne se terminerait jamais.
abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const pop = Curves.elasticOut;

  /// Faux dans les tests (voir test/flutter_test_config.dart).
  static bool loopsEnabled = true;

  /// Le téléphone demande de réduire les animations.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Une animation en boucle peut tourner.
  static bool loops(BuildContext context) => loopsEnabled && !reduced(context);

  /// Durée effective : zéro si les animations sont réduites.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

/// Transition entre écrans : léger glissement horizontal et fondu (même famille que les
/// transitions Material « axe partagé »), sans effet si les animations sont réduites.
class PrivioPageTransitionsBuilder extends PageTransitionsBuilder {
  const PrivioPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: Motion.enter);
    return SlideTransition(
      position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(enter),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween(begin: Offset.zero, end: const Offset(-0.04, 0)).animate(leave),
          child: child,
        ),
      ),
    );
  }
}

/// Apparition unique : fondu et glissement depuis [offset] (bulles, lignes nouvelles).
class AppearIn extends StatefulWidget {
  const AppearIn({
    super.key,
    required this.child,
    this.animate = true,
    this.offset = const Offset(0, 0.25),
    this.scale = 1,
    this.delay = Duration.zero,
    this.duration = Motion.medium,
  });

  final Widget child;
  final bool animate;
  final Offset offset;
  final double scale;
  final Duration delay;
  final Duration duration;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> with SingleTickerProviderStateMixin {
  // L'attente fait partie de l'animation (pas de minuterie à part).
  late final _c = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  late final double _start =
      widget.delay.inMicroseconds / (widget.delay + widget.duration).inMicroseconds;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
    } else {
      _c.forward();
    }
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
  Widget build(BuildContext context) {
    final a = CurvedAnimation(
      parent: _c,
      curve: Interval(_start, 1, curve: Motion.enter),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(a),
        child: widget.scale == 1
            ? widget.child
            : ScaleTransition(
                scale: Tween(begin: widget.scale, end: 1.0).animate(a),
                child: widget.child,
              ),
      ),
    );
  }
}

/// Petit « pop » élastique quand [value] change (pastilles, réactions, onglet choisi).
/// Rien à la première image : seul un changement anime.
class PopOnChange extends StatefulWidget {
  const PopOnChange({super.key, required this.value, required this.child, this.pop = true});

  final Object? value;
  final Widget child;

  /// Faux : le changement ne fait pas sauter (ex. onglet qu'on quitte).
  final bool pop;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  @override
  void didUpdateWidget(PopOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.pop && !Motion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Motion.pop)),
    child: widget.child,
  );
}

/// Secousse horizontale quand [value] change (code faux).
class ShakeOnChange extends StatefulWidget {
  const ShakeOnChange({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<ShakeOnChange> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  @override
  void didUpdateWidget(ShakeOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      // Trois allers-retours qui s'amortissent.
      final t = _c.value;
      final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// Contrôleur en boucle qui se fige (à [still]) quand les boucles sont coupées.
mixin LoopingAnimation<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController loop = AnimationController(vsync: this, duration: loopDuration);

  Duration get loopDuration;

  /// Image montrée quand l'animation est figée (0 à 1).
  double get still => 0.5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!loop.isAnimating) loop.repeat();
    } else {
      loop
        ..stop()
        ..value = still;
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}
