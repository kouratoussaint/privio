/// Personne trouvée par la recherche (réponse minimale du serveur, sans numéro).
class FoundUser {
  const FoundUser({required this.id, required this.handle, required this.displayName});

  final String id;
  final String handle;
  final String displayName;

  factory FoundUser.fromJson(Map<String, dynamic> j) => FoundUser(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['display_name'] as String,
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
  });

  final String id;
  final String? peerId;
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

  bool get isDeleted => deletedAt != null;
  bool get isSystem => kind == 'system';

  /// Message système « durée réglée » : nouvelle durée en secondes, sinon null.
  int? get systemTtlSeconds =>
      isSystem && (body ?? '').startsWith('ttl:') ? int.tryParse(body!.substring(4)) : null;

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
    );
  }
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
