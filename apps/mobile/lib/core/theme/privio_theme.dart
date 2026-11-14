import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'privio_palette.dart';
import 'privio_tokens.dart';
import '../../ui/core/motion/motion.dart';

/// Thèmes clair et sombre : unique source de vérité des couleurs, typographies et
/// composants. Aucun widget ne code une couleur ou un style de texte en dur.
abstract final class PrivioTheme {
  static const fontFamily = 'Inter';
  static const fallbackFonts = ['Noto Sans', 'Roboto'];

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: PrivioColors.purple,
    onPrimary: PrivioColors.textInverse,
    primaryContainer: PrivioColors.outgoingBubbleLight,
    onPrimaryContainer: PrivioColors.textPrimary,
    secondary: PrivioColors.blue,
    onSecondary: PrivioColors.textInverse,
    tertiary: PrivioColors.navy,
    onTertiary: PrivioColors.textInverse,
    error: PrivioColors.error,
    onError: PrivioColors.textInverse,
    surface: PrivioColors.surfaceLight,
    onSurface: PrivioColors.textPrimary,
    onSurfaceVariant: PrivioColors.textSecondaryLight,
    surfaceContainerHighest: PrivioColors.surfaceContainerLight,
    surfaceContainer: PrivioColors.surfaceContainerLight,
    outline: PrivioColors.outlineLight,
    outlineVariant: PrivioColors.outlineLight,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: PrivioColors.lilac,
    onPrimary: PrivioColors.navy,
    primaryContainer: PrivioColors.outgoingBubbleDark,
    onPrimaryContainer: PrivioColors.textInverse,
    secondary: PrivioColors.blue,
    onSecondary: PrivioColors.textInverse,
    tertiary: PrivioColors.navy,
    onTertiary: PrivioColors.textInverse,
    error: PrivioColors.errorDark,
    onError: PrivioColors.navy,
    surface: PrivioColors.surfaceDark,
    onSurface: PrivioColors.textInverse,
    onSurfaceVariant: PrivioColors.textSecondaryDark,
    surfaceContainerHighest: PrivioColors.surfaceContainerDark,
    surfaceContainer: PrivioColors.surfaceContainerDark,
    outline: PrivioColors.outlineDark,
    outlineVariant: PrivioColors.outlineDark,
  );

  static ThemeData get light => _build(lightScheme, PrivioPalette.light);

  /// Écrans d'entrée (accueil, bienvenue) : fond bleu nuit « premium », quel que soit le
  /// thème du téléphone, bouton principal violet (maquette validée du lot 2.D).
  static ThemeData get entry {
    final base = dark;
    return base.copyWith(
      scaffoldBackgroundColor: PrivioColors.navy,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: PrivioColors.navy),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? PrivioColors.surfaceContainerDark
                : PrivioColors.purple,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? PrivioColors.textSecondaryDark
                : Colors.white,
          ),
        ),
      ),
    );
  }

  static ThemeData get dark => _build(darkScheme, PrivioPalette.dark);

  /// Réduction globale des polices (retour du 12/11/2026 : « un peu grosses »), −8 %.
  static const textScale = 0.92;

  /// Plancher de lisibilité : aucune légende sous 12 sp (exception documentée : l'heure
  /// et la minuterie des bulles, 11 sp, contraste ≥ 4,5:1 vérifié par les tests).
  static const minReadableSize = 12.0;

  static double scaled(double size) {
    final v = (size * textScale * 2).round() / 2;
    return v < minReadableSize ? minReadableSize : v;
  }

  /// Échelle du guide (titres 24–28, sous-titres 18–20, corps 14–16, légendes 12),
  /// réduite de 8 %.
  static TextTheme _textTheme(ColorScheme s) {
    TextStyle style(double size, FontWeight weight, {Color? color, double height = 1.3}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallbackFonts,
          fontSize: scaled(size),
          fontWeight: weight,
          height: height,
          color: color ?? s.onSurface,
        );
    return TextTheme(
      headlineMedium: style(28, FontWeight.w700, height: 1.2),
      headlineSmall: style(24, FontWeight.w700, height: 1.2),
      titleLarge: style(20, FontWeight.w600),
      titleMedium: style(18, FontWeight.w600),
      titleSmall: style(16, FontWeight.w600),
      bodyLarge: style(16, FontWeight.w400, height: 1.4),
      bodyMedium: style(14, FontWeight.w400, height: 1.4),
      bodySmall: style(12, FontWeight.w400, color: s.onSurfaceVariant),
      labelLarge: style(16, FontWeight.w600),
      labelMedium: style(14, FontWeight.w500),
      labelSmall: style(12, FontWeight.w500, color: s.onSurfaceVariant),
    );
  }

  static ThemeData _build(ColorScheme s, PrivioPalette p) {
    final text = _textTheme(s);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(PrivioRadius.medium));
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: PrivioSpacing.xl,
      vertical: PrivioSpacing.m,
    );
    const minSize = Size(kMinTouchTarget, kMinTouchTarget);
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(PrivioRadius.medium),
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      // Lot 7.2b2 : transitions d'écran communes (glissement léger et fondu).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PrivioPageTransitionsBuilder(),
          TargetPlatform.iOS: PrivioPageTransitionsBuilder(),
        },
      ),
      colorScheme: s,
      fontFamily: fontFamily,
      fontFamilyFallback: fallbackFonts,
      textTheme: text,
      scaffoldBackgroundColor: s.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.header,
        foregroundColor: p.onHeader,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: p.onHeader),
        iconTheme: IconThemeData(color: p.onHeader),
        actionsIconTheme: IconThemeData(color: p.onHeader),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.brightness == Brightness.light
            ? PrivioColors.purple
            : PrivioColors.lilac,
        foregroundColor: s.brightness == Brightness.light ? Colors.white : PrivioColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PrivioRadius.large)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minSize,
          padding: buttonPadding,
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minSize,
          padding: buttonPadding,
          shape: shape,
          side: BorderSide(color: s.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minSize,
          shape: shape,
          textStyle: text.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.l,
          vertical: PrivioSpacing.l,
        ),
        border: border(s.outline),
        enabledBorder: border(s.outline),
        focusedBorder: border(s.primary, 2),
        errorBorder: border(s.error),
        focusedErrorBorder: border(s.error, 2),
        errorStyle: text.bodySmall?.copyWith(color: s.error),
        helperStyle: text.bodySmall,
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainerHighest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrivioRadius.large),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.navigation,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(color: s.onSurface)),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: PrivioSpacing.m,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        iconColor: s.onSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape),
      dividerTheme: DividerThemeData(color: p.divider, space: 1),
    );
  }
}
