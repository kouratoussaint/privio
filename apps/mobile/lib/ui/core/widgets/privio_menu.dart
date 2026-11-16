import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../l10n/l10n.dart';
import '../motion/motion.dart';

/// Lot 8.5a — menu en carte flottante (décision A.1 du 16/11/2026) : icônes dans des
/// pastilles de couleur, actions dangereuses séparées en rouge, ouverture animée depuis le
/// bouton (ou le point d'appui). Au-delà de [PrivioMenu.collapseAfter] actions, les
/// premières seulement, puis « Voir plus ».
class PrivioMenuItem<T> {
  const PrivioMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.key,
    this.tint,
    this.danger = false,
    this.enabled = true,
    this.subtitle,
  });

  final T value;
  final IconData icon;
  final String label;
  final Key? key;

  /// Couleur de la pastille (par défaut : couleur d'accent de Privio).
  final Color? tint;
  final bool danger;
  final bool enabled;
  final String? subtitle;
}

/// Teintes des pastilles, par famille d'action.
abstract final class MenuTint {
  static const violet = Color(0xFF6A3FD0);
  static const teal = Color(0xFF138A6E);
  static const amber = Color(0xFFB7700F);
  static const blue = Color(0xFF2A73C9);
  static const green = Color(0xFF3E8B1A);
  static const pink = Color(0xFFC0457A);
  static const gray = Color(0xFF6B6A66);
}

abstract final class PrivioMenu {
  /// Plus de 6 actions : 5 visibles, puis « Voir plus ».
  static const collapseAfter = 6;
  static const visibleWhenCollapsed = 5;
  static const width = 268.0;

  /// Ouvre le menu près de [anchor] (le bouton ⋮ ou l'élément appuyé). [at] : point
  /// d'appui précis (appui long), sinon le coin du bouton.
  static Future<T?> show<T>(
    BuildContext anchor, {
    required List<PrivioMenuItem<T>> items,
    Offset? at,
    String? title,
  }) {
    final box = anchor.findRenderObject() as RenderBox?;
    // Navigateur racine : au-dessus de la barre d'onglets.
    final nav = Navigator.of(anchor, rootNavigator: true);
    final overlay = nav.overlay!.context.findRenderObject() as RenderBox;
    Rect rect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
      rect = topLeft & box.size;
    } else {
      rect = Rect.fromCenter(center: overlay.size.center(Offset.zero), width: 0, height: 0);
    }
    if (at != null) rect = Rect.fromCenter(center: at, width: 0, height: 0);
    // Ancre trop grande (un écran entier) : menu au milieu de l'écran.
    if (rect.height > overlay.size.height * 0.4) {
      final c = overlay.size.center(Offset.zero);
      rect = Rect.fromLTWH(overlay.size.width / 2 - PrivioMenu.width / 2, c.dy - 120, 0, 0);
    }
    return nav.push<T>(
      _MenuRoute<T>(
        anchor: rect,
        items: items,
        title: title,
        barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
        duration: Motion.of(anchor, Motion.medium),
      ),
    );
  }
}

/// Bouton ⋮ qui ouvre un [PrivioMenu].
class PrivioMenuButton<T> extends StatelessWidget {
  const PrivioMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.icon = const Icon(Icons.more_vert),
  });

  final List<PrivioMenuItem<T>> Function() items;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (ctx) => IconButton(
      tooltip: tooltip ?? L.t.plusOptions,
      icon: icon,
      onPressed: () async {
        final v = await PrivioMenu.show<T>(ctx, items: items());
        if (v != null) onSelected(v);
      },
    ),
  );
}

class _MenuRoute<T> extends PopupRoute<T> {
  _MenuRoute({
    required this.anchor,
    required this.items,
    required this.title,
    required this.barrierLabel,
    required this.duration,
  });

  final Rect anchor;
  final List<PrivioMenuItem<T>> items;
  final String? title;
  final Duration duration;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.black12;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => Duration(milliseconds: duration.inMilliseconds ~/ 2);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const margin = 8.0;
    final w = math.min(PrivioMenu.width, size.width - 2 * margin);
    // Aligné sur le bord droit du bouton s'il est à droite de l'écran, sinon sur son bord
    // gauche ; sous le bouton, ou au-dessus s'il est en bas de l'écran.
    final rightSide = anchor.center.dx > size.width / 2;
    final left = (rightSide ? anchor.right - w : anchor.left).clamp(
      margin,
      size.width - w - margin,
    );
    // Élément en partie hors de l'écran : on le ramène dans l'écran.
    final top = anchor.top.clamp(pad.top, size.height - pad.bottom);
    final bottom = anchor.bottom.clamp(pad.top, size.height - pad.bottom);
    final spaceBelow = size.height - pad.bottom - margin - (bottom + 4);
    final spaceAbove = top - 4 - pad.top - margin;
    // Hauteur estimée du menu : on l'ouvre du côté où il tient en entier.
    final rows = math.min(items.length, PrivioMenu.collapseAfter + 1);
    final needed = rows * 52.0 + (title != null ? 40 : 0) + 24;
    final below = spaceBelow >= needed || (spaceAbove < needed && spaceBelow >= spaceAbove);
    final alignment = Alignment(rightSide ? 1 : -1, below ? -1 : 1);
    final maxHeight = math.max(120.0, below ? spaceBelow : spaceAbove);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    final card = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: alignment,
        scale: Tween(begin: 0.86, end: 1.0).animate(curved),
        child: _MenuCard<T>(items: items, title: title, width: w),
      ),
    );
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Stack(
        children: [
          Positioned(
            left: left,
            width: w,
            top: below ? math.min(bottom + 4, size.height - pad.bottom - margin - maxHeight) : null,
            bottom: below
                ? null
                : math.min(size.height - top + 4, size.height - pad.top - margin - maxHeight),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard<T> extends StatefulWidget {
  const _MenuCard({required this.items, required this.title, required this.width});

  final List<PrivioMenuItem<T>> items;
  final String? title;
  final double width;

  @override
  State<_MenuCard<T>> createState() => _MenuCardState<T>();
}

class _MenuCardState<T> extends State<_MenuCard<T>> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = widget.items;
    final collapse = !_expanded && all.length > PrivioMenu.collapseAfter;
    final shown = collapse ? all.take(PrivioMenu.visibleWhenCollapsed).toList() : all;
    final rows = <Widget>[];
    if (widget.title != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            widget.title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    var dangerStarted = false;
    for (final item in shown) {
      // Actions dangereuses séparées du reste.
      if (item.danger && !dangerStarted && rows.isNotEmpty) {
        rows.add(Divider(height: 9, indent: 14, endIndent: 14, color: scheme.outlineVariant));
      }
      dangerStarted = dangerStarted || item.danger;
      rows.add(_MenuRow<T>(item: item));
    }
    if (collapse) {
      rows.add(
        _MenuRow<T>(
          item: PrivioMenuItem<T>(
            key: const Key('menu.more'),
            value: all.first.value,
            icon: Icons.expand_more_rounded,
            label: L.t.voirPlus,
            tint: MenuTint.gray,
          ),
          onTap: () => setState(() => _expanded = true),
        ),
      );
    }
    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: 10,
      shadowColor: Colors.black38,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: Motion.of(context, Motion.medium),
        curve: Motion.enter,
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({required this.item, this.onTap});

  final PrivioMenuItem<T> item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final base = item.danger ? scheme.error : (item.tint ?? PrivioPalette.of(context).accentText);
    final fg = dark ? Color.lerp(base, Colors.white, 0.35)! : base;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: base.withValues(alpha: dark ? 0.26 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 19, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: item.danger ? scheme.error : scheme.onSurface,
                  ),
                ),
                if (item.subtitle != null)
                  Text(
                    item.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: item.enabled,
      child: InkWell(
        key: item.key,
        onTap: !item.enabled ? null : (onTap ?? () => Navigator.of(context).pop(item.value)),
        child: Opacity(opacity: item.enabled ? 1 : 0.42, child: row),
      ),
    );
  }
}
