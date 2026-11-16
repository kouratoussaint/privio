import '../state/session_controller.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const phone = '/phone';
  static const otp = '/otp';
  static const profileSetup = '/profile-setup';
  static const permissions = '/permissions';

  /// Lot 8.4a : code de vérification après le SMS (compte protégé).
  static const twoStep = '/two-step';
  static const discussions = '/discussions';
  static const groups = '/groups';
  static const settings = '/settings';
  static const newConversation = '/new-conversation';
  static const newGroup = '/new-group';
  static const blockedUsers = '/blocked-users';
  static const archived = '/archived';

  /// Lot 10.2 : discussions cachées (après le code Privio).
  static const hidden = '/hidden';

  /// Lot 7.2c1 : archives d'une seule liste (« discussions » ou « groupes ») quand les
  /// groupes sont séparés des discussions.
  static String archivedOf(String kind) => '$archived?kind=$kind';
  static const help = '/help';
  static const discover = '/discover';
  static const deleteAccount = '/delete-account';
  static const appLock = '/app-lock';
  static const appLockNew = '/app-lock/new';
  static const appLockChange = '/app-lock/change';
  static const appLockDisable = '/app-lock/disable';
  static const storage = '/storage';
  static const privacy = '/privacy';

  /// Lot 8.3a : sous-écrans des Paramètres et favoris de toutes les discussions.
  static const security = '/security';
  static const notificationSettings = '/notification-settings';
  static const chatSettings = '/chat-settings';
  static const favorites = '/favorites';
  static const requests = '/requests';
  static const console = '/console';
  static const mySupport = '/support';
  static const joinGroup = '/join-group';
  static const myProfile = '/me';
  static String chat(String id) => '/chat/$id';
  static String contact(String conversationId) => '/chat/$conversationId/contact';
  static String groupInvite(String conversationId) => '/chat/$conversationId/invite';
  static String groupCode(String conversationId) => '/chat/$conversationId/code';

  static const signedOutRoutes = {welcome, phone, otp};
  static const homeRoutes = {discussions, groups, settings};

  /// Écrans du parcours d'accès : inaccessibles une fois le compte prêt.
  static const accessRoutes = {
    splash,
    onboarding,
    welcome,
    phone,
    otp,
    twoStep,
    profileSetup,
    permissions,
  };
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
    case SessionStage.needsTwoStep:
      return goTo(Routes.twoStep);
    case SessionStage.needsProfile:
      return goTo(Routes.profileSetup);
    case SessionStage.needsPermissions:
      return goTo(Routes.permissions);
    case SessionStage.ready:
      return Routes.accessRoutes.contains(location) ? Routes.discussions : null;
  }
}
