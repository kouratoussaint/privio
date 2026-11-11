import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/theme/privio_theme.dart';
import 'package:privio/core/theme/privio_tokens.dart';

/// WCAG AA : 4,5:1 pour le texte courant.
void main() {
  void expectAA(String name, Color fg, Color bg) {
    final ratio = contrastRatio(fg, bg);
    expect(ratio, greaterThanOrEqualTo(4.5), reason: '$name : ${ratio.toStringAsFixed(2)}:1');
  }

  for (final (label, s) in [
    ('clair', PrivioTheme.lightScheme),
    ('sombre', PrivioTheme.darkScheme),
  ]) {
    group('thème $label', () {
      test('texte sur surface', () => expectAA('onSurface/surface', s.onSurface, s.surface));
      test('texte secondaire', () => expectAA('onSurfaceVariant', s.onSurfaceVariant, s.surface));
      test('bouton principal', () => expectAA('onPrimary/primary', s.onPrimary, s.primary));
      test('lien/accent sur surface', () => expectAA('primary/surface', s.primary, s.surface));
      test(
        'bulle sortante',
        () => expectAA('onPrimaryContainer', s.onPrimaryContainer, s.primaryContainer),
      );
      test('erreur sur surface', () => expectAA('error/surface', s.error, s.surface));
      test(
        'texte sur conteneur',
        () => expectAA('onSurface/container', s.onSurface, s.surfaceContainerHighest),
      );
    });
  }

  test('règles du guide : le lilas échoue sur blanc, le violet sur fond sombre', () {
    expect(contrastRatio(PrivioColors.lilac, Colors.white), lessThan(4.5));
    expect(contrastRatio(PrivioColors.purple, PrivioColors.surfaceDark), lessThan(4.5));
  });
}
