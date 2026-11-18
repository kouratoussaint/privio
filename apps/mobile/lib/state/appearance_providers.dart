import 'dart:async';

import '../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Lot 8.1a : thème et taille du texte, réglages gardés sur le téléphone.
class Appearance {
  const Appearance({this.theme = 'system', this.textSize = 'normal', this.language = 'fr'});

  /// Lot 8.2a : langue (« fr », « mos », « dyu »).
  final String language;

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
  static Map<String, String> get textLabels => {
    'small': L.t.petit,
    'normal': L.t.normal,
    'large': L.t.grand,
    'xlarge': L.t.tresGrand,
  };
  static Map<String, String> get themeLabels => {
    'system': L.t.automatiqueCommeTelephone,
    'light': L.t.clair,
    'dark': L.t.sombre,
  };

  Appearance copyWith({String? theme, String? textSize, String? language}) => Appearance(
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    language: language ?? this.language,
  );
}

final appearanceProvider = AsyncNotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);

class AppearanceController extends AsyncNotifier<Appearance> {
  @override
  Future<Appearance> build() async {
    final flags = ref.watch(localFlagsProvider);
    return Appearance(
      theme: await flags.themeChoice(),
      textSize: await flags.textSize(),
      language: await flags.language(),
    );
  }

  Future<void> setTheme(String value) async {
    await ref.read(localFlagsProvider).setThemeChoice(value);
    state = AsyncData((state.value ?? const Appearance()).copyWith(theme: value));
  }

  Future<void> setLanguage(String value) async {
    await ref.read(localFlagsProvider).setLanguage(value);
    state = AsyncData((state.value ?? const Appearance()).copyWith(language: value));
    // Lot 5.9 : langue de ce téléphone (statistiques seulement).
    unawaited(ref.read(accountApiProvider).setDeviceLanguage(value).catchError((Object _) {}));
  }

  Future<void> setTextSize(String value) async {
    await ref.read(localFlagsProvider).setTextSize(value);
    state = AsyncData((state.value ?? const Appearance()).copyWith(textSize: value));
  }
}
