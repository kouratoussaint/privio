import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/util/ids.dart';
import '../data/services/messaging_api.dart';
import '../data/services/realtime_service.dart';
import '../domain/models/messaging.dart';
import 'session_controller.dart';

final messagingApiProvider = Provider<MessagingApi>(
  (ref) => throw UnimplementedError('messagingApiProvider doit être surchargé'),
);
final realtimeServiceProvider = Provider<RealtimeService>(
  (ref) => throw UnimplementedError('realtimeServiceProvider doit être surchargé'),
);

/// Identifiant du compte connecté (null si déconnecté ou profil absent).
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionControllerProvider).value?.account?.userId,
);

/// Flux des signaux temps réel, ouvert tant qu'un compte est connecté.
final realtimeSignalsProvider = StreamProvider<RealtimeSignal>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final service = ref.watch(realtimeServiceProvider);
  if (userId == null) return const Stream.empty();
  unawaited(service.start(userId).catchError((Object _) {}));
  ref.onDispose(() => unawaited(service.stop().catchError((Object _) {})));
  return service.signals;
});

/// État de la connexion temps réel (affiché dans Paramètres).
final realtimeStatusProvider = Provider<RealtimeService>(
  (ref) => ref.watch(realtimeServiceProvider),
);

// ------------------------------------------------------------------------
// Liste des discussions (écran 08)
// ------------------------------------------------------------------------
final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<ConversationSummary>>(
      ConversationsController.new,
    );

class ConversationsController extends AsyncNotifier<List<ConversationSummary>> {
  @override
  Future<List<ConversationSummary>> build() async {
    // Changement de compte : la liste est reconstruite (aucune fuite entre comptes).
    if (ref.watch(currentUserIdProvider) == null) return const [];
    ref.listen(realtimeSignalsProvider, (_, _) => ref.invalidateSelf());
    final api = ref.watch(messagingApiProvider);
    final list = await api.listConversations();
    // Accusé « reçu » : les messages listés sont arrivés sur cet appareil.
    for (final c in list) {
      if (c.unreadCount > 0 && c.lastSentAt != null) {
        unawaited(
          api.markConversation(c.id, deliveredUpTo: c.lastSentAt).catchError((Object _) {}),
        );
      }
    }
    return list.where((c) => !c.archived).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Résumé d'une discussion (en-tête de l'écran de conversation).
final conversationSummaryProvider = Provider.family<ConversationSummary?, String>((ref, id) {
  final list = ref.watch(conversationsProvider).value ?? const [];
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

// ------------------------------------------------------------------------
// Conversation (écran 10, version de base du lot 2.2)
// ------------------------------------------------------------------------
class PendingMessage {
  const PendingMessage({required this.clientId, required this.body, this.failed = false});

  final String clientId;
  final String body;
  final bool failed;
}

class ChatState {
  const ChatState({required this.messages, this.pending = const []});

  final List<ChatMessage> messages;
  final List<PendingMessage> pending;

  ChatState copyWith({List<ChatMessage>? messages, List<PendingMessage>? pending}) =>
      ChatState(messages: messages ?? this.messages, pending: pending ?? this.pending);
}

final chatProvider = AsyncNotifierProvider.autoDispose.family<ChatController, ChatState, String>(
  ChatController.new,
);

class ChatController extends AsyncNotifier<ChatState> {
  ChatController(this.conversationId);

  final String conversationId;

  @override
  Future<ChatState> build() async {
    ref.listen(realtimeSignalsProvider, (_, next) {
      final signal = next.value;
      if (signal == null || signal.conversationId == conversationId) unawaited(reload());
    });
    final messages = await ref.watch(messagingApiProvider).getMessages(conversationId);
    _markRead(messages);
    return ChatState(messages: messages, pending: state.value?.pending ?? const []);
  }

  void _markRead(List<ChatMessage> messages) {
    final me = ref.read(currentUserIdProvider);
    final lastIncoming = messages.where((m) => m.senderId != me).map((m) => m.sentAt);
    if (lastIncoming.isEmpty) return;
    final latest = lastIncoming.reduce((a, b) => a.isAfter(b) ? a : b);
    unawaited(
      ref
          .read(messagingApiProvider)
          .markConversation(conversationId, deliveredUpTo: latest, readUpTo: latest)
          .then((_) => ref.invalidate(conversationsProvider))
          .catchError((Object _) {}),
    );
  }

  Future<void> reload() async {
    try {
      final messages = await ref.read(messagingApiProvider).getMessages(conversationId);
      final current = state.value ?? const ChatState(messages: []);
      state = AsyncData(current.copyWith(messages: messages));
      _markRead(messages);
    } on Object {
      // Réseau indisponible : on garde l'affichage actuel (filtré par expiration).
    }
  }

  /// Envoi avec affichage immédiat ; en cas d'échec, le message reste « à renvoyer »
  /// avec le MÊME identifiant client (pas de doublon côté serveur).
  Future<void> send(String text, {String? clientId}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final id = clientId ?? uuidV4();
    final current = state.value ?? const ChatState(messages: []);
    state = AsyncData(
      current.copyWith(
        pending: [
          ...current.pending.where((p) => p.clientId != id),
          PendingMessage(clientId: id, body: body),
        ],
      ),
    );
    try {
      final sent = await ref
          .read(messagingApiProvider)
          .sendMessage(conversationId: conversationId, clientMsgId: id, body: body);
      final now = state.value ?? current;
      state = AsyncData(
        ChatState(
          messages: [...now.messages.where((m) => m.id != sent.id), sent],
          pending: now.pending.where((p) => p.clientId != id).toList(),
        ),
      );
      ref.invalidate(conversationsProvider);
    } on Object catch (e) {
      final now = state.value ?? current;
      state = AsyncData(
        now.copyWith(
          pending: [
            for (final p in now.pending)
              p.clientId == id ? PendingMessage(clientId: id, body: body, failed: true) : p,
          ],
        ),
      );
      throw toAppFailure(e);
    }
  }

  void discardPending(String clientId) {
    final now = state.value;
    if (now == null) return;
    state = AsyncData(
      now.copyWith(pending: now.pending.where((p) => p.clientId != clientId).toList()),
    );
  }
}

// ------------------------------------------------------------------------
// Blocages
// ------------------------------------------------------------------------
final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>(
  (ref) => ref.watch(messagingApiProvider).listBlockedUsers(),
);

Future<void> setBlocked(WidgetRef ref, String userId, {required bool blocked}) async {
  final api = ref.read(messagingApiProvider);
  if (blocked) {
    await api.blockUser(userId);
  } else {
    await api.unblockUser(userId);
  }
  ref
    ..invalidate(blockedUsersProvider)
    ..invalidate(conversationsProvider);
}
