import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Lot 8.1a : thème et taille du texte, réglages gardés sur le téléphone.
class Appearance {
  const Appearance({this.theme = 'system', this.textSize = 'normal'});

  /// « system » (comme le téléphone, par défaut), « light » ou « dark ».
  final String theme;

  /// « small », « normal », « large » ou « xlarge ».
  final String textSize;

  ThemeMode get themeMode => switch (theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Multiplie la taille choisie dans le téléphone.
  double get textFactor => textFactors[textSize] ?? 1.0;

  static const textFactors = {'small': 0.9, 'normal': 1.0, 'large': 1.15, 'xlarge': 1.3};
  static const textLabels = {
    'small': 'Petit',
    'normal': 'Normal',
    'large': 'Grand',
    'xlarge': 'Très grand',
  };
  static const themeLabels = {
    'system': 'Automatique (comme le téléphone)',
    'light': 'Clair',
    'dark': 'Sombre',
  };

  Appearance copyWith({String? theme, String? textSize}) =>
      Appearance(theme: theme ?? this.theme, textSize: textSize ?? this.textSize);
}

final appearanceProvider = AsyncNotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);

class AppearanceController extends AsyncNotifier<Appearance> {
  @override
  Future<Appearance> build() async {
    final flags = ref.watch(localFlagsProvider);
    return Appearance(theme: await flags.themeChoice(), textSize: await flags.textSize());
  }

  Future<void> setTheme(String value) async {
    await ref.read(localFlagsProvider).setThemeChoice(value);
    state = AsyncData((state.value ?? const Appearance()).copyWith(theme: value));
  }

  Future<void> setTextSize(String value) async {
    await ref.read(localFlagsProvider).setTextSize(value);
    state = AsyncData((state.value ?? const Appearance()).copyWith(textSize: value));
  }
}
