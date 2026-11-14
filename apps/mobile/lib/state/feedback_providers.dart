import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/sound_service.dart';
import 'providers.dart';

export '../data/services/sound_service.dart' show PrivioSound;

final soundPlayerProvider = Provider<SoundPlayer>((ref) => DeviceSoundPlayer());

/// Réglage « Sons et vibrations dans l'application » (activé par défaut).
final soundsEnabledProvider = AsyncNotifierProvider<SoundsEnabledController, bool>(
  SoundsEnabledController.new,
);

class SoundsEnabledController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(localFlagsProvider).soundsEnabled();

  Future<void> set(bool value) async {
    await ref.read(localFlagsProvider).setSoundsEnabled(value);
    state = AsyncData(value);
  }
}

enum Haptic { light, medium, heavy, selection }

/// Retour sonore et vibration, selon le réglage.
final feedbackProvider = Provider<PrivioFeedback>(PrivioFeedback.new);

class PrivioFeedback {
  PrivioFeedback(this._ref);

  final Ref _ref;

  // Tant que le réglage n'est pas lu (premières millisecondes), silence : mieux vaut un son
  // manqué qu'un son joué alors qu'il est coupé. Il est lu au démarrage (app.dart).
  bool get _on => _ref.read(soundsEnabledProvider).value ?? false;

  void sound(PrivioSound s) {
    if (_on) unawaited(_ref.read(soundPlayerProvider).play(s));
  }

  void haptic(Haptic h) {
    if (!_on) return;
    unawaited(switch (h) {
      Haptic.light => HapticFeedback.lightImpact(),
      Haptic.medium => HapticFeedback.mediumImpact(),
      Haptic.heavy => HapticFeedback.heavyImpact(),
      Haptic.selection => HapticFeedback.selectionClick(),
    });
  }
}
