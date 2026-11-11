import 'package:flutter/material.dart';

import 'privio_tokens.dart';

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

  static ThemeData get light => _build(lightScheme);
  static ThemeData get dark => _build(darkScheme);

  /// Échelle du guide : titres 24–28, sous-titres 18–20, corps 14–16, légendes 12.
  static TextTheme _textTheme(ColorScheme s) {
    TextStyle style(double size, FontWeight weight, {Color? color, double height = 1.3}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallbackFonts,
          fontSize: size,
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
      bodyLarge: style(16, FontWeight.w400, height: 1.45),
      bodyMedium: style(14, FontWeight.w400, height: 1.45),
      bodySmall: style(12, FontWeight.w400, color: s.onSurfaceVariant),
      labelLarge: style(16, FontWeight.w600),
      labelMedium: style(14, FontWeight.w500),
      labelSmall: style(12, FontWeight.w500, color: s.onSurfaceVariant),
    );
  }

  static ThemeData _build(ColorScheme s) {
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
      colorScheme: s,
      fontFamily: fontFamily,
      fontFamilyFallback: fallbackFonts,
      textTheme: text,
      scaffoldBackgroundColor: s.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
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
        backgroundColor: s.surfaceContainerHighest,
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
      dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
    );
  }
}
