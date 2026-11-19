import 'package:flutter/material.dart';

import 'privio_tokens.dart';

/// Couleurs de marque hors ColorScheme (en-tête, bulles, champs, avertissements).
/// Lire avec `PrivioPalette.of(context)` ; jamais de couleur codée dans un widget.
@immutable
class PrivioPalette extends ThemeExtension<PrivioPalette> {
  const PrivioPalette({
    required this.header,
    required this.onHeader,
    required this.onHeaderMuted,
    required this.sheet,
    required this.chatBackground,
    required this.bubbleIn,
    required this.onBubbleIn,
    required this.bubbleInMeta,
    required this.bubbleOut,
    required this.onBubbleOut,
    required this.bubbleOutMeta,
    required this.quoteIn,
    required this.quoteOut,
    required this.accentText,
    required this.field,
    required this.divider,
    required this.warn,
    required this.success,
    required this.notice,
    required this.navigation,
    required this.pattern,
  });

  final Color header;
  final Color onHeader;
  final Color onHeaderMuted;
  final Color sheet;
  final Color chatBackground;
  final Color bubbleIn;
  final Color onBubbleIn;
  final Color bubbleInMeta;
  final Color bubbleOut;
  final Color onBubbleOut;
  final Color bubbleOutMeta;
  final Color quoteIn;
  final Color quoteOut;
  final Color accentText;
  final Color field;
  final Color divider;
  final Color warn;
  final Color success;
  final Color notice;
  final Color navigation;

  /// Motif « confidentialité » du fond des discussions (opacité très réduite).
  final Color pattern;

  static const light = PrivioPalette(
    header: PrivioColors.purpleDeep,
    onHeader: Colors.white,
    onHeaderMuted: Color(0xFFEADCFF),
    sheet: Colors.white,
    chatBackground: PrivioColors.chatLight,
    bubbleIn: Colors.white,
    onBubbleIn: PrivioColors.textPrimary,
    bubbleInMeta: Color(0x9E17182D), // 62 % de #17182D
    bubbleOut: PrivioColors.purpleDeep,
    onBubbleOut: Colors.white,
    bubbleOutMeta: Color(0xADFFFFFF), // 68 % de blanc
    quoteIn: PrivioColors.chatLight,
    quoteOut: Color(0x29FFFFFF),
    accentText: PrivioColors.purpleText,
    field: PrivioColors.fieldLight,
    divider: PrivioColors.dividerLight,
    warn: PrivioColors.warnLight,
    success: PrivioColors.success,
    notice: Color(0xFFEAE1FB),
    navigation: PrivioColors.surfaceLight,
    pattern: Color(0x125B1FB8), // 7 %
  );

  static const dark = PrivioPalette(
    header: PrivioColors.headerDark,
    onHeader: Colors.white,
    onHeaderMuted: Color(0xFFEADCFF),
    sheet: PrivioColors.surfaceDark,
    chatBackground: PrivioColors.chatDark,
    bubbleIn: PrivioColors.surfaceContainerDark,
    onBubbleIn: Colors.white,
    bubbleInMeta: Color(0x99FFFFFF), // 60 % de blanc
    bubbleOut: PrivioColors.purpleText,
    onBubbleOut: Colors.white,
    bubbleOutMeta: Color(0xD1FFFFFF), // 82 % de blanc
    quoteIn: Color(0xFF232B52),
    quoteOut: Color(0x29FFFFFF),
    accentText: PrivioColors.lilac,
    field: PrivioColors.surfaceContainerDark,
    divider: PrivioColors.dividerDark,
    warn: PrivioColors.warnDark,
    success: PrivioColors.successDark,
    notice: PrivioColors.surfaceContainerDark,
    navigation: Color(0xFF141B38),
    pattern: Color(0x0FC879FF), // 6 %
  );

  static PrivioPalette of(BuildContext context) =>
      Theme.of(context).extension<PrivioPalette>() ?? light;

  /// Couleur stable d'une pastille d'initiales, dérivée d'un identifiant.
  static Color avatarFor(String seed) =>
      PrivioColors.avatars[seed.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff) %
          PrivioColors.avatars.length];

  /// Lot 5.10 : même palette, autre couleur d'accent (rubriques de la console).
  PrivioPalette withAccent(Color accent) => PrivioPalette(
    header: header,
    onHeader: onHeader,
    onHeaderMuted: onHeaderMuted,
    sheet: sheet,
    chatBackground: chatBackground,
    bubbleIn: bubbleIn,
    onBubbleIn: onBubbleIn,
    bubbleInMeta: bubbleInMeta,
    bubbleOut: bubbleOut,
    onBubbleOut: onBubbleOut,
    bubbleOutMeta: bubbleOutMeta,
    quoteIn: quoteIn,
    quoteOut: quoteOut,
    accentText: accent,
    field: field,
    divider: divider,
    warn: warn,
    success: success,
    notice: notice,
    navigation: navigation,
    pattern: pattern,
  );

  @override
  PrivioPalette copyWith() => this;

  @override
  PrivioPalette lerp(ThemeExtension<PrivioPalette>? other, double t) =>
      other is PrivioPalette && t >= 0.5 ? other : this;
}
