import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';

/// Fond des discussions : motif original « vie privée » (cadenas, bouclier, clé, œil
/// barré, minuterie, empreinte, bulle), en quinconce, à très faible opacité.
/// Purement décoratif (exclu des lecteurs d'écran) ; les bulles restent opaques.
class PrivacyPattern extends StatelessWidget {
  const PrivacyPattern({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: p.chatBackground)),
        Positioned.fill(
          child: ExcludeSemantics(
            child: RepaintBoundary(child: CustomPaint(painter: _PatternPainter(p.pattern))),
          ),
        ),
        child,
      ],
    );
  }
}

class _Glyph {
  const _Glyph(this.icon, this.x, this.y, this.size, this.turns);

  final IconData icon;
  final double x;
  final double y;
  final double size;
  final double turns;
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.color);

  final Color color;

  static const tile = 168.0;
  static const glyphs = [
    _Glyph(Icons.lock_outline, 18, 16, 26, -0.04),
    _Glyph(Icons.shield_outlined, 92, 30, 24, 0.05),
    _Glyph(Icons.timer_outlined, 140, 92, 22, -0.06),
    _Glyph(Icons.visibility_off_outlined, 44, 86, 24, 0.03),
    _Glyph(Icons.key_outlined, 106, 128, 24, -0.1),
    _Glyph(Icons.fingerprint, 8, 138, 24, 0.06),
    _Glyph(Icons.chat_bubble_outline, 140, 8, 20, 0.08),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final painters = [
      for (final g in glyphs)
        TextPainter(
          text: TextSpan(
            text: String.fromCharCode(g.icon.codePoint),
            style: TextStyle(
              fontFamily: g.icon.fontFamily,
              package: g.icon.fontPackage,
              fontSize: g.size,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    for (var row = 0; row * tile < size.height + tile; row++) {
      // Quinconce : une rangée sur deux est décalée d'une demi-tuile.
      final offsetX = row.isOdd ? -tile / 2 : 0.0;
      for (var col = 0; col * tile + offsetX < size.width + tile; col++) {
        final ox = col * tile + offsetX;
        final oy = row * tile;
        for (var i = 0; i < glyphs.length; i++) {
          final g = glyphs[i];
          canvas
            ..save()
            ..translate(ox + g.x + g.size / 2, oy + g.y + g.size / 2)
            ..rotate(g.turns * 2 * math.pi);
          painters[i].paint(canvas, Offset(-g.size / 2, -g.size / 2));
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.color != color;
}
