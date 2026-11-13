import 'package:flutter/material.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';

/// Barres « une par jour » (lot 5.2) : une seule série, une seule teinte, barres fines aux
/// extrémités arrondies posées sur la ligne de base, axe discret. Toucher une barre affiche
/// le jour et la valeur. Une journée sans relevé (null) n'a pas de barre.
class DayBars extends StatefulWidget {
  const DayBars({
    super.key,
    required this.days,
    required this.values,
    required this.semanticLabel,
    this.height = 120,
  });

  final List<DateTime> days;
  final List<int?> values;
  final String semanticLabel;
  final double height;

  @override
  State<DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<DayBars> {
  int? _selected;

  int get _max => widget.values.fold<int>(0, (m, v) => v != null && v > m ? v : m);

  static String _dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  void _pick(Offset local, double width) {
    final n = widget.values.length;
    if (n == 0) return;
    final i = (local.dx / width * n).floor().clamp(0, n - 1);
    setState(() => _selected = _selected == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final sel = _selected;
    final label = sel == null
        ? 'Touchez une barre pour voir le jour'
        : '${_dm(widget.days[sel])} : '
              '${widget.values[sel] == null ? 'pas de relevé' : formatThousands(widget.values[sel]!)}';
    return Semantics(
      label: widget.semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            key: const Key('bars.label'),
            style: theme.textTheme.bodySmall?.copyWith(color: sel == null ? muted : null),
          ),
          const SizedBox(height: PrivioSpacing.xs),
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
                      child: CustomPaint(
                        painter: _BarsPainter(
                          values: widget.values,
                          max: _max,
                          color: theme.colorScheme.primary,
                          selectedColor: theme.colorScheme.onSurface,
                          axis: theme.colorScheme.outlineVariant,
                          selected: sel,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: PrivioSpacing.s),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatThousands(_max),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                    Text('0', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  ],
                ),
              ],
            ),
          ),
          if (widget.days.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PrivioSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _dm(widget.days.first),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  Text('aujourd’hui', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.max,
    required this.color,
    required this.selectedColor,
    required this.axis,
    required this.selected,
  });

  final List<int?> values;
  final int max;
  final Color color;
  final Color selectedColor;
  final Color axis;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = axis
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
    if (values.isEmpty || max == 0) return;
    const gap = 2.0;
    final slot = size.width / values.length;
    final w = (slot - gap).clamp(1.0, 24.0);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || v == 0) continue;
      final h = (v / max * (size.height - 1)).clamp(2.0, size.height - 1);
      final left = i * slot + (slot - w) / 2;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - 1 - h, w, h),
        topLeft: Radius.circular((w / 2).clamp(0, 4)),
        topRight: Radius.circular((w / 2).clamp(0, 4)),
      );
      canvas.drawRRect(r, Paint()..color = i == selected ? selectedColor : color);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.selected != selected || old.color != color || old.max != max;
}
