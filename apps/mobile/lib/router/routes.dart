import '../state/session_controller.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const phone = '/phone';
  static const otp = '/otp';
  static const profileSetup = '/profile-setup';
  static const permissions = '/permissions';
  static const discussions = '/discussions';
  static const groups = '/groups';
  static const settings = '/settings';

  static const signedOutRoutes = {welcome, phone, otp};
  static const homeRoutes = {discussions, groups, settings};
}

/// Redirection pure, testée unitairement. `stage == null` : chargement ou erreur.
String? redirectFor(SessionStage? stage, String location) {
  String? goTo(String target) => location == target ? null : target;
  switch (stage) {
    case null:
      return goTo(Routes.splash);
    case SessionStage.onboarding:
      return goTo(Routes.onboarding);
    case SessionStage.signedOut:
      return Routes.signedOutRoutes.contains(location) ? null : Routes.welcome;
    case SessionStage.needsProfile:
      return goTo(Routes.profileSetup);
    case SessionStage.needsPermissions:
      return goTo(Routes.permissions);
    case SessionStage.ready:
      final inHome = Routes.homeRoutes.any((r) => location == r || location.startsWith('$r/'));
      return inHome ? null : Routes.discussions;
  }
}
