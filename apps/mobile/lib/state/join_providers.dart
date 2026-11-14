import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/messaging.dart';
import 'messaging_providers.dart';

/// Lot 7.1b : un événement qui concerne les demandes d'adhésion (ou le retour dans l'app).
bool _joinEvent(String? event) =>
    event == 'join_request' || event == 'resume' || event == 'reconnected';

/// Réglages d'entrée d'un groupe (administrateurs) : approbation, demandes en attente.
final groupJoinSettingsProvider = FutureProvider.autoDispose.family<GroupJoinSettings, String>((
  ref,
  conversationId,
) {
  ref.listen(realtimeSignalsProvider, (_, next) {
    final s = next.value;
    if (_joinEvent(s?.event) &&
        (s?.conversationId == null || s?.conversationId == conversationId)) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(messagingApiProvider).getGroupJoinSettings(conversationId);
});

/// Demandes reçues par les administrateurs d'un groupe, à jour en temps réel.
final groupJoinRequestsProvider = FutureProvider.autoDispose.family<List<JoinRequest>, String>((
  ref,
  conversationId,
) {
  ref.listen(realtimeSignalsProvider, (_, next) {
    final s = next.value;
    if (_joinEvent(s?.event) &&
        (s?.conversationId == null || s?.conversationId == conversationId)) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(messagingApiProvider).listGroupJoinRequests(conversationId);
});

/// Mes demandes en attente (onglet Groupes).
final myJoinRequestsProvider = FutureProvider.autoDispose<List<MyJoinRequest>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  ref.listen(realtimeSignalsProvider, (_, next) {
    if (_joinEvent(next.value?.event)) ref.invalidateSelf();
  });
  return ref.watch(messagingApiProvider).listMyJoinRequests();
});

/// Membres d'un groupe pour les @mentions : lus à l'ouverture de la discussion, puis à
/// chaque nouvelle mention (pas à chaque message, contrairement à la fiche du groupe).
final mentionMembersProvider = FutureProvider.autoDispose.family<List<GroupMember>, String>(
  (ref, conversationId) => ref.watch(messagingApiProvider).getMembers(conversationId),
);
