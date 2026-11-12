import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../domain/models/account.dart';
import 'providers.dart';
import 'push_providers.dart';

/// Étape du parcours, dont découle la navigation (voir router/stage_redirect.dart).
enum SessionStage { onboarding, signedOut, needsProfile, needsPermissions, ready }

class SessionState {
  const SessionState({
    required this.onboardingDone,
    required this.signedIn,
    required this.permissionsSeen,
    this.account,
    this.notice,
  });

  final bool onboardingDone;
  final bool signedIn;
  final bool permissionsSeen;
  final Account? account;

  /// Message à afficher une fois (ex. compte ouvert sur un autre appareil).
  final String? notice;

  SessionStage get stage {
    if (!onboardingDone) return SessionStage.onboarding;
    if (!signedIn || account == null) return SessionStage.signedOut;
    if (!account!.hasProfile) return SessionStage.needsProfile;
    if (!permissionsSeen) return SessionStage.needsPermissions;
    return SessionStage.ready;
  }
}

const kAccountDeletedNotice =
    'Votre compte Privio a été supprimé, ainsi que vos messages envoyés. Vous pouvez créer '
    'un nouveau compte à tout moment.';

const kOtherDeviceNotice =
    'Votre compte est maintenant ouvert sur un autre téléphone. Privio ne fonctionne que '
    'sur un seul appareil à la fois : reconnectez-vous pour l\'utiliser ici.';

final sessionControllerProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<SessionState> {
  String? _pendingNotice;

  /// Dernier état connecté/déconnecté connu. Mis à jour AVANT toute déconnexion
  /// déclenchée par le contrôleur lui-même, pour ne pas se recharger en boucle.
  bool _lastSignedIn = false;

  @override
  Future<SessionState> build() async {
    final auth = ref.watch(authServiceProvider);
    final flags = ref.watch(localFlagsProvider);
    final api = ref.watch(accountApiProvider);

    // On ne reconstruit que si l'état connecté/déconnecté change réellement
    // (le flux Auth émet aussi l'état initial et les rafraîchissements de jeton).
    final signedIn = _lastSignedIn = auth.hasSession;
    final sub = auth.changes.listen((_) {
      if (auth.hasSession != _lastSignedIn) {
        _lastSignedIn = auth.hasSession;
        ref.invalidateSelf();
      }
    });
    ref.onDispose(sub.cancel);

    final onboardingDone = await flags.onboardingDone();
    final permissionsSeen = await flags.permissionsSeen();

    if (!signedIn) {
      return SessionState(
        onboardingDone: onboardingDone,
        signedIn: false,
        permissionsSeen: permissionsSeen,
        notice: _pendingNotice,
      );
    }

    try {
      final account = await api.getMyAccount();
      return SessionState(
        onboardingDone: onboardingDone,
        signedIn: true,
        permissionsSeen: permissionsSeen,
        account: account,
      );
    } on AppFailure catch (f) {
      if (f.code != FailureCode.authRequired) rethrow;
      // Session révoquée côté serveur (autre appareil) : nettoyage local.
      _pendingNotice = kOtherDeviceNotice;
      _lastSignedIn = false;
      await auth.signOut();
      await flags.clearAccountScoped();
      // Compte ouvert ailleurs : plus aucun message lisible sur ce téléphone.
      await ref.read(localCacheProvider).wipe();
      return SessionState(
        onboardingDone: onboardingDone,
        signedIn: false,
        permissionsSeen: false,
        notice: _pendingNotice,
      );
    }
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> completeOnboarding() async {
    await ref.read(localFlagsProvider).setOnboardingDone();
    await _reload();
  }

  /// Après un OTP valide : enregistre cet appareil (révoque les autres), puis recharge.
  Future<void> onOtpVerified() async {
    _pendingNotice = null;
    _lastSignedIn = ref.read(authServiceProvider).hasSession;
    await ref.read(accountApiProvider).registerDevice(appVersion: ref.read(appVersionProvider));
    await _reload();
  }

  Future<void> onProfileCreated() => _reload();

  /// Profil modifié (ex. photo de profil) : relecture du compte.
  Future<void> refreshAccount() => _reload();

  Future<void> markPermissionsSeen() async {
    await ref.read(localFlagsProvider).setPermissionsSeen();
    await _reload();
  }

  Future<void> setPhoneDiscoverable(bool value) async {
    final current = state.value;
    final result = await ref.read(accountApiProvider).setPhoneDiscoverable(value);
    if (current?.account != null) {
      state = AsyncData(
        SessionState(
          onboardingDone: current!.onboardingDone,
          signedIn: current.signedIn,
          permissionsSeen: current.permissionsSeen,
          account: current.account!.copyWith(phoneDiscoverable: result),
        ),
      );
    }
  }

  Future<void> signOut() async {
    // Plus aucune notification pour ce téléphone (jeton retiré du serveur et de Firebase).
    await forgetPushToken(ref, serverSide: true);
    try {
      await ref.read(accountApiProvider).unregisterCurrentDevice();
    } on Object {
      // L'appareil peut déjà être révoqué : la déconnexion locale reste prioritaire.
    }
    _lastSignedIn = false;
    await ref.read(authServiceProvider).signOut();
    await ref.read(localFlagsProvider).clearAccountScoped();
    // Déconnexion : le cache chiffré et sa clé sont détruits.
    await ref.read(localCacheProvider).wipe();
    _pendingNotice = null;
    await _reload();
  }

  /// Après suppression du compte côté serveur : tout effacer sur ce téléphone.
  Future<void> onAccountDeleted() async {
    await forgetPushToken(ref, serverSide: false);
    _lastSignedIn = false;
    await ref.read(localCacheProvider).wipe();
    await ref.read(authServiceProvider).signOut();
    await ref.read(localFlagsProvider).clearAccountScoped();
    _pendingNotice = kAccountDeletedNotice;
    await _reload();
  }

  void clearNotice() {
    _pendingNotice = null;
    final current = state.value;
    if (current?.notice == null) return;
    state = AsyncData(
      SessionState(
        onboardingDone: current!.onboardingDone,
        signedIn: current.signedIn,
        permissionsSeen: current.permissionsSeen,
        account: current.account,
      ),
    );
  }
}
