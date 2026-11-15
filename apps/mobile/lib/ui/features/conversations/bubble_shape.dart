import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Lot 8.1b : forme d'une bulle de discussion. Arrondis de 10 ; le premier message d'une
/// suite porte une petite queue en haut, du côté de l'auteur (à gauche pour un message
/// reçu, à droite pour le mien), et ce coin-là est pointu.
///
/// La place de la queue ([tailWidth]) est toujours réservée du côté de l'auteur, pour que
/// les messages d'une même suite restent alignés, avec ou sans queue.
class BubbleShape extends ShapeBorder {
  const BubbleShape({
    required this.outgoing,
    required this.tail,
    this.radius = 10,
    this.side = BorderSide.none,
  });

  final bool outgoing;
  final bool tail;
  final double radius;
  final BorderSide side;

  static const tailWidth = 8.0;
  static const tailHeight = 10.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Rect _body(Rect rect) => outgoing
      ? Rect.fromLTRB(rect.left, rect.top, rect.right - tailWidth, rect.bottom)
      : Rect.fromLTRB(rect.left + tailWidth, rect.top, rect.right, rect.bottom);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final b = _body(rect);
    final r = Radius.circular(radius);
    final pointed = tail ? Radius.zero : r;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          b,
          topLeft: outgoing ? r : pointed,
          topRight: outgoing ? pointed : r,
          bottomLeft: r,
          bottomRight: r,
        ),
      );
    if (!tail) return path;
    final tri = Path();
    if (outgoing) {
      tri
        ..moveTo(b.right - 1, b.top)
        ..lineTo(rect.right, b.top)
        ..quadraticBezierTo(rect.right - 2, b.top + 3, b.right, b.top + tailHeight)
        ..close();
    } else {
      tri
        ..moveTo(b.left + 1, b.top)
        ..lineTo(rect.left, b.top)
        ..quadraticBezierTo(rect.left + 2, b.top + 3, b.left, b.top + tailHeight)
        ..close();
    }
    return Path.combine(PathOperation.union, path, tri);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      BubbleShape(outgoing: outgoing, tail: tail, radius: radius * t, side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is BubbleShape) {
      return BubbleShape(
        outgoing: outgoing,
        tail: tail,
        radius: lerpDouble(a.radius, radius, t)!,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  bool operator ==(Object other) =>
      other is BubbleShape &&
      other.outgoing == outgoing &&
      other.tail == tail &&
      other.radius == radius &&
      other.side == side;

  @override
  int get hashCode => Object.hash(outgoing, tail, radius, side);
}
