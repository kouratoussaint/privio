import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Jetons de design PRIVIO (guide d'identité, palette de départ).
/// Règle WCAG : [lilac] n'est jamais utilisé pour du texte sur fond clair (2,75:1),
/// [purple] jamais pour du texte courant sur fond sombre (3,32:1).
abstract final class PrivioColors {
  static const navy = Color(0xFF111A42);
  static const purple = Color(0xFF8A35F2);
  static const blue = Color(0xFF315BEE);
  static const lilac = Color(0xFFC879FF);
  static const surfaceLight = Color(0xFFF7F6FC);
  static const surfaceDark = Color(0xFF10152D);
  static const textPrimary = Color(0xFF17182D);
  static const textInverse = Color(0xFFFFFFFF);
  static const success = Color(0xFF13866B);
  static const error = Color(0xFFC6354C);

  // Dérivés (contrastes vérifiés par test/core/theme_contrast_test.dart).
  static const textSecondaryLight = Color(0xFF4A4C66);
  static const textSecondaryDark = Color(0xFFC3C6DA);
  static const surfaceContainerLight = Color(0xFFFFFFFF);
  static const surfaceContainerDark = Color(0xFF1A2142);
  static const outgoingBubbleLight = Color(0xFFEDE3FD);
  static const outgoingBubbleDark = Color(0xFF34236B);
  static const outlineLight = Color(0xFFD9D7E8);
  static const outlineDark = Color(0xFF39406A);
  static const errorDark = Color(0xFFFF8FA0);
  static const successDark = Color(0xFF5FD3B2);
}

/// Grille 4/8 dp.
abstract final class PrivioSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class PrivioRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 20;
}

/// Cible tactile minimale (dp).
const double kMinTouchTarget = 48;

/// Rapport de contraste WCAG 2.x entre deux couleurs opaques.
double contrastRatio(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
