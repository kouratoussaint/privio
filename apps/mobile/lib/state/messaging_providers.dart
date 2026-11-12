import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/util/ids.dart';
import '../core/util/time_format.dart';
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
  const PendingMessage({
    required this.clientId,
    required this.body,
    this.failed = false,
    this.replyToId,
  });

  final String clientId;
  final String body;
  final bool failed;
  final String? replyToId;
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
  Future<void> send(String text, {String? clientId, String? replyToId, int? ttlSeconds}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final id = clientId ?? uuidV4();
    final current = state.value ?? const ChatState(messages: []);
    state = AsyncData(
      current.copyWith(
        pending: [
          ...current.pending.where((p) => p.clientId != id),
          PendingMessage(clientId: id, body: body, replyToId: replyToId),
        ],
      ),
    );
    try {
      final sent = await ref
          .read(messagingApiProvider)
          .sendMessage(
            conversationId: conversationId,
            clientMsgId: id,
            body: body,
            replyToId: replyToId,
            ttlSeconds: ttlSeconds,
          );
      final now = state.value ?? current;
      // La réponse affiche tout de suite la citation (le serveur la renverra ensuite).
      final quoted = replyToId == null
          ? null
          : now.messages.where((m) => m.id == replyToId && !m.isDeleted).firstOrNull?.body;
      final shown = quoted == null
          ? sent
          : ChatMessage(
              id: sent.id,
              senderId: sent.senderId,
              body: sent.body,
              replyToId: replyToId,
              replyPreview: quoted.length > 120 ? quoted.substring(0, 120) : quoted,
              sentAt: sent.sentAt,
              expiresAt: sent.expiresAt,
              updatedAt: sent.updatedAt,
            );
      state = AsyncData(
        ChatState(
          messages: [...now.messages.where((m) => m.id != sent.id), shown],
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
              p.clientId == id
                  ? PendingMessage(clientId: id, body: body, failed: true, replyToId: replyToId)
                  : p,
          ],
        ),
      );
      throw toAppFailure(e);
    }
  }

  Future<void> _act(Future<void> Function(MessagingApi api) run) async {
    try {
      await run(ref.read(messagingApiProvider));
    } on Object catch (e) {
      throw toAppFailure(e);
    } finally {
      await reload();
    }
  }

  /// Durée des nouveaux messages de la discussion (annoncée aux deux personnes).
  Future<void> setTtl(int seconds) async {
    await _act((api) => api.setConversationTtl(conversationId, seconds));
    ref.invalidate(conversationsProvider);
  }

  Future<void> edit(String messageId, String body) =>
      _act((api) => api.editMessage(messageId, body.trim()));

  Future<void> deleteForEveryone(String messageId) =>
      _act((api) => api.deleteForEveryone(messageId));

  /// Masquage immédiat à l'écran, puis confirmation serveur.
  Future<void> deleteForMe(String messageId) {
    final now = state.value;
    if (now != null) {
      state = AsyncData(
        now.copyWith(messages: now.messages.where((m) => m.id != messageId).toList()),
      );
    }
    return _act((api) => api.deleteForMe(messageId));
  }

  /// Toucher l'emoji déjà choisi le retire ; un autre emoji le remplace.
  Future<void> toggleReaction(String messageId, String emoji) {
    final me = ref.read(currentUserIdProvider);
    final message = state.value?.messages.where((m) => m.id == messageId).firstOrNull;
    final mine = message?.reactions.where((r) => r.userId == me).firstOrNull;
    return _act(
      (api) =>
          mine?.emoji == emoji ? api.removeReaction(messageId) : api.setReaction(messageId, emoji),
    );
  }

  void discardPending(String clientId) {
    final now = state.value;
    if (now == null) return;
    state = AsyncData(
      now.copyWith(pending: now.pending.where((p) => p.clientId != clientId).toList()),
    );
  }
}

/// Règles affichées côté client (le serveur reste l'autorité et refuse au-delà).
class MessagingRules {
  const MessagingRules({
    this.editWindow = const Duration(minutes: 60),
    this.deleteForAllWindow = const Duration(hours: 72),
    this.minTtlSeconds = 300,
    this.maxTtlSeconds = 72 * 3600,
  });

  final Duration editWindow;
  final Duration deleteForAllWindow;
  final int minTtlSeconds;
  final int maxTtlSeconds;

  /// Durées proposées dans les bornes du serveur, éventuellement plafonnées.
  List<int> ttlChoices({int? cap}) => [
    for (final s in kTtlChoices)
      if (s >= minTtlSeconds && s <= maxTtlSeconds && (cap == null || s <= cap)) s,
  ];

  factory MessagingRules.fromPolicies(Map<String, Object?> v) => MessagingRules(
    editWindow: Duration(minutes: (v['message_edit_window_minutes'] as num?)?.toInt() ?? 60),
    deleteForAllWindow: Duration(hours: (v['message_delete_for_all_hours'] as num?)?.toInt() ?? 72),
    minTtlSeconds: ((v['message_ttl_min_minutes'] as num?)?.toInt() ?? 5) * 60,
    maxTtlSeconds: ((v['message_ttl_hours'] as num?)?.toInt() ?? 72) * 3600,
  );

  bool canEdit(ChatMessage m, DateTime now) =>
      !m.isDeleted && now.isBefore(m.sentAt.add(editWindow));
  bool canDeleteForAll(ChatMessage m, DateTime now) =>
      !m.isDeleted && now.isBefore(m.sentAt.add(deleteForAllWindow));
}

final messagingRulesProvider = FutureProvider<MessagingRules>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const MessagingRules();
  try {
    return MessagingRules.fromPolicies(await ref.watch(messagingApiProvider).getClientPolicies());
  } on Object {
    return const MessagingRules(); // valeurs validées par défaut (B1)
  }
});

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
