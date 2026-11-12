import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/util/ids.dart';
import '../core/util/time_format.dart';
import '../data/services/messaging_api.dart';
import '../data/services/realtime_service.dart';
import '../data/storage/local_cache.dart';
import '../domain/models/messaging.dart';
import 'providers.dart';
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

bool _isNetwork(Object e) => toAppFailure(e).code == FailureCode.network;

// ------------------------------------------------------------------------
// Hors connexion
// ------------------------------------------------------------------------
/// Vrai quand le dernier échange avec le serveur a échoué faute de réseau.
final offlineProvider = NotifierProvider<OfflineController, bool>(OfflineController.new);

class OfflineController extends Notifier<bool> {
  @override
  bool build() => false;

  void report({required bool offline}) {
    if (state == offline) return;
    state = offline;
    // Retour du réseau : les messages en attente partent aussitôt.
    if (!offline) unawaited(ref.read(outboxProvider.notifier).flush());
  }
}

// ------------------------------------------------------------------------
// File d'envoi hors ligne (persistée, chiffrée)
// ------------------------------------------------------------------------
final outboxProvider = NotifierProvider<OutboxController, List<OutboxItem>>(OutboxController.new);

class OutboxController extends Notifier<List<OutboxItem>> {
  static const retryEvery = Duration(seconds: 15);
  Timer? _timer;
  bool _flushing = false;

  LocalCache get _cache => ref.read(localCacheProvider);

  @override
  List<OutboxItem> build() {
    ref.watch(currentUserIdProvider);
    ref.onDispose(() => _timer?.cancel());
    // Reconnexion temps réel ou retour dans l'app : nouvel essai.
    ref.listen(realtimeSignalsProvider, (_, next) {
      final e = next.value?.event;
      if (e == 'reconnected' || e == 'resume') unawaited(flush());
    });
    unawaited(
      _cache.ensureLoaded().then((_) {
        state = _cache.outbox;
        _schedule();
      }),
    );
    return const [];
  }

  void _schedule() {
    _timer?.cancel();
    if (state.any((o) => !o.failed)) {
      _timer = Timer.periodic(retryEvery, (_) => unawaited(flush()));
    }
  }

  Future<void> enqueue(OutboxItem item) async {
    await _cache.ensureLoaded();
    await _cache.addOutbox(item);
    state = _cache.outbox;
    _schedule();
  }

  Future<void> discard(String clientId) async {
    await _cache.removeOutbox(clientId);
    state = _cache.outbox;
    _schedule();
  }

  /// Envoie un message de la file. Réseau absent : il reste en attente (null).
  /// Refus du serveur : marqué en échec et l'erreur est relancée.
  Future<ChatMessage?> sendOne(OutboxItem item) async {
    try {
      final sent = await ref
          .read(messagingApiProvider)
          .sendMessage(
            conversationId: item.conversationId,
            clientMsgId: item.clientId,
            body: item.body,
            replyToId: item.replyToId,
            ttlSeconds: item.ttlSeconds,
          );
      await _cache.removeOutbox(item.clientId);
      state = _cache.outbox;
      _schedule();
      ref.read(offlineProvider.notifier).report(offline: false);
      return sent;
    } on Object catch (e) {
      if (_isNetwork(e)) {
        ref.read(offlineProvider.notifier).report(offline: true);
        _schedule();
        return null;
      }
      await _cache.updateOutbox(item.copyWith(failed: true));
      state = _cache.outbox;
      _schedule();
      throw toAppFailure(e);
    }
  }

  /// Renvoie tout ce qui attend (même identifiant client : jamais de doublon).
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (final item in List.of(state.where((o) => !o.failed))) {
        try {
          final sent = await sendOne(item);
          if (sent == null) break; // toujours hors connexion
          // La conversation concernée se recharge d'elle-même (elle observe la file).
          unawaited(ref.read(conversationsProvider.notifier).refresh());
        } on AppFailure {
          // Marqué en échec : l'utilisateur décidera (réessayer ou abandonner).
        }
      }
    } finally {
      _flushing = false;
    }
  }
}

// ------------------------------------------------------------------------
// « En train d'écrire… » (signal temps réel sans contenu, 5 s)
// ------------------------------------------------------------------------
const kTypingVisible = Duration(seconds: 5);

final typingProvider = NotifierProvider<TypingController, Set<String>>(TypingController.new);

class TypingController extends Notifier<Set<String>> {
  final Map<String, Timer> _timers = {};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    ref.listen(realtimeSignalsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      final id = s.conversationId;
      if (id == null) return;
      if (s.event == 'typing') {
        _timers[id]?.cancel();
        _timers[id] = Timer(kTypingVisible, () => _clear(id));
        state = {...state, id};
      } else if (s.event == 'message') {
        _clear(id); // le message est arrivé : l'indicateur disparaît
      }
    });
    return const {};
  }

  void _clear(String id) {
    _timers.remove(id)?.cancel();
    if (state.contains(id)) state = {...state}..remove(id);
  }
}

// ------------------------------------------------------------------------
// Liste des discussions (écran 08) — d'abord le cache local, puis le serveur
// ------------------------------------------------------------------------
final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<ConversationSummary>>(
      ConversationsController.new,
    );

class ConversationsController extends AsyncNotifier<List<ConversationSummary>> {
  static const purgeEvery = Duration(seconds: 30);

  @override
  Future<List<ConversationSummary>> build() async {
    // Changement de compte : la liste est reconstruite (aucune fuite entre comptes).
    if (ref.watch(currentUserIdProvider) == null) return const [];
    final cache = ref.watch(localCacheProvider);
    await cache.ensureLoaded();
    ref.listen(realtimeSignalsProvider, (_, next) {
      if (next.value?.event == 'typing') return;
      unawaited(refresh());
    });
    // Effacement local des messages expirés, même sans réseau.
    final purge = Timer.periodic(purgeEvery, (_) => unawaited(cache.purgeExpired()));
    ref.onDispose(purge.cancel);
    ref.read(outboxProvider);
    unawaited(Future<void>.microtask(refresh));
    return cache.conversations;
  }

  /// Synchronise avec le serveur ; hors connexion, la liste locale reste affichée.
  Future<void> refresh() async {
    final api = ref.read(messagingApiProvider);
    try {
      final list = await api.listConversations();
      state = AsyncData(list);
      await ref.read(localCacheProvider).putConversations(list);
      ref.read(offlineProvider.notifier).report(offline: false);
      // Accusé « reçu » : les messages listés sont arrivés sur cet appareil.
      for (final c in list) {
        if (c.unreadCount > 0 && c.lastSentAt != null) {
          unawaited(
            api.markConversation(c.id, deliveredUpTo: c.lastSentAt).catchError((Object _) {}),
          );
        }
      }
    } on Object catch (e) {
      if (_isNetwork(e)) {
        ref.read(offlineProvider.notifier).report(offline: true);
      } else if (!state.hasValue || (state.value?.isEmpty ?? true)) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }

  /// Épingler / archiver (état personnel), affiché aussitôt puis confirmé.
  Future<void> setFlags(String conversationId, {bool? pinned, bool? archived}) async {
    final before = state.value ?? const [];
    state = AsyncData([
      for (final c in before)
        c.id == conversationId ? c.copyWith(pinned: pinned, archived: archived) : c,
    ]);
    try {
      await ref
          .read(messagingApiProvider)
          .setConversationFlags(conversationId, pinned: pinned, archived: archived);
      await refresh();
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
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
// Conversation (écran 10) — cache local, file d'envoi, synchronisation
// ------------------------------------------------------------------------
class PendingMessage {
  const PendingMessage({
    required this.clientId,
    required this.body,
    this.failed = false,
    this.replyToId,
    this.ttlSeconds,
  });

  final String clientId;
  final String body;

  /// Refusé par le serveur (sinon : simplement en attente du réseau).
  final bool failed;
  final String? replyToId;
  final int? ttlSeconds;
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
  DateTime? _lastTypingSent;

  static const typingThrottle = Duration(seconds: 4);

  LocalCache get _cache => ref.read(localCacheProvider);

  List<PendingMessage> _pendingFrom(List<OutboxItem> outbox) => [
    for (final o in outbox)
      if (o.conversationId == conversationId)
        PendingMessage(
          clientId: o.clientId,
          body: o.body,
          failed: o.failed,
          replyToId: o.replyToId,
          ttlSeconds: o.ttlSeconds,
        ),
  ];

  @override
  Future<ChatState> build() async {
    final cache = ref.watch(localCacheProvider);
    await cache.ensureLoaded();
    ref.listen(realtimeSignalsProvider, (_, next) {
      final signal = next.value;
      if (signal == null || signal.event == 'typing') return;
      if (signal.conversationId == null || signal.conversationId == conversationId) {
        unawaited(reload());
      }
    });
    ref.listen(outboxProvider, (prev, next) {
      int mine(List<OutboxItem>? l) =>
          (l ?? const <OutboxItem>[]).where((o) => o.conversationId == conversationId).length;
      final current = state.value;
      if (current != null) state = AsyncData(current.copyWith(pending: _pendingFrom(next)));
      // Un message en attente vient de partir : on affiche la version du serveur.
      if (mine(next) < mine(prev)) unawaited(reload());
    });
    unawaited(Future<void>.microtask(reload));
    return ChatState(
      messages: cache.messages(conversationId),
      pending: _pendingFrom(ref.read(outboxProvider)),
    );
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
      await _cache.putMessages(conversationId, messages);
      ref.read(offlineProvider.notifier).report(offline: false);
      _markRead(messages);
    } on Object catch (e) {
      // Hors connexion : on garde l'affichage local (toujours filtré par expiration).
      if (_isNetwork(e)) ref.read(offlineProvider.notifier).report(offline: true);
    }
  }

  /// Signale « en train d'écrire » au plus toutes les 4 s (sans contenu).
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null && now.difference(_lastTypingSent!) < typingThrottle) return;
    _lastTypingSent = now;
    unawaited(
      ref.read(messagingApiProvider).signalTyping(conversationId).catchError((Object _) {}),
    );
  }

  /// Envoi : le message entre d'abord dans la file locale chiffrée (il survit à une
  /// coupure ou à la fermeture de l'app), puis part ; hors connexion il attend et
  /// repart seul, avec le MÊME identifiant client (pas de doublon côté serveur).
  Future<void> send(String text, {String? clientId, String? replyToId, int? ttlSeconds}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final outbox = ref.read(outboxProvider.notifier);
    final existing = ref.read(outboxProvider).where((o) => o.clientId == clientId).firstOrNull;
    final item =
        existing?.copyWith(failed: false) ??
        OutboxItem(
          clientId: clientId ?? uuidV4(),
          conversationId: conversationId,
          body: body,
          createdAt: DateTime.now(),
          replyToId: replyToId,
          ttlSeconds: ttlSeconds,
        );
    await outbox.enqueue(item);
    final sent = await outbox.sendOne(item);
    if (sent == null) return;
    final now = state.value ?? const ChatState(messages: []);
    // La réponse affiche tout de suite la citation (le serveur la renverra ensuite).
    final quoted = item.replyToId == null
        ? null
        : now.messages.where((m) => m.id == item.replyToId && !m.isDeleted).firstOrNull?.body;
    final shown = quoted == null
        ? sent
        : ChatMessage(
            id: sent.id,
            senderId: sent.senderId,
            body: sent.body,
            replyToId: item.replyToId,
            replyPreview: quoted.length > 120 ? quoted.substring(0, 120) : quoted,
            sentAt: sent.sentAt,
            expiresAt: sent.expiresAt,
            updatedAt: sent.updatedAt,
          );
    final messages = [...now.messages.where((m) => m.id != sent.id), shown];
    state = AsyncData(now.copyWith(messages: messages));
    await _cache.putMessages(conversationId, messages);
    ref.invalidate(conversationsProvider);
  }

  Future<void> retry(String clientId) {
    final item = ref.read(outboxProvider).where((o) => o.clientId == clientId).firstOrNull;
    if (item == null) return Future.value();
    return send(item.body, clientId: clientId);
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

  /// Masquage immédiat à l'écran et sur le téléphone, puis confirmation serveur.
  Future<void> deleteForMe(String messageId) async {
    final now = state.value;
    if (now != null) {
      final messages = now.messages.where((m) => m.id != messageId).toList();
      state = AsyncData(now.copyWith(messages: messages));
      await _cache.putMessages(conversationId, messages);
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

  Future<void> discardPending(String clientId) =>
      ref.read(outboxProvider.notifier).discard(clientId);
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
