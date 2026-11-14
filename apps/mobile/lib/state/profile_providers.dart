import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/messaging.dart';
import 'messaging_providers.dart';

/// Lot 7.1a : fiche d'un contact (« À propos » et photo selon ses réglages).
final contactProfileProvider = FutureProvider.autoDispose.family<ContactProfile?, String>(
  (ref, userId) => ref.watch(messagingApiProvider).getContactProfile(userId),
);

/// Groupes en commun avec un contact.
final commonGroupsProvider = FutureProvider.autoDispose.family<List<CommonGroup>, String>(
  (ref, userId) => ref.watch(messagingApiProvider).listCommonGroups(userId),
);

/// Photos et vocaux encore présents dans une discussion ; relus quand elle change.
final conversationMediaProvider = FutureProvider.autoDispose.family<List<ChatMessage>, String>((
  ref,
  conversationId,
) {
  ref.listen(realtimeSignalsProvider, (_, next) {
    final s = next.value;
    if (s != null &&
        (s.conversationId == conversationId || s.event == 'resume') &&
        (s.event == 'message' || s.event == 'message_changed' || s.event == 'resume')) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(messagingApiProvider).listConversationMedia(conversationId);
});
