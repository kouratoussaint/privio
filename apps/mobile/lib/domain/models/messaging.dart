import 'dart:convert';

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

/// Ligne de l'écran « Discussions » (RPC list_conversations) : discussion 1:1 ou groupe.
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
    this.kind = 'direct',
    this.lastMessageId,
    this.lastSenderId,
    this.lastSenderName,
    this.lastBody,
    this.lastDeleted = false,
    this.lastSentAt,
    this.lastExpiresAt,
    this.lastKind = 'text',
    this.ttlSeconds = 259200,
    this.peerDeliveredUpTo,
    this.peerReadUpTo,
    this.peerAvatarPath,
    this.mutedUntil,
    this.groupTitle,
    this.groupDescription,
    this.groupAvatarPath,
    this.memberCount = 2,
    this.myRole,
    this.posting = 'all',
    this.infoEditing = 'admins',
    this.clearedBefore,
    this.clearRequestBy,
    this.clearRequestExpiresAt,
  });

  final String id;

  /// « direct » (1:1) ou « group ».
  final String kind;
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

  /// Nom de l'expéditeur du dernier message (groupes ; null si c'est soi).
  final String? lastSenderName;
  final String? lastBody;
  final bool lastDeleted;
  final DateTime? lastSentAt;
  final DateTime? lastExpiresAt;
  final String lastKind;

  /// Durée de vie des nouveaux messages de la discussion (secondes).
  final int ttlSeconds;

  /// 1:1 : pointeurs du correspondant ; groupe : atteints par TOUS les autres membres.
  final DateTime? peerDeliveredUpTo;
  final DateTime? peerReadUpTo;

  /// Sourdine jusqu'à cette date (notifications, lot 4.1).
  final DateTime? mutedUntil;

  // Groupes
  final String? groupTitle;
  final String? groupDescription;
  final String? groupAvatarPath;
  final int memberCount;

  /// « owner », « admin » ou « member » (groupes).
  final String? myRole;

  /// Qui peut écrire (« all » / « admins ») et modifier les informations.
  final String posting;
  final String infoEditing;

  /// Messages envoyés avant cet instant effacés pour moi (« vider », lot 4.3).
  final DateTime? clearedBefore;

  /// Demande « vider pour nous deux » en cours : qui l'a faite, jusqu'à quand.
  final String? clearRequestBy;
  final DateTime? clearRequestExpiresAt;

  bool get isGroup => kind == 'group';
  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';

  /// Groupe fermé par Privio (lot 5.3) : plus personne n'y écrit.
  bool get isClosed => isGroup && posting == 'closed';
  bool get canPost => isGroup ? (!isClosed && (posting == 'all' || isAdmin)) : !blocked;
  bool get canEditInfo => isGroup ? (infoEditing == 'all' || isAdmin) : !blocked;
  bool isMuted(DateTime now) => mutedUntil != null && mutedUntil!.isAfter(now);

  String get title => isGroup
      ? (groupTitle ?? 'Groupe')
      : (peerDeleted ? 'Compte supprimé' : (peerDisplayName ?? 'Inconnu'));

  /// Photo à afficher : celle du groupe, ou du correspondant.
  String? get avatarPath => isGroup ? groupAvatarPath : peerAvatarPath;

  Map<String, dynamic> toJson() => {
    'conversation_id': id,
    'kind': kind,
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
    'last_sender_name': lastSenderName,
    'last_body': lastBody,
    'last_deleted': lastDeleted,
    'last_sent_at': lastSentAt?.toUtc().toIso8601String(),
    'last_expires_at': lastExpiresAt?.toUtc().toIso8601String(),
    'last_kind': lastKind,
    'ttl_seconds': ttlSeconds,
    'peer_delivered_up_to': peerDeliveredUpTo?.toUtc().toIso8601String(),
    'peer_read_up_to': peerReadUpTo?.toUtc().toIso8601String(),
    'peer_avatar_path': peerAvatarPath,
    'muted_until': mutedUntil?.toUtc().toIso8601String(),
    'title': groupTitle,
    'description': groupDescription,
    'avatar_path': groupAvatarPath,
    'member_count': memberCount,
    'my_role': myRole,
    'posting': posting,
    'info_editing': infoEditing,
    'cleared_before': clearedBefore?.toUtc().toIso8601String(),
    'clear_request_by': clearRequestBy,
    'clear_request_expires_at': clearRequestExpiresAt?.toUtc().toIso8601String(),
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
    kind: kind,
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
    lastSenderName: clearLast ? null : lastSenderName,
    lastBody: clearLast ? null : lastBody,
    lastDeleted: clearLast ? false : lastDeleted,
    lastSentAt: clearLast ? null : lastSentAt,
    lastExpiresAt: clearLast ? null : lastExpiresAt,
    lastKind: clearLast ? 'text' : lastKind,
    ttlSeconds: ttlSeconds,
    peerDeliveredUpTo: peerDeliveredUpTo,
    peerReadUpTo: peerReadUpTo,
    peerAvatarPath: peerAvatarPath,
    mutedUntil: mutedUntil,
    groupTitle: groupTitle,
    groupDescription: groupDescription,
    groupAvatarPath: groupAvatarPath,
    memberCount: memberCount,
    myRole: myRole,
    posting: posting,
    infoEditing: infoEditing,
    clearedBefore: clearedBefore,
    clearRequestBy: clearRequestBy,
    clearRequestExpiresAt: clearRequestExpiresAt,
  );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
    id: j['conversation_id'] as String,
    kind: j['kind'] as String? ?? 'direct',
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
    lastSenderName: j['last_sender_name'] as String?,
    lastBody: j['last_body'] as String?,
    lastDeleted: j['last_deleted'] as bool? ?? false,
    lastSentAt: _date(j['last_sent_at']),
    lastExpiresAt: _date(j['last_expires_at']),
    lastKind: j['last_kind'] as String? ?? 'text',
    ttlSeconds: (j['ttl_seconds'] as num?)?.toInt() ?? 259200,
    peerDeliveredUpTo: _date(j['peer_delivered_up_to']),
    peerReadUpTo: _date(j['peer_read_up_to']),
    peerAvatarPath: j['peer_avatar_path'] as String?,
    mutedUntil: _date(j['muted_until']),
    groupTitle: j['title'] as String?,
    groupDescription: j['description'] as String?,
    groupAvatarPath: j['avatar_path'] as String?,
    memberCount: (j['member_count'] as num?)?.toInt() ?? 2,
    myRole: j['my_role'] as String?,
    posting: j['posting'] as String? ?? 'all',
    infoEditing: j['info_editing'] as String? ?? 'admins',
    clearedBefore: _date(j['cleared_before']),
    clearRequestBy: j['clear_request_by'] as String?,
    clearRequestExpiresAt: _date(j['clear_request_expires_at']),
  );
}

/// Membre d'un groupe (ou invitation en attente, visible des administrateurs).
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.role,
    this.handle,
    this.avatarPath,
    this.invited = false,
  });

  final String userId;
  final String? handle;
  final String displayName;
  final String? avatarPath;

  /// « owner », « admin », « member » ou « invited ».
  final String role;
  final bool invited;

  bool get isAdmin => role == 'owner' || role == 'admin';

  String get roleLabel => switch (role) {
    'owner' => 'Propriétaire',
    'admin' => 'Administrateur',
    'invited' => 'Invitation envoyée',
    _ => 'Membre',
  };

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    userId: j['user_id'] as String,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String? ?? 'Compte supprimé',
    avatarPath: j['avatar_path'] as String?,
    role: j['role'] as String,
    invited: j['invited'] as bool? ?? false,
  );
}

/// Invitation à rejoindre un groupe (à accepter ou refuser).
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.memberCount,
    this.description,
    this.avatarPath,
    this.inviterName,
    this.expiresAt,
  });

  final String id;
  final String conversationId;
  final String title;
  final String? description;
  final String? avatarPath;
  final String? inviterName;
  final int memberCount;
  final DateTime? expiresAt;

  factory GroupInvitation.fromJson(Map<String, dynamic> j) => GroupInvitation(
    id: j['invitation_id'] as String,
    conversationId: j['conversation_id'] as String,
    title: j['title'] as String? ?? 'Groupe',
    description: j['description'] as String?,
    avatarPath: j['avatar_path'] as String?,
    inviterName: j['inviter_name'] as String?,
    memberCount: (j['member_count'] as num?)?.toInt() ?? 1,
    expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
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
    this.senderName,
    this.waveform,
  });

  final String id;
  final String kind;

  /// Nom de l'expéditeur (groupes) ; null pour un compte supprimé.
  final String? senderName;
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

  /// Vocal : profil sonore (8 à 64 valeurs de 0 à 100) ; null pour un ancien vocal.
  final List<int>? waveform;

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
    'sender_name': senderName,
    'media_waveform': waveform,
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
      senderName: j['sender_name'] as String?,
      waveform: (j['media_waveform'] as List<dynamic>?)?.map((v) => (v as num).toInt()).toList(),
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

/// Événement de groupe annoncé par un message système (corps JSON {e, a, t, v}), rédigé
/// en français ; « Vous » quand l'acteur est l'utilisateur. Null si le corps n'en est pas un.
String? groupEventText(ChatMessage m, {required String? me}) {
  final body = m.body;
  if (!m.isSystem || body == null || !body.startsWith('{')) return null;
  Map<String, dynamic> j;
  try {
    j = Map<String, dynamic>.from(jsonDecode(body) as Map);
  } on Object {
    return null;
  }
  final mine = m.senderId != null && m.senderId == me;
  final a = j['a'] as String? ?? 'Quelqu’un';
  final t = j['t'] as String? ?? 'un membre';
  final v = j['v'] as String?;
  String did(String verb) => mine ? 'Vous avez $verb' : '$a a $verb';
  return switch (j['e']) {
    'created' => did('créé le groupe «\u202F${v ?? ''}\u202F»'),
    'joined' => mine ? 'Vous avez rejoint le groupe' : '$a a rejoint le groupe',
    'left' => mine ? 'Vous avez quitté le groupe' : '$a a quitté le groupe',
    'removed' => did('retiré $t du groupe'),
    'admin_added' => did('nommé $t administrateur'),
    'admin_removed' => did('retiré le rôle d’administrateur à $t'),
    'owner_changed' =>
      j['a'] == null ? '$t est maintenant propriétaire du groupe' : did('confié le groupe à $t'),
    'title' => did('renommé le groupe «\u202F${v ?? ''}\u202F»'),
    'description' => did('modifié la description du groupe'),
    'photo' => did('changé la photo du groupe'),
    'photo_removed' => did('retiré la photo du groupe'),
    'posting' =>
      v == 'admins'
          ? did('réservé l’envoi de messages aux administrateurs')
          : did('permis à tous les membres d’écrire'),
    'closed' => 'Ce groupe a été fermé par Privio',
    'info_editing' =>
      v == 'admins'
          ? did('réservé la modification du groupe aux administrateurs')
          : did('permis à tous les membres de modifier le groupe'),
    _ => null,
  };
}

/// Réglages de confidentialité du compte (lot 4.3). Visibilités : 'everyone',
/// 'contacts' (personnes avec qui l'on a une discussion à deux) ou 'nobody'.
class PrivacySettings {
  const PrivacySettings({
    this.presence = 'contacts',
    this.readReceipts = true,
    this.typing = true,
    this.avatar = 'everyone',
    this.groupInvites = 'everyone',
    this.defaultTtlSeconds,
  });

  final String presence;
  final bool readReceipts;
  final bool typing;
  final String avatar;
  final String groupInvites;

  /// Durée des messages des nouvelles discussions (null : 72 h).
  final int? defaultTtlSeconds;

  PrivacySettings copyWith({
    String? presence,
    bool? readReceipts,
    bool? typing,
    String? avatar,
    String? groupInvites,
    int? defaultTtlSeconds,
    bool clearDefaultTtl = false,
  }) => PrivacySettings(
    presence: presence ?? this.presence,
    readReceipts: readReceipts ?? this.readReceipts,
    typing: typing ?? this.typing,
    avatar: avatar ?? this.avatar,
    groupInvites: groupInvites ?? this.groupInvites,
    defaultTtlSeconds: clearDefaultTtl ? null : (defaultTtlSeconds ?? this.defaultTtlSeconds),
  );

  factory PrivacySettings.fromJson(Map<String, dynamic> j) => PrivacySettings(
    presence: j['presence_visibility'] as String? ?? 'contacts',
    readReceipts: j['read_receipts'] as bool? ?? true,
    typing: j['typing_indicator'] as bool? ?? true,
    avatar: j['avatar_visibility'] as String? ?? 'everyone',
    groupInvites: j['group_invites'] as String? ?? 'everyone',
    defaultTtlSeconds: (j['default_ttl_seconds'] as num?)?.toInt(),
  );

  Map<String, dynamic> toRpc() => {
    'p_presence_visibility': presence,
    'p_read_receipts': readReceipts,
    'p_typing_indicator': typing,
    'p_avatar_visibility': avatar,
    'p_group_invites': groupInvites,
    'p_default_ttl_seconds': defaultTtlSeconds,
  };
}

/// Libellé d'une visibilité.
String visibilityLabel(String v) => switch (v) {
  'everyone' => 'Tout le monde',
  'contacts' => 'Mes contacts',
  _ => 'Personne',
};

/// Statut d'une personne (si elle le montre).
class UserPresence {
  const UserPresence({this.visible = false, this.online = false, this.lastSeenAt});

  final bool visible;
  final bool online;
  final DateTime? lastSeenAt;

  factory UserPresence.fromJson(Map<String, dynamic> j) => UserPresence(
    visible: j['visible'] as bool? ?? false,
    online: j['online'] as bool? ?? false,
    lastSeenAt: j['last_seen_at'] == null ? null : DateTime.parse(j['last_seen_at'] as String),
  );
}

// ---------------------------------------------------------------------------
// Demandes de connexion (lot 4.7)
// ---------------------------------------------------------------------------

/// Relation avec une personne trouvée : décide du bouton de la recherche.
enum LinkState {
  /// Discussion existante (ou demandes désactivées) : on écrit.
  connected,

  /// Ma demande attend sa réponse.
  outgoing,

  /// Sa demande attend ma réponse.
  incoming,

  /// Refus récent : nouvel essai à [ConnectionStatus.retryAt].
  refused,

  /// Aucune relation : on peut envoyer une demande.
  none,
}

class ConnectionStatus {
  const ConnectionStatus({required this.state, this.conversationId, this.requestId, this.retryAt});

  final LinkState state;
  final String? conversationId;
  final String? requestId;
  final DateTime? retryAt;

  factory ConnectionStatus.fromJson(Map<String, dynamic> j) => ConnectionStatus(
    state: LinkState.values.firstWhere((s) => s.name == j['state'], orElse: () => LinkState.none),
    conversationId: j['conversation_id'] as String?,
    requestId: j['request_id'] as String?,
    retryAt: j['retry_at'] == null ? null : DateTime.parse(j['retry_at'] as String),
  );
}

/// Résultat d'un envoi : discussion ouverte (déjà connectés, demande croisée) ou demande.
class ConnectionSendResult {
  const ConnectionSendResult({required this.connected, this.conversationId, this.requestId});

  final bool connected;
  final String? conversationId;
  final String? requestId;

  factory ConnectionSendResult.fromJson(Map<String, dynamic> j) => ConnectionSendResult(
    connected: j['state'] == 'connected',
    conversationId: j['conversation_id'] as String?,
    requestId: j['request_id'] as String?,
  );
}

enum ConnectionAction { accept, refuse, block }

class ConnectionRequest {
  const ConnectionRequest({
    required this.id,
    required this.incoming,
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.avatarPath,
    this.note,
    this.answeredAt,
    this.retryAt,
  });

  final String id;

  /// Reçue (true) ou envoyée (false).
  final bool incoming;

  /// L'autre personne.
  final String userId;
  final String handle;
  final String displayName;
  final String? avatarPath;
  final String? note;

  /// pending · refused · expired (accepted et cancelled ne sont pas listées).
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? answeredAt;
  final DateTime? retryAt;

  bool get pending => status == 'pending';

  factory ConnectionRequest.fromJson(Map<String, dynamic> j) {
    DateTime? at(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return ConnectionRequest(
      id: j['id'] as String,
      incoming: j['direction'] == 'incoming',
      userId: j['user_id'] as String,
      handle: j['handle'] as String,
      displayName: j['display_name'] as String,
      avatarPath: j['avatar_path'] as String?,
      note: j['note'] as String?,
      status: j['status'] as String,
      createdAt: at('created_at')!,
      expiresAt: at('expires_at')!,
      answeredAt: at('answered_at'),
      retryAt: at('retry_at'),
    );
  }
}
