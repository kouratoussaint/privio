import '../l10n/l10n.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/device_services.dart';
import '../data/storage/app_lock_store.dart';

final appLockStoreProvider = Provider<AppLockStore>((ref) => MemoryAppLockStore());
final biometricGateProvider = Provider<BiometricGate>((ref) => const NoBiometricGate());
final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

/// Horloge remplaçable (tests du délai et des attentes).
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Longueur du code Privio.
const kPinLength = 6;

/// Essais libres avant d'imposer une attente, puis attente doublée à chaque erreur.
const kFreeAttempts = 5;
const kFirstWait = Duration(seconds: 30);
const kMaxWait = Duration(minutes: 15);

class AppLockState {
  const AppLockState({
    required this.config,
    required this.locked,
    this.biometricsAvailable = false,
  });

  final AppLockConfig config;
  final bool locked;
  final bool biometricsAvailable;

  bool get enabled => config.enabled;

  AppLockState copyWith({AppLockConfig? config, bool? locked, bool? biometricsAvailable}) =>
      AppLockState(
        config: config ?? this.config,
        locked: locked ?? this.locked,
        biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      );
}

sealed class UnlockResult {
  const UnlockResult();
}

class Unlocked extends UnlockResult {
  const Unlocked();
}

class WrongPin extends UnlockResult {
  const WrongPin(this.remainingBeforeWait);

  /// Essais restants avant une attente (0 : une attente vient d'être imposée).
  final int remainingBeforeWait;
}

class MustWait extends UnlockResult {
  const MustWait(this.until);

  final DateTime until;
}

final appLockProvider = AsyncNotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// Verrouillage de l'application (SEC-004) : au démarrage, puis au retour après le délai
/// choisi. Les réglages et le compteur d'essais survivent à la fermeture de l'application.
class AppLockController extends AsyncNotifier<AppLockState> {
  DateTime? _backgroundAt;
  int _externalDepth = 0;
  bool _authenticating = false;

  AppLockStore get _store => ref.read(appLockStoreProvider);
  DateTime _now() => ref.read(lockClockProvider)();

  @override
  Future<AppLockState> build() async {
    final config = await _store.read();
    final bio = config.enabled && await ref.read(biometricGateProvider).available();
    return AppLockState(config: config, locked: config.enabled, biometricsAvailable: bio);
  }

  AppLockState get _s => state.requireValue;

  Future<void> _save(AppLockConfig config, {bool? locked}) async {
    await _store.write(config);
    state = AsyncData(_s.copyWith(config: config, locked: locked));
  }

  // --- Cycle de vie ---------------------------------------------------------

  /// L'application passe en arrière-plan.
  void onBackground() {
    if (_authenticating || _externalDepth > 0) return;
    _backgroundAt ??= _now();
  }

  /// L'application revient au premier plan : verrouiller si le délai est dépassé.
  void onForeground() {
    final at = _backgroundAt;
    _backgroundAt = null;
    final s = state.value;
    if (at == null || s == null || !s.enabled || s.locked) return;
    if (_now().difference(at).inSeconds >= s.config.delaySeconds) {
      state = AsyncData(s.copyWith(locked: true));
    }
  }

  /// Lot 8.3a : « Verrouiller Privio maintenant » (menu ⋮ des listes).
  void lockNow() {
    final s = state.value;
    if (s == null || !s.enabled || s.locked) return;
    _backgroundAt = null;
    state = AsyncData(s.copyWith(locked: true));
  }

  /// Appareil photo ou galerie : sortie voulue, sans reverrouillage au retour.
  Future<T> runExternal<T>(Future<T> Function() action) async {
    _externalDepth++;
    try {
      return await action();
    } finally {
      _externalDepth--;
      _backgroundAt = null;
    }
  }

  // --- Déverrouillage -------------------------------------------------------

  /// Attente en cours (trop d'essais manqués), ou null.
  DateTime? get waitUntil {
    final until = state.value?.config.retryAt;
    return until != null && until.isAfter(_now()) ? until : null;
  }

  Future<bool> _check(String pin) async {
    final c = _s.config;
    if (c.salt == null || c.hash == null) return false;
    final h = await ref.read(pinHasherProvider).hash(pin, base64Decode(c.salt!), c.iterations);
    return sameHash(h, c.hash!);
  }

  Future<UnlockResult> unlock(String pin) async {
    final wait = waitUntil;
    if (wait != null) return MustWait(wait);
    if (await _check(pin)) {
      await _save(_s.config.copyWith(failures: 0, clearRetry: true), locked: false);
      return const Unlocked();
    }
    final failures = _s.config.failures + 1;
    DateTime? retryAt;
    if (failures >= kFreeAttempts) {
      final factor = 1 << (failures - kFreeAttempts).clamp(0, 10);
      final wait = kFirstWait * factor;
      retryAt = _now().add(wait > kMaxWait ? kMaxWait : wait);
    }
    await _save(
      _s.config.copyWith(failures: failures, retryAt: retryAt, clearRetry: retryAt == null),
    );
    return retryAt == null ? WrongPin(kFreeAttempts - failures) : MustWait(retryAt);
  }

  Future<bool> unlockWithBiometrics() async {
    final s = state.value;
    if (s == null || !s.locked || !s.config.biometrics || !s.biometricsAvailable) return false;
    _authenticating = true;
    try {
      final ok = await ref.read(biometricGateProvider).authenticate(L.t.deverrouillerPrivio);
      if (ok) {
        await _save(_s.config.copyWith(failures: 0, clearRetry: true), locked: false);
      }
      return ok;
    } finally {
      _authenticating = false;
      _backgroundAt = null;
    }
  }

  /// Confirmer son identité par l'empreinte, application déjà déverrouillée (ouverture de
  /// la console, lot 5.1). Faux si l'empreinte n'est pas activée ou pas disponible.
  Future<bool> confirmWithBiometrics(String reason) async {
    final s = state.value;
    if (s == null || !s.enabled || !s.config.biometrics || !s.biometricsAvailable) return false;
    _authenticating = true;
    try {
      return await ref.read(biometricGateProvider).authenticate(reason);
    } finally {
      _authenticating = false;
      _backgroundAt = null;
    }
  }

  // --- Réglages -------------------------------------------------------------

  Future<AppLockConfig> _withPin(AppLockConfig base, String pin) async {
    final salt = PinHasher.newSalt();
    final hash = await ref.read(pinHasherProvider).hash(pin, salt, AppLockConfig.defaultIterations);
    return base.copyWith(
      salt: base64Encode(salt),
      hash: hash,
      iterations: AppLockConfig.defaultIterations,
      failures: 0,
      clearRetry: true,
    );
  }

  /// Active le verrouillage avec un nouveau code.
  Future<void> enable(String pin) async {
    final available = await ref.read(biometricGateProvider).available();
    final config = await _withPin(_s.config.copyWith(enabled: true), pin);
    await _store.write(config);
    state = AsyncData(AppLockState(config: config, locked: false, biometricsAvailable: available));
  }

  /// Vérifie le code actuel (changement de code, désactivation).
  Future<UnlockResult> verify(String pin) async {
    final wait = waitUntil;
    if (wait != null) return MustWait(wait);
    final r = await unlock(pin);
    return r;
  }

  Future<void> changePin(String pin) async => _save(await _withPin(_s.config, pin));

  Future<void> disable() => reset();

  Future<void> setDelay(int seconds) => _save(_s.config.copyWith(delaySeconds: seconds));

  Future<void> setBiometrics(bool value) => _save(_s.config.copyWith(biometrics: value));

  /// Déconnexion, suppression du compte, « code oublié » : tout est oublié.
  Future<void> reset() async {
    await _store.clear();
    _backgroundAt = null;
    state = const AsyncData(AppLockState(config: AppLockConfig(), locked: false));
  }
}

/// Texte d'attente : « 30 s », « 2 min ».
String formatWait(Duration d) {
  final s = d.inSeconds.clamp(1, 1 << 30);
  if (s < 60) return L.t.unitSeconds(s);
  final m = (s / 60).ceil();
  return L.t.unitMinutes(m);
}
