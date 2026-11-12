import 'dart:async';

import '../../domain/models/messaging.dart';
import 'local_store.dart';

/// Message en attente d'envoi (file hors ligne), conservé chiffré sur le téléphone.
class OutboxItem {
  const OutboxItem({
    required this.clientId,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.replyToId,
    this.ttlSeconds,
    this.failed = false,
  });

  final String clientId;
  final String conversationId;
  final String body;
  final DateTime createdAt;
  final String? replyToId;
  final int? ttlSeconds;

  /// Refusé par le serveur pour une autre raison que le réseau (ex. blocage).
  final bool failed;

  /// Un message jamais parti n'attend pas indéfiniment : 72 h au plus.
  bool isStale(DateTime now) => now.difference(createdAt) > const Duration(hours: 72);

  OutboxItem copyWith({bool? failed}) => OutboxItem(
    clientId: clientId,
    conversationId: conversationId,
    body: body,
    createdAt: createdAt,
    replyToId: replyToId,
    ttlSeconds: ttlSeconds,
    failed: failed ?? this.failed,
  );

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'conversation_id': conversationId,
    'body': body,
    'created_at': createdAt.toUtc().toIso8601String(),
    'reply_to_id': replyToId,
    'ttl_seconds': ttlSeconds,
    'failed': failed,
  };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
    clientId: j['client_id'] as String,
    conversationId: j['conversation_id'] as String,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    replyToId: j['reply_to_id'] as String?,
    ttlSeconds: (j['ttl_seconds'] as num?)?.toInt(),
    failed: j['failed'] as bool? ?? false,
  );
}

/// Cache local des discussions, messages et envois en attente.
/// Garantie : rien d'expiré n'est conservé sur le disque (purge à chaque lecture,
/// chaque écriture et périodiquement, même sans réseau).
class LocalCache {
  LocalCache(this._store, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _now;
  List<ConversationSummary> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  List<OutboxItem> _outbox = [];
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await _store.read();
    if (raw != null) {
      _conversations = [
        for (final c in (raw['conversations'] as List<dynamic>? ?? const []))
          ConversationSummary.fromJson(Map<String, dynamic>.from(c as Map)),
      ];
      final msgs = Map<String, dynamic>.from(raw['messages'] as Map? ?? const {});
      for (final e in msgs.entries) {
        _messages[e.key] = [
          for (final m in e.value as List<dynamic>)
            ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
        ];
      }
      _outbox = [
        for (final o in (raw['outbox'] as List<dynamic>? ?? const []))
          OutboxItem.fromJson(Map<String, dynamic>.from(o as Map)),
      ];
    }
    if (purgeExpiredInMemory()) await _persist();
  }

  List<ConversationSummary> get conversations => List.unmodifiable(_conversations);
  List<ChatMessage> messages(String conversationId) =>
      List.unmodifiable(_messages[conversationId] ?? const []);
  List<OutboxItem> get outbox => List.unmodifiable(_outbox);

  /// Tous les messages en clair conservés (recherche locale).
  Map<String, List<ChatMessage>> get allMessages => Map.unmodifiable(_messages);

  Future<void> putConversations(List<ConversationSummary> list) {
    _conversations = List.of(list);
    _messages.removeWhere((id, _) => !list.any((c) => c.id == id));
    return _persist();
  }

  Future<void> putMessages(String conversationId, List<ChatMessage> list) {
    _messages[conversationId] = List.of(list);
    return _persist();
  }

  Future<void> addOutbox(OutboxItem item) {
    _outbox = [..._outbox.where((o) => o.clientId != item.clientId), item];
    return _persist();
  }

  Future<void> updateOutbox(OutboxItem item) => addOutbox(item);

  Future<void> removeOutbox(String clientId) {
    _outbox = _outbox.where((o) => o.clientId != clientId).toList();
    return _persist();
  }

  /// Retire de la mémoire tout ce qui a expiré. Renvoie vrai si quelque chose a changé.
  bool purgeExpiredInMemory() {
    final now = _now();
    var changed = false;
    for (final e in _messages.entries) {
      final before = e.value.length;
      e.value.removeWhere((m) => !m.isVisibleAt(now));
      changed |= e.value.length != before;
    }
    final convs = [for (final c in _conversations) c.withoutExpiredLast(now)];
    for (var i = 0; i < convs.length; i++) {
      if (!identical(convs[i], _conversations[i])) changed = true;
    }
    _conversations = convs;
    final before = _outbox.length;
    _outbox = _outbox.where((o) => !o.isStale(now)).toList();
    return changed || _outbox.length != before;
  }

  /// Purge périodique : efface aussi du disque.
  Future<void> purgeExpired() async {
    await ensureLoaded();
    if (purgeExpiredInMemory()) await _persist();
  }

  Future<void> wipe() async {
    _conversations = [];
    _messages.clear();
    _outbox = [];
    _loading = Future.value();
    await _writing;
    await _store.wipe();
  }

  Future<void> _persist() {
    purgeExpiredInMemory();
    final snapshot = {
      'v': 1,
      'conversations': [for (final c in _conversations) c.toJson()],
      'messages': {
        for (final e in _messages.entries) e.key: [for (final m in e.value) m.toJson()],
      },
      'outbox': [for (final o in _outbox) o.toJson()],
    };
    // Écritures sérialisées : jamais deux écritures concurrentes du fichier.
    return _writing = _writing.then((_) => _store.write(snapshot)).catchError((Object _) {});
  }
}
