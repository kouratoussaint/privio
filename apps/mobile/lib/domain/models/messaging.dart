/// Personne trouvée par la recherche (réponse minimale du serveur, sans numéro).
class FoundUser {
  const FoundUser({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarPath,
  });

  final String id;
  final String handle;
  final String displayName;
  final String? avatarPath;

  factory FoundUser.fromJson(Map<String, dynamic> j) => FoundUser(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['display_name'] as String,
    avatarPath: j['avatar_path'] as String?,
  );
}

/// Ligne de l'écran « Discussions » (RPC list_conversations).
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.peerId,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.peerDeleted,
    required this.blocked,
    required this.unreadCount,
    required this.pinned,
    required this.archived,
    required this.sortAt,
    this.lastMessageId,
    this.lastSenderId,
    this.lastBody,
    this.lastDeleted = false,
    this.lastSentAt,
    this.lastExpiresAt,
    this.lastKind = 'text',
    this.ttlSeconds = 259200,
    this.peerDeliveredUpTo,
    this.peerReadUpTo,
    this.peerAvatarPath,
  });

  final String id;
  final String? peerId;

  /// Photo de profil du correspondant (absente s'il est bloqué ou supprimé).
  final String? peerAvatarPath;
  final String? peerHandle;
  final String? peerDisplayName;
  final bool peerDeleted;
  final bool blocked;
  final int unreadCount;
  final bool pinned;
  final bool archived;
  final DateTime sortAt;
  final String? lastMessageId;
  final String? lastSenderId;
  final String? lastBody;
  final bool lastDeleted;
  final DateTime? lastSentAt;
  final DateTime? lastExpiresAt;
  final String lastKind;

  /// Durée de vie des nouveaux messages de la discussion (secondes).
  final int ttlSeconds;
  final DateTime? peerDeliveredUpTo;
  final DateTime? peerReadUpTo;

  String get title => peerDeleted ? 'Compte supprimé' : (peerDisplayName ?? 'Inconnu');

  Map<String, dynamic> toJson() => {
    'conversation_id': id,
    'peer_id': peerId,
    'peer_handle': peerHandle,
    'peer_display_name': peerDisplayName,
    'peer_deleted': peerDeleted,
    'blocked': blocked,
    'unread_count': unreadCount,
    'pinned': pinned,
    'archived': archived,
    'sort_at': sortAt.toUtc().toIso8601String(),
    'last_message_id': lastMessageId,
    'last_sender_id': lastSenderId,
    'last_body': lastBody,
    'last_deleted': lastDeleted,
    'last_sent_at': lastSentAt?.toUtc().toIso8601String(),
    'last_expires_at': lastExpiresAt?.toUtc().toIso8601String(),
    'last_kind': lastKind,
    'ttl_seconds': ttlSeconds,
    'peer_delivered_up_to': peerDeliveredUpTo?.toUtc().toIso8601String(),
    'peer_read_up_to': peerReadUpTo?.toUtc().toIso8601String(),
    'peer_avatar_path': peerAvatarPath,
  };

  /// Copie dont le dernier message est effacé s'il a expiré (hors connexion aussi).
  ConversationSummary withoutExpiredLast(DateTime now) {
    if (lastExpiresAt == null || lastExpiresAt!.isAfter(now)) return this;
    return copyWith(clearLast: true, unreadCount: 0);
  }

  ConversationSummary copyWith({
    bool? pinned,
    bool? archived,
    int? unreadCount,
    bool clearLast = false,
  }) => ConversationSummary(
    id: id,
    peerId: peerId,
    peerHandle: peerHandle,
    peerDisplayName: peerDisplayName,
    peerDeleted: peerDeleted,
    blocked: blocked,
    unreadCount: unreadCount ?? this.unreadCount,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    sortAt: sortAt,
    lastMessageId: clearLast ? null : lastMessageId,
    lastSenderId: clearLast ? null : lastSenderId,
    lastBody: clearLast ? null : lastBody,
    lastDeleted: clearLast ? false : lastDeleted,
    lastSentAt: clearLast ? null : lastSentAt,
    lastExpiresAt: clearLast ? null : lastExpiresAt,
    lastKind: clearLast ? 'text' : lastKind,
    ttlSeconds: ttlSeconds,
    peerDeliveredUpTo: peerDeliveredUpTo,
    peerReadUpTo: peerReadUpTo,
    peerAvatarPath: peerAvatarPath,
  );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
    id: j['conversation_id'] as String,
    peerId: j['peer_id'] as String?,
    peerHandle: j['peer_handle'] as String?,
    peerDisplayName: j['peer_display_name'] as String?,
    peerDeleted: j['peer_deleted'] as bool? ?? false,
    blocked: j['blocked'] as bool? ?? false,
    unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
    pinned: j['pinned'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
    sortAt: DateTime.parse(j['sort_at'] as String),
    lastMessageId: j['last_message_id'] as String?,
    lastSenderId: j['last_sender_id'] as String?,
    lastBody: j['last_body'] as String?,
    lastDeleted: j['last_deleted'] as bool? ?? false,
    lastSentAt: _date(j['last_sent_at']),
    lastExpiresAt: _date(j['last_expires_at']),
    lastKind: j['last_kind'] as String? ?? 'text',
    ttlSeconds: (j['ttl_seconds'] as num?)?.toInt() ?? 259200,
    peerDeliveredUpTo: _date(j['peer_delivered_up_to']),
    peerReadUpTo: _date(j['peer_read_up_to']),
    peerAvatarPath: j['peer_avatar_path'] as String?,
  );
}

class Reaction {
  const Reaction({required this.userId, required this.emoji});

  final String userId;
  final String emoji;
}

/// Message d'une discussion (RPC get_messages).
class ChatMessage {
  const ChatMessage({
    required this.id,
    this.kind = 'text',
    required this.senderId,
    required this.sentAt,
    required this.expiresAt,
    required this.updatedAt,
    this.body,
    this.replyToId,
    this.replyPreview,
    this.editedAt,
    this.deletedAt,
    this.reactions = const [],
    this.replyKind,
    this.mediaPath,
    this.durationMs,
    this.width,
    this.height,
  });

  final String id;
  final String kind;
  final String? senderId;
  final String? body;
  final String? replyToId;
  final String? replyPreview;
  final DateTime sentAt;
  final DateTime expiresAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime updatedAt;
  final List<Reaction> reactions;

  /// Type du message cité (« text » ou « voice »), s'il est encore visible.
  final String? replyKind;

  /// Vocal : chemin opaque du son dans le stockage privé, et durée mesurée par le serveur.
  final String? mediaPath;
  final int? durationMs;

  /// Photo : dimensions mesurées par le serveur (pour réserver la place avant l'affichage).
  final int? width;
  final int? height;

  bool get isDeleted => deletedAt != null;
  bool get isSystem => kind == 'system';
  bool get isVoice => kind == 'voice';
  bool get isPhoto => kind == 'photo';

  /// Photo encore affichable (ni supprimée, ni sans fichier).
  bool get hasViewablePhoto => isPhoto && !isDeleted && mediaPath != null;

  /// Vocal encore écoutable (ni supprimé, ni sans fichier).
  bool get hasPlayableVoice => isVoice && !isDeleted && mediaPath != null;

  /// Message système « durée réglée » : nouvelle durée en secondes, sinon null.
  int? get systemTtlSeconds =>
      isSystem && (body ?? '').startsWith('ttl:') ? int.tryParse(body!.substring(4)) : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'sender_id': senderId,
    'body': body,
    'reply_to_id': replyToId,
    'reply_preview': replyPreview,
    'sent_at': sentAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'edited_at': editedAt?.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'reactions': [
      for (final r in reactions) {'user_id': r.userId, 'emoji': r.emoji},
    ],
    'reply_kind': replyKind,
    'media_path': mediaPath,
    'media_duration_ms': durationMs,
    'media_width': width,
    'media_height': height,
  };

  /// Règle d'or : un message expiré n'est jamais affiché, même sans réseau.
  bool isVisibleAt(DateTime now) => expiresAt.isAfter(now);

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return ChatMessage(
      id: j['id'] as String,
      kind: j['kind'] as String? ?? 'text',
      senderId: j['sender_id'] as String?,
      body: j['body'] as String?,
      replyToId: j['reply_to_id'] as String?,
      replyPreview: j['reply_preview'] as String?,
      sentAt: d('sent_at')!,
      expiresAt: d('expires_at')!,
      editedAt: d('edited_at'),
      deletedAt: d('deleted_at'),
      updatedAt: d('updated_at')!,
      reactions: [
        for (final r in (j['reactions'] as List<dynamic>? ?? const []))
          Reaction(userId: (r as Map)['user_id'] as String, emoji: r['emoji'] as String),
      ],
      replyKind: j['reply_kind'] as String?,
      mediaPath: j['media_path'] as String?,
      durationMs: (j['media_duration_ms'] as num?)?.toInt(),
      width: (j['media_width'] as num?)?.toInt(),
      height: (j['media_height'] as num?)?.toInt(),
    );
  }
}

/// Photos du jour (PHOTO-005) : limite, utilisées, restantes, remise à zéro.
class PhotoQuota {
  const PhotoQuota({required this.limit, required this.used, this.resetsAt});

  final int limit;
  final int used;
  final DateTime? resetsAt;

  int get remaining => (limit - used).clamp(0, limit);

  factory PhotoQuota.fromJson(Map<String, dynamic> j) => PhotoQuota(
    limit: (j['limit'] as num).toInt(),
    used: (j['used'] as num).toInt(),
    resetsAt: j['resets_at'] == null ? null : DateTime.parse(j['resets_at'] as String),
  );
}

class BlockedUser {
  const BlockedUser({required this.id, required this.handle, required this.displayName});

  final String id;
  final String handle;
  final String displayName;

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['display_name'] as String,
  );
}
