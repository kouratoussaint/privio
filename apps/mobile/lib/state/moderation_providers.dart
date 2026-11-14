import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/moderation.dart';
import 'console_providers.dart';
import 'messaging_providers.dart';
import 'providers.dart';

/// Situation du compte connecté (lot 5.3) : suspension, avertissement non lu. Relue dès
/// que la console décide (signal « moderation »), au retour dans l'app et après une coupure.
final moderationStatusProvider = FutureProvider<ModerationStatus>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return ModerationStatus.none;
  ref.listen(realtimeSignalsProvider, (_, next) {
    final e = next.value?.event;
    if (e == 'moderation' || e == 'resume' || e == 'reconnected') ref.invalidateSelf();
  });
  try {
    return await ref.watch(accountApiProvider).moderationStatus();
  } on Object {
    // Hors connexion : rien n'est affiché ; le serveur refuse de toute façon les envois.
    return ModerationStatus.none;
  }
});

/// Lot 5.4 : mes demandes d'assistance, relues à l'arrivée d'une réponse.
final mySupportRequestsProvider = FutureProvider.autoDispose<List<SupportRequest>>((ref) {
  ref.listen(realtimeSignalsProvider, (_, next) {
    final e = next.value?.event;
    if (e == 'support' || e == 'resume' || e == 'reconnected') ref.invalidateSelf();
  });
  return ref.watch(messagingApiProvider).mySupportRequests();
});

// ---------------------------------------------------------------------------
// Console
// ---------------------------------------------------------------------------
final consoleReportsProvider = FutureProvider.autoDispose.family<List<ModerationReport>, String>(
  (ref, status) => ref.watch(adminApiProvider).reports(status),
);

final consoleAppealsProvider = FutureProvider.autoDispose<List<Sanction>>(
  (ref) => ref.watch(adminApiProvider).appeals(),
);

final userSanctionsProvider = FutureProvider.autoDispose.family<List<Sanction>, String>(
  (ref, userId) => ref.watch(adminApiProvider).sanctions(userId),
);

/// Après une décision : files, contestations, tableau de bord et journal à jour.
void refreshModeration(WidgetRef ref) {
  for (final s in const ['open', 'reviewing', 'closed']) {
    ref.invalidate(consoleReportsProvider(s));
  }
  ref
    ..invalidate(consoleAppealsProvider)
    ..invalidate(consoleDashboardProvider)
    ..invalidate(consoleJournalProvider);
}

/// Lot 5.4 : recherche de comptes (texte saisi → résultats).
final accountSearchProvider = FutureProvider.autoDispose.family<List<AccountHit>, String>(
  (ref, query) => ref.watch(adminApiProvider).searchAccounts(query),
);

final consoleAccountProvider = FutureProvider.autoDispose.family<ConsoleAccount, String>(
  (ref, userId) => ref.watch(adminApiProvider).account(userId),
);
