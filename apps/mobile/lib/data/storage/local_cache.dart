import 'dart:async';
import 'dart:typed_data';

import '../../domain/models/messaging.dart';
import 'local_store.dart';
import 'media_vault.dart';

/// Message en attente d'envoi (file hors ligne), conservé chiffré sur le téléphone.
/// Vocal : le son lui-même est dans le coffre ([LocalCache.outboxMediaKey]).
class OutboxItem {
  const OutboxItem({
    required this.clientId,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.replyToId,
    this.ttlSeconds,
    this.failed = false,
    this.kind = 'text',
    this.durationMs,
    this.width,
    this.height,
  });

  final String clientId;
  final String conversationId;
  final String body;
  final DateTime createdAt;
  final String? replyToId;
  final int? ttlSeconds;

  /// « text » ou « voice ».
  final String kind;

  /// Vocal : durée mesurée sur le téléphone (affichage ; le serveur mesure à nouveau).
  final int? durationMs;

  /// Photo : dimensions (affichage en attente d'envoi) ; [body] porte la légende.
  final int? width;
  final int? height;

  /// Refusé par le serveur pour une autre raison que le réseau (ex. blocage).
  final bool failed;

  bool get isVoice => kind == 'voice';
  bool get isPhoto => kind == 'photo';
  bool get hasMedia => isVoice || isPhoto;

  /// Un message jamais parti n'attend pas indéfiniment : 72 h au plus.
  DateTime get staleAt => createdAt.add(const Duration(hours: 72));
  bool isStale(DateTime now) => now.isAfter(staleAt);

  OutboxItem copyWith({bool? failed}) => OutboxItem(
    clientId: clientId,
    conversationId: conversationId,
    body: body,
    createdAt: createdAt,
    replyToId: replyToId,
    ttlSeconds: ttlSeconds,
    kind: kind,
    durationMs: durationMs,
    width: width,
    height: height,
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
    'kind': kind,
    'duration_ms': durationMs,
    'width': width,
    'height': height,
  };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
    clientId: j['client_id'] as String,
    conversationId: j['conversation_id'] as String,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    replyToId: j['reply_to_id'] as String?,
    ttlSeconds: (j['ttl_seconds'] as num?)?.toInt(),
    failed: j['failed'] as bool? ?? false,
    kind: j['kind'] as String? ?? 'text',
    durationMs: (j['duration_ms'] as num?)?.toInt(),
    width: (j['width'] as num?)?.toInt(),
    height: (j['height'] as num?)?.toInt(),
  );
}

/// Cache local des discussions, messages, envois en attente et sons.
/// Garantie : rien d'expiré n'est conservé sur le disque (purge à chaque lecture,
/// chaque écriture et périodiquement, même sans réseau). Chaque son est indexé avec
/// sa date d'expiration et effacé du coffre à l'échéance, ou dès que son message est
/// supprimé.
class LocalCache {
  LocalCache(this._store, {MediaVault? media, DateTime Function()? clock})
    : _vault = media ?? MemoryMediaVault(),
      _now = clock ?? DateTime.now;

  static String messageMediaKey(String messageId) => 'msg-$messageId';
  static String outboxMediaKey(String clientId) => 'out-$clientId';

  /// Photo de profil : la clé suit le chemin (une nouvelle photo = un nouveau chemin).
  static String avatarMediaKey(String avatarPath) {
    final safe = avatarPath.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final key = 'av-$safe';
    return key.length <= 80 ? key : key.substring(0, 80);
  }

  final LocalStore _store;
  final MediaVault _vault;
  final DateTime Function() _now;
  List<ConversationSummary> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  List<OutboxItem> _outbox = [];

  /// Index des sons du coffre : clé → expiration.
  final Map<String, DateTime> _media = {};
  Future<void>? _loading;

  /// File unique des écritures (document et coffre) : l'ordre des opérations est garanti.
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
      final media = Map<String, dynamic>.from(raw['media'] as Map? ?? const {});
      for (final e in media.entries) {
        _media[e.key] = DateTime.parse(e.value as String);
      }
    }
    if (purgeExpiredInMemory()) await _persist();
  }

  List<ConversationSummary> get conversations => List.unmodifiable(_conversations);
  List<ChatMessage> messages(String conversationId) =>
      List.unmodifiable(_messages[conversationId] ?? const []);
  List<OutboxItem> get outbox => List.unmodifiable(_outbox);

  /// Tous les messages en clair conservés (recherche locale).
  Map<String, List<ChatMessage>> get allMessages => Map.unmodifiable(_messages);

  /// Clés des sons présents dans le coffre (tests, diagnostic).
  Set<String> get mediaKeys => Set.unmodifiable(_media.keys);

  Future<void> putConversations(List<ConversationSummary> list) {
    _conversations = List.of(list);
    final gone = _messages.keys.where((id) => !list.any((c) => c.id == id)).toList();
    for (final id in gone) {
      for (final m in _messages[id]!) {
        _forgetMedia(messageMediaKey(m.id));
      }
      _messages.remove(id);
    }
    return _persist();
  }

  Future<void> putMessages(String conversationId, List<ChatMessage> list) {
    _messages[conversationId] = List.of(list);
    // Vocal ou photo supprimé pour tous : fichier effacé du téléphone aussitôt.
    for (final m in list) {
      if ((m.isVoice || m.isPhoto) && m.isDeleted) _forgetMedia(messageMediaKey(m.id));
    }
    return _persist();
  }

  /// Message masqué (« supprimer pour moi ») : retiré, son compris.
  Future<void> removeMessage(String conversationId, String messageId) {
    _messages[conversationId]?.removeWhere((m) => m.id == messageId);
    _forgetMedia(messageMediaKey(messageId));
    return _persist();
  }

  Future<void> addOutbox(OutboxItem item, {List<int>? media}) {
    if (media != null) _putMedia(outboxMediaKey(item.clientId), media, item.staleAt);
    _outbox = [..._outbox.where((o) => o.clientId != item.clientId), item];
    return _persist();
  }

  Future<void> updateOutbox(OutboxItem item) => addOutbox(item);

  Future<void> removeOutbox(String clientId) {
    _outbox = _outbox.where((o) => o.clientId != clientId).toList();
    _forgetMedia(outboxMediaKey(clientId));
    return _persist();
  }

  /// Range un son dans le coffre jusqu'à [expiresAt] (déjà échu : rien n'est écrit).
  Future<void> putMedia(String key, List<int> bytes, DateTime expiresAt) {
    _putMedia(key, bytes, expiresAt);
    return _persist();
  }

  /// Son du coffre, ou null s'il est absent ou expiré.
  Future<Uint8List?> readMedia(String key) async {
    await ensureLoaded();
    final until = _media[key];
    if (until == null || !until.isAfter(_now())) return null;
    await _writing;
    return _vault.get(key);
  }

  void _putMedia(String key, List<int> bytes, DateTime expiresAt) {
    if (!expiresAt.isAfter(_now())) return;
    _media[key] = expiresAt;
    final copy = List<int>.of(bytes);
    _writing = _writing.then((_) => _vault.put(key, copy)).catchError((Object _) {});
  }

  void _forgetMedia(String key) {
    if (_media.remove(key) == null) return;
    _writing = _writing.then((_) => _vault.delete(key)).catchError((Object _) {});
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
    final stale = _outbox.where((o) => o.isStale(now)).toList();
    _outbox = _outbox.where((o) => !o.isStale(now)).toList();
    for (final o in stale) {
      _forgetMedia(outboxMediaKey(o.clientId));
    }
    final expired = [
      for (final e in _media.entries)
        if (!e.value.isAfter(now)) e.key,
    ];
    for (final key in expired) {
      _forgetMedia(key);
    }
    return changed || _outbox.length != before || expired.isNotEmpty;
  }

  /// Fichiers gardés sur le téléphone (photos, vocaux, photos de profil) et place occupée.
  Future<({int files, int bytes})> mediaUsage() async {
    await ensureLoaded();
    await _writing;
    return (files: _media.length, bytes: await _vault.totalBytes());
  }

  /// Efface les copies locales des médias reçus et envoyés (DATA-008). Elles seront
  /// retéléchargées à la demande tant que les messages n'ont pas expiré. Les médias en
  /// attente d'envoi sont gardés. Renvoie le nombre de fichiers effacés.
  Future<int> clearMedia() async {
    await ensureLoaded();
    final keys = [
      for (final k in _media.keys)
        if (!k.startsWith('out-')) k,
    ];
    for (final k in keys) {
      _forgetMedia(k);
    }
    await _persist();
    await _writing;
    return keys.length;
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
    _media.clear();
    _loading = Future.value();
    await _writing;
    await _store.wipe();
    await _vault.wipe();
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
      'media': {for (final e in _media.entries) e.key: e.value.toUtc().toIso8601String()},
    };
    // Écritures sérialisées : jamais deux écritures concurrentes du fichier.
    return _writing = _writing.then((_) => _store.write(snapshot)).catchError((Object _) {});
  }
}
