import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/admin_api.dart';
import '../domain/models/console.dart';
import '../domain/models/console_team.dart';
import 'messaging_providers.dart';
import '../domain/models/moderation.dart';

final adminApiProvider = Provider<AdminApi>(
  (ref) => throw UnimplementedError('adminApiProvider doit être surchargé'),
);

/// Afficher l'entrée « Administration » (Paramètres) : réponse du serveur, recalculée au
/// changement de compte. Aucune condition locale (numéro, etc.) dans l'application.
final consoleAccessProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  // Lot 5.8 : ajouté à l'équipe ou retiré (signal « moderation ») : l'entrée suit.
  ref.listen(realtimeSignalsProvider, (_, next) {
    if (next.value?.event == 'moderation') ref.invalidateSelf();
  });
  return ref.watch(adminApiProvider).consoleAccess();
});

/// Lot 5.8 : mon rôle dans la console (relu à chaque ouverture).
final consoleMeProvider = FutureProvider.autoDispose<ConsoleMe>(
  (ref) => ref.watch(adminApiProvider).me(),
);

final consoleTeamProvider = FutureProvider.autoDispose<List<StaffMember>>(
  (ref) => ref.watch(adminApiProvider).team(),
);

/// Groupes : (recherche, filtre, page).
final consoleGroupsPageProvider = FutureProvider.autoDispose
    .family<ConsolePage<ConsoleGroup>, (String, String, int)>(
      (ref, f) => ref
          .watch(adminApiProvider)
          .groupsPage(query: f.$1.isEmpty ? null : f.$1, filter: f.$2, page: f.$3),
    );

final consoleTemplatesProvider = FutureProvider.autoDispose<List<ConsoleTemplate>>(
  (ref) => ref.watch(adminApiProvider).templates(),
);

final blockedSitesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(adminApiProvider).blockedSites(),
);

final moderationStatsProvider = FutureProvider.autoDispose.family<ModerationStats, int>(
  (ref, days) => ref.watch(adminApiProvider).moderationStats(days),
);

/// Lot 5.5 : page de la liste des comptes (A–Z). Lot 5.6 : (filtre, page).
final consoleAccountsPageProvider = FutureProvider.autoDispose
    .family<ConsolePage<AccountHit>, (String, int)>(
      (ref, f) => ref.watch(adminApiProvider).accountsPage(f.$2, filter: f.$1),
    );

/// Lot 5.6 : identifiants réservés.
final reservedHandlesProvider = FutureProvider.autoDispose<ReservedHandles>(
  (ref) => ref.watch(adminApiProvider).reservedHandles(),
);

/// Lot 5.5 : journal (type d'action, période en jours, page).
final consoleJournalPageProvider = FutureProvider.autoDispose
    .family<ConsolePage<JournalEntry>, (String?, int?, int)>(
      (ref, f) => ref.watch(adminApiProvider).journalPage(type: f.$1, days: f.$2, page: f.$3),
    );

final consoleDashboardProvider = FutureProvider.autoDispose<ConsoleDashboard>(
  (ref) => ref.watch(adminApiProvider).dashboard(),
);

// Lot 5.2
final consolePoliciesProvider = FutureProvider.autoDispose<List<ConsolePolicy>>(
  (ref) => ref.watch(adminApiProvider).policies(),
);

final policyHistoryProvider = FutureProvider.autoDispose.family<List<PolicyChange>, String>(
  (ref, key) => ref.watch(adminApiProvider).policyHistory(key),
);

final consoleStatsProvider = FutureProvider.autoDispose<ConsoleStats>(
  (ref) => ref.watch(adminApiProvider).stats(),
);

final consoleJournalProvider = FutureProvider.autoDispose<List<JournalEntry>>(
  (ref) => ref.watch(adminApiProvider).journal(),
);

/// Modifie un réglage puis rafraîchit la liste, l'historique et le journal.
Future<void> savePolicy(WidgetRef ref, ConsolePolicy policy, Object value) async {
  await ref.read(adminApiProvider).setPolicy(policy.key, value);
  ref
    ..invalidate(consolePoliciesProvider)
    ..invalidate(policyHistoryProvider(policy.key))
    ..invalidate(consoleJournalProvider);
}

/// Lot 5.7 : santé du service.
final consoleHealthProvider = FutureProvider.autoDispose<ConsoleHealth>(
  (ref) => ref.watch(adminApiProvider).health(),
);
