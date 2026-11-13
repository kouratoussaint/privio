import 'package:flutter_test/flutter_test.dart';
import 'package:privio/router/routes.dart';
import 'package:privio/state/session_controller.dart';

void main() {
  test('chargement → écran de démarrage', () {
    expect(redirectFor(null, Routes.discussions), Routes.splash);
    expect(redirectFor(null, Routes.splash), isNull);
  });

  test('déconnecté\u202F: seules les routes d’accès par téléphone sont permises', () {
    expect(redirectFor(SessionStage.signedOut, Routes.phone), isNull);
    expect(redirectFor(SessionStage.signedOut, Routes.otp), isNull);
    expect(redirectFor(SessionStage.signedOut, Routes.settings), Routes.welcome);
  });

  test('parcours d’inscription imposé dans l’ordre', () {
    expect(redirectFor(SessionStage.onboarding, Routes.welcome), Routes.onboarding);
    expect(redirectFor(SessionStage.needsProfile, Routes.discussions), Routes.profileSetup);
    expect(redirectFor(SessionStage.needsPermissions, Routes.discussions), Routes.permissions);
  });

  test(
    'prêt\u202F: accès aux onglets et aux discussions, pas de retour aux écrans de connexion',
    () {
      for (final r in [
        Routes.discussions,
        Routes.groups,
        Routes.settings,
        Routes.newConversation,
        Routes.blockedUsers,
        Routes.chat('abc'),
        Routes.contact('abc'),
      ]) {
        expect(redirectFor(SessionStage.ready, r), isNull, reason: r);
      }
      for (final r in [Routes.otp, Routes.welcome, Routes.profileSetup, Routes.splash]) {
        expect(redirectFor(SessionStage.ready, r), Routes.discussions, reason: r);
      }
    },
  );

  test('déconnecté\u202F: aucune discussion accessible', () {
    expect(redirectFor(SessionStage.signedOut, Routes.chat('abc')), Routes.welcome);
  });
}
