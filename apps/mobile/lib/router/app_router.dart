import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/session_controller.dart';
import '../ui/features/auth/otp_screen.dart';
import '../ui/features/conversations/chat_screen.dart';
import '../ui/features/conversations/new_conversation_screen.dart';
import '../ui/features/auth/phone_screen.dart';
import '../ui/features/auth/welcome_screen.dart';
import '../ui/features/groups/group_screens.dart';
import '../ui/features/home/archived_screen.dart';
import '../ui/features/home/discussions_tab.dart';
import '../ui/features/home/groups_tab.dart';
import '../ui/features/home/home_shell.dart';
import '../ui/features/onboarding/onboarding_screen.dart';
import '../ui/features/permissions/permissions_screen.dart';
import '../ui/features/profile_setup/profile_setup_screen.dart';
import '../ui/features/settings/blocked_users_screen.dart';
import '../ui/features/settings/delete_account_screen.dart';
import '../ui/features/settings/help_screen.dart';
import '../ui/features/settings/settings_tab.dart';
import '../ui/features/splash/splash_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final stage = session.hasError ? null : session.value?.stage;
      return redirectFor(stage, state.matchedLocation);
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.phone, builder: (_, _) => const PhoneScreen()),
      GoRoute(
        path: Routes.otp,
        builder: (_, state) => OtpScreen(phoneE164: state.uri.queryParameters['phone'] ?? ''),
      ),
      GoRoute(path: Routes.profileSetup, builder: (_, _) => const ProfileSetupScreen()),
      GoRoute(path: Routes.permissions, builder: (_, _) => const PermissionsScreen()),
      GoRoute(path: Routes.newConversation, builder: (_, _) => const NewConversationScreen()),
      GoRoute(path: Routes.newGroup, builder: (_, _) => const NewGroupScreen()),
      GoRoute(path: Routes.blockedUsers, builder: (_, _) => const BlockedUsersScreen()),
      GoRoute(path: Routes.archived, builder: (_, _) => const ArchivedScreen()),
      GoRoute(path: Routes.help, builder: (_, _) => const HelpScreen()),
      GoRoute(path: Routes.deleteAccount, builder: (_, _) => const DeleteAccountScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'contact',
            builder: (_, state) =>
                ConversationInfoScreen(conversationId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'invite',
            builder: (_, state) => InviteMembersScreen(conversationId: state.pathParameters['id']!),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.discussions, builder: (_, _) => const DiscussionsTab())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.groups, builder: (_, _) => const GroupsTab())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsTab())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
