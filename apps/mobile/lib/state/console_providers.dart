import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/admin_api.dart';
import '../domain/models/console.dart';
import 'messaging_providers.dart';
import '../domain/models/moderation.dart';

final adminApiProvider = Provider<AdminApi>(
  (ref) => throw UnimplementedError('adminApiProvider doit être surchargé'),
);

/// Afficher l'entrée « Administration » (Paramètres) : réponse du serveur, recalculée au
/// changement de compte. Aucune condition locale (numéro, etc.) dans l'application.
final consoleAccessProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(adminApiProvider).consoleAccess();
});

/// Lot 5.5 : page [page] de la liste des comptes (A–Z).
final consoleAccountsPageProvider = FutureProvider.autoDispose.family<ConsolePage<AccountHit>, int>(
  (ref, page) => ref.watch(adminApiProvider).accountsPage(page),
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
