import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/theme/privio_palette.dart';
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

  for (final (label, p) in [('clair', PrivioPalette.light), ('sombre', PrivioPalette.dark)]) {
    group('palette de marque ($label, lot 2.D)', () {
      test('en-tête', () => expectAA('onHeader/header', p.onHeader, p.header));
      test('en-tête, texte secondaire', () => expectAA('onHeaderMuted', p.onHeaderMuted, p.header));
      test(
        'bulle envoyée (violet plein, décision 1B)',
        () => expectAA('onBubbleOut', p.onBubbleOut, p.bubbleOut),
      );
      test(
        'heure dans la bulle envoyée',
        () => expectAA('bubbleOutMeta', p.bubbleOutMeta, p.bubbleOut),
      );
      test('bulle reçue', () => expectAA('onBubbleIn', p.onBubbleIn, p.bubbleIn));
      test('heure dans la bulle reçue', () => expectAA('bubbleInMeta', p.bubbleInMeta, p.bubbleIn));
      test(
        'texte d\'accent sur la feuille',
        () => expectAA('accentText/sheet', p.accentText, p.sheet),
      );
      test('rappel d\'expiration', () => expectAA('warn/sheet', p.warn, p.sheet));
      test('état « Connecté »', () => expectAA('success', p.success, p.sheet));
    });
  }

  test('pastilles d\'initiales : texte blanc lisible sur chaque couleur', () {
    for (final c in PrivioColors.avatars) {
      expectAA('avatar ${c.toARGB32().toRadixString(16)}', Colors.white, c);
    }
  });

  test('pastilles de filtre sélectionnées', () {
    expectAA('clair', Colors.white, PrivioColors.purpleDeep);
    expectAA('sombre', PrivioColors.navy, PrivioColors.lilac);
  });
}
