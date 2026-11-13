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
  static const newConversation = '/new-conversation';
  static const newGroup = '/new-group';
  static const blockedUsers = '/blocked-users';
  static const archived = '/archived';
  static const help = '/help';
  static const deleteAccount = '/delete-account';
  static const appLock = '/app-lock';
  static const appLockNew = '/app-lock/new';
  static const appLockChange = '/app-lock/change';
  static const appLockDisable = '/app-lock/disable';
  static const storage = '/storage';
  static String chat(String id) => '/chat/$id';
  static String contact(String conversationId) => '/chat/$conversationId/contact';
  static String groupInvite(String conversationId) => '/chat/$conversationId/invite';

  static const signedOutRoutes = {welcome, phone, otp};
  static const homeRoutes = {discussions, groups, settings};

  /// Écrans du parcours d'accès : inaccessibles une fois le compte prêt.
  static const accessRoutes = {splash, onboarding, welcome, phone, otp, profileSetup, permissions};
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
      return Routes.accessRoutes.contains(location) ? Routes.discussions : null;
  }
}
