import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/privio_palette.dart';

/// Action révélée par un glissement horizontal.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.onTriggered,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTriggered;
  final Color? color;
}

/// Glisser vers la droite / la gauche pour déclencher une action (lot 2.F).
/// L'élément suit le doigt puis revient ; l'action part au relâcher, au-delà du seuil,
/// avec une petite vibration au franchissement. Chaque action est aussi proposée à
/// TalkBack (actions personnalisées) : aucun geste n'est le seul moyen d'agir.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, this.right, this.left, this.threshold = 64});

  final Widget child;

  /// Glissement vers la droite (ex. répondre).
  final SwipeAction? right;

  /// Glissement vers la gauche (ex. supprimer).
  final SwipeAction? left;
  final double threshold;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0;
  double _from = 0;
  bool _armed = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  double get _max => widget.threshold * 1.4;

  void _update(DragUpdateDetails d) {
    var next = _dx + d.delta.dx;
    if (widget.right == null && next > 0) next = 0;
    if (widget.left == null && next < 0) next = 0;
    next = next.clamp(-_max, _max);
    final armed = next.abs() >= widget.threshold;
    if (armed && !_armed) unawaited(HapticFeedback.selectionClick());
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end(DragEndDetails _) {
    final action = _armed ? (_dx > 0 ? widget.right : widget.left) : null;
    _from = _dx;
    _armed = false;
    _back.forward(from: 0);
    action?.onTriggered();
  }

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final action = _dx > 0 ? widget.right : (_dx < 0 ? widget.left : null);
    final progress = (_dx.abs() / widget.threshold).clamp(0.0, 1.0);
    return Semantics(
      customSemanticsActions: {
        if (widget.right != null)
          CustomSemanticsAction(label: widget.right!.label): widget.right!.onTriggered,
        if (widget.left != null)
          CustomSemanticsAction(label: widget.left!.label): widget.left!.onTriggered,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: () => _end(DragEndDetails()),
        child: Stack(
          children: [
            if (action != null)
              Positioned.fill(
                child: Align(
                  alignment: _dx > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Opacity(
                      opacity: progress,
                      child: Transform.scale(
                        scale: 0.7 + 0.3 * progress,
                        child: Icon(
                          action.icon,
                          semanticLabel: action.label,
                          color: action.color ?? p.accentText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(offset: Offset(_dx, 0), child: widget.child),
          ],
        ),
      ),
    );
  }
}
