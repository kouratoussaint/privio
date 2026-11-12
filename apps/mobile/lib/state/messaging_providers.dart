import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/util/ids.dart';
import '../core/util/time_format.dart';
import '../data/services/messaging_api.dart';
import '../data/services/realtime_service.dart';
import '../data/storage/local_cache.dart';
import '../core/media/photo_processing.dart';
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

  Future<void> enqueue(OutboxItem item, {List<int>? media}) async {
    await _cache.ensureLoaded();
    await _cache.addOutbox(item, media: media);
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
      final api = ref.read(messagingApiProvider);
      final ChatMessage sent;
      if (item.hasMedia) {
        final media = await _cache.readMedia(LocalCache.outboxMediaKey(item.clientId));
        if (media == null) {
          // Fichier perdu (coffre effacé) : l'envoi ne peut plus aboutir.
          await _cache.removeOutbox(item.clientId);
          state = _cache.outbox;
          _schedule();
          throw const AppFailure(FailureCode.mediaNotFound);
        }
        sent = item.isVoice
            ? await api.sendVoice(
                conversationId: item.conversationId,
                clientMsgId: item.clientId,
                audio: media,
                replyToId: item.replyToId,
                ttlSeconds: item.ttlSeconds,
              )
            : await api.sendPhoto(
                conversationId: item.conversationId,
                clientMsgId: item.clientId,
                jpeg: media,
                caption: item.body.isEmpty ? null : item.body,
                replyToId: item.replyToId,
                ttlSeconds: item.ttlSeconds,
              );
        // L'expéditeur revoit / réécoute son envoi sans le retélécharger.
        await _cache.putMedia(LocalCache.messageMediaKey(sent.id), media, sent.expiresAt);
        if (item.isPhoto) ref.invalidate(photoQuotaProvider);
      } else {
        sent = await api.sendMessage(
          conversationId: item.conversationId,
          clientMsgId: item.clientId,
          body: item.body,
          replyToId: item.replyToId,
          ttlSeconds: item.ttlSeconds,
        );
      }
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
      if (toAppFailure(e).code == FailureCode.mediaNotFound && item.hasMedia) {
        throw toAppFailure(e);
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
    this.kind = 'text',
    this.durationMs,
    this.width,
    this.height,
  });

  final String clientId;
  final String body;
  final String kind;
  final int? durationMs;
  final int? width;
  final int? height;

  bool get isVoice => kind == 'voice';
  bool get isPhoto => kind == 'photo';

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
          kind: o.kind,
          durationMs: o.durationMs,
          width: o.width,
          height: o.height,
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
      // Retiré d'un groupe (ou parti) : plus rien n'est affiché ni gardé.
      if (toAppFailure(e).code == FailureCode.notMember) {
        state = AsyncError(toAppFailure(e), StackTrace.current);
        await _cache.putMessages(conversationId, const []);
        ref.invalidate(conversationsProvider);
      }
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
    await _showSent(sent, item.replyToId);
  }

  /// Vocal : même parcours que le texte (file chiffrée, puis envoi, puis reprise
  /// automatique hors connexion avec le MÊME identifiant client).
  Future<void> sendVoice(
    Uint8List audio, {
    required int durationMs,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    final item = OutboxItem(
      clientId: uuidV4(),
      conversationId: conversationId,
      body: '',
      createdAt: DateTime.now(),
      replyToId: replyToId,
      ttlSeconds: ttlSeconds,
      kind: 'voice',
      durationMs: durationMs,
    );
    final outbox = ref.read(outboxProvider.notifier);
    await outbox.enqueue(item, media: audio);
    final sent = await outbox.sendOne(item);
    if (sent == null) return;
    await _showSent(sent, item.replyToId);
  }

  /// Photo (PHOTO-002) : légende facultative ; même parcours que le texte et les vocaux.
  Future<void> sendPhoto(
    PreparedPhoto photo, {
    String? caption,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    final item = OutboxItem(
      clientId: uuidV4(),
      conversationId: conversationId,
      body: caption?.trim() ?? '',
      createdAt: DateTime.now(),
      replyToId: replyToId,
      ttlSeconds: ttlSeconds,
      kind: 'photo',
      width: photo.width,
      height: photo.height,
    );
    final outbox = ref.read(outboxProvider.notifier);
    await outbox.enqueue(item, media: photo.bytes);
    final sent = await outbox.sendOne(item);
    if (sent == null) return;
    await _showSent(sent, item.replyToId);
  }

  /// Affiche aussitôt le message accepté par le serveur (la réponse montre déjà sa
  /// citation ; le serveur la renverra ensuite).
  Future<void> _showSent(ChatMessage sent, String? replyToId) async {
    final now = state.value ?? const ChatState(messages: []);
    final quoted = replyToId == null
        ? null
        : now.messages.where((m) => m.id == replyToId && !m.isDeleted).firstOrNull;
    final preview = quoted?.body;
    final shown = quoted == null
        ? sent
        : ChatMessage(
            id: sent.id,
            kind: sent.kind,
            senderId: sent.senderId,
            body: sent.body,
            replyToId: replyToId,
            replyPreview: preview == null || preview.length <= 120
                ? preview
                : preview.substring(0, 120),
            replyKind: quoted.kind,
            sentAt: sent.sentAt,
            expiresAt: sent.expiresAt,
            updatedAt: sent.updatedAt,
            mediaPath: sent.mediaPath,
            durationMs: sent.durationMs,
            width: sent.width,
            height: sent.height,
          );
    final messages = [...now.messages.where((m) => m.id != sent.id), shown];
    state = AsyncData(now.copyWith(messages: messages));
    await _cache.putMessages(conversationId, messages);
    ref.invalidate(conversationsProvider);
  }

  Future<void> retry(String clientId) async {
    final item = ref.read(outboxProvider).where((o) => o.clientId == clientId).firstOrNull;
    if (item == null) return;
    if (!item.hasMedia) return send(item.body, clientId: clientId);
    final outbox = ref.read(outboxProvider.notifier);
    final again = item.copyWith(failed: false);
    await outbox.enqueue(again);
    final sent = await outbox.sendOne(again);
    if (sent != null) await _showSent(sent, again.replyToId);
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

  /// Masquage immédiat à l'écran et sur le téléphone (son compris), puis confirmation.
  Future<void> deleteForMe(String messageId) async {
    final now = state.value;
    if (now != null) {
      final messages = now.messages.where((m) => m.id != messageId).toList();
      state = AsyncData(now.copyWith(messages: messages));
    }
    await _cache.removeMessage(conversationId, messageId);
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
    this.voiceMax = const Duration(seconds: 30),
  });

  /// Durée maximale d'un vocal (le serveur la mesure et refuse au-delà).
  final Duration voiceMax;
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
    voiceMax: Duration(seconds: (v['voice_max_seconds'] as num?)?.toInt() ?? 30),
  );

  bool canEdit(ChatMessage m, DateTime now) =>
      m.kind == 'text' && !m.isDeleted && now.isBefore(m.sentAt.add(editWindow));
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

// ------------------------------------------------------------------------
// Photos : compteur du jour, fichiers (coffre local chiffré, puis stockage privé)
// ------------------------------------------------------------------------
/// Photos restantes aujourd'hui (le serveur reste l'autorité au moment de l'envoi).
final photoQuotaProvider = FutureProvider.autoDispose<PhotoQuota>(
  (ref) => ref.watch(messagingApiProvider).getPhotoQuota(),
);

/// Photo à afficher : message reçu ou envoyé, ou envoi en attente.
class PhotoRef {
  PhotoRef.message(ChatMessage m)
    : key = 'msg-${m.id}',
      path = m.mediaPath,
      expiresAt = m.expiresAt;
  const PhotoRef.pending(String clientId) : key = 'out-$clientId', path = null, expiresAt = null;

  /// Clé du coffre local.
  final String key;
  final String? path;
  final DateTime? expiresAt;

  @override
  bool operator ==(Object other) => other is PhotoRef && other.key == key && other.path == path;
  @override
  int get hashCode => Object.hash(key, path);
}

/// Octets d'une photo : du coffre local s'ils y sont, sinon téléchargés (avec le jeton)
/// puis rangés chiffrés jusqu'à l'expiration du message.
final photoBytesProvider = FutureProvider.autoDispose.family<Uint8List, PhotoRef>((
  ref,
  photo,
) async {
  final cache = ref.read(localCacheProvider);
  final local = await cache.readMedia(photo.key);
  if (local != null) return local;
  final path = photo.path;
  final until = photo.expiresAt;
  if (path == null || until == null) throw const AppFailure(FailureCode.mediaNotFound);
  if (!until.isAfter(DateTime.now())) throw const AppFailure(FailureCode.messageExpired);
  try {
    final bytes = await ref.read(messagingApiProvider).downloadPhoto(path);
    await cache.putMedia(photo.key, bytes, until);
    return bytes;
  } on Object catch (e) {
    final failure = toAppFailure(e);
    if (failure.code == FailureCode.network) {
      ref.read(offlineProvider.notifier).report(offline: true);
    }
    throw failure;
  }
});

/// Photo de profil : gardée chiffrée 7 jours (le chemin change à chaque nouvelle photo).
final avatarBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, path) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  final cache = ref.read(localCacheProvider);
  final key = LocalCache.avatarMediaKey(path);
  final local = await cache.readMedia(key);
  if (local != null) return local;
  final bytes = await ref.read(messagingApiProvider).downloadAvatar(path);
  await cache.putMedia(key, bytes, DateTime.now().add(const Duration(days: 7)));
  return bytes;
});

// ------------------------------------------------------------------------
// Groupes (lot 3.3)
// ------------------------------------------------------------------------
/// Invitations reçues (à accepter ou refuser), mises à jour en temps réel.
final invitationsProvider = FutureProvider.autoDispose<List<GroupInvitation>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  ref.listen(realtimeSignalsProvider, (_, next) {
    if (next.value?.event == 'invitation') ref.invalidateSelf();
  });
  return ref.watch(messagingApiProvider).listInvitations();
});

/// Membres d'un groupe (et invitations en attente pour les administrateurs).
final groupMembersProvider = FutureProvider.autoDispose.family<List<GroupMember>, String>((
  ref,
  conversationId,
) {
  ref.listen(realtimeSignalsProvider, (_, next) {
    final s = next.value;
    if (s != null && s.event != 'typing' && s.conversationId == conversationId) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(messagingApiProvider).getMembers(conversationId);
});

/// Action sur un groupe : appel serveur, puis rafraîchissement de la liste, des membres
/// et de la discussion (qui affiche le message système de l'événement).
Future<T> groupAction<T>(
  WidgetRef ref,
  String conversationId,
  Future<T> Function(MessagingApi api) run,
) async {
  try {
    return await run(ref.read(messagingApiProvider));
  } on Object catch (e) {
    throw toAppFailure(e);
  } finally {
    ref
      ..invalidate(conversationsProvider)
      ..invalidate(groupMembersProvider(conversationId))
      ..invalidate(chatProvider(conversationId));
  }
}
