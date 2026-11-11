import 'package:flutter_test/flutter_test.dart';
import 'package:privio/router/routes.dart';
import 'package:privio/state/session_controller.dart';

void main() {
  test('chargement → écran de démarrage', () {
    expect(redirectFor(null, Routes.discussions), Routes.splash);
    expect(redirectFor(null, Routes.splash), isNull);
  });

  test('déconnecté : seules les routes d\'accès par téléphone sont permises', () {
    expect(redirectFor(SessionStage.signedOut, Routes.phone), isNull);
    expect(redirectFor(SessionStage.signedOut, Routes.otp), isNull);
    expect(redirectFor(SessionStage.signedOut, Routes.settings), Routes.welcome);
  });

  test('parcours d\'inscription imposé dans l\'ordre', () {
    expect(redirectFor(SessionStage.onboarding, Routes.welcome), Routes.onboarding);
    expect(redirectFor(SessionStage.needsProfile, Routes.discussions), Routes.profileSetup);
    expect(redirectFor(SessionStage.needsPermissions, Routes.discussions), Routes.permissions);
  });

  test('prêt : accès aux trois onglets, pas de retour aux écrans de connexion', () {
    for (final r in [Routes.discussions, Routes.groups, Routes.settings]) {
      expect(redirectFor(SessionStage.ready, r), isNull);
    }
    expect(redirectFor(SessionStage.ready, Routes.otp), Routes.discussions);
  });
}
