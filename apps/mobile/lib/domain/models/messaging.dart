import '../../l10n/l10n.dart';

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
    this.clearRequestDelete = false,
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

  /// Lot 7.2b1 : la demande en cours est une suppression (sinon : vider).
  final bool clearRequestDelete;

  bool get isGroup => kind == 'group';
  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';

  /// Groupe fermé par Privio (lot 5.3) : plus personne n'y écrit.
  bool get isClosed => isGroup && posting == 'closed';
  bool get canPost => isGroup ? (!isClosed && (posting == 'all' || isAdmin)) : !blocked;
  bool get canEditInfo => isGroup ? (infoEditing == 'all' || isAdmin) : !blocked;
  bool isMuted(DateTime now) => mutedUntil != null && mutedUntil!.isAfter(now);

  String get title => isGroup
      ? (groupTitle ?? L.t.groupe)
      : (peerDeleted ? L.t.compteSupprime : (peerDisplayName ?? L.t.inconnu));

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
    'clear_request_delete': clearRequestDelete,
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
    clearRequestDelete: clearRequestDelete,
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
    clearRequestDelete: j['clear_request_delete'] as bool? ?? false,
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
    'owner' => L.t.proprietaire,
    'admin' => L.t.administrateur,
    'invited' => L.t.invitationEnvoyee,
    _ => L.t.membre,
  };

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    userId: j['user_id'] as String,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String? ?? L.t.compteSupprime,
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
    title: j['title'] as String? ?? L.t.groupe,
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
    this.mentions = const [],
    this.viewOnce = false,
    this.opened = false,
    this.openedCount,
    this.linkPreview,
  });

  final String id;
  final String kind;

  /// Lot 7.3b : photo ou vocal en vue unique ; ouvert par moi ; nombre d'ouvertures (mes
  /// envois seulement).
  final bool viewOnce;
  final bool opened;
  final int? openedCount;

  /// Lot 7.3b : aperçu du premier lien (préparé par le serveur).
  final LinkPreview? linkPreview;

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

  /// Personnes mentionnées (lot 7.1b, groupes seulement).
  final List<String> mentions;

  bool get isDeleted => deletedAt != null;
  bool get isSystem => kind == 'system';
  bool get isVoice => kind == 'voice';
  bool get isPhoto => kind == 'photo';

  /// Lot 7.3a : autocollant intégré à l'application ; [body] le désigne (« série/nom »).
  bool get isSticker => kind == 'sticker';

  /// Lot 7.3b : GIF (copié dans le stockage privé de Privio).
  bool get isGif => kind == 'gif';

  /// Photo encore affichable (ni supprimée, ni sans fichier).
  bool get hasViewablePhoto => isPhoto && !viewOnce && !isDeleted && mediaPath != null;

  /// Vocal encore écoutable (ni supprimé, ni sans fichier).
  bool get hasPlayableVoice => isVoice && !viewOnce && !isDeleted && mediaPath != null;

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
    'mentions': mentions,
    'view_once': viewOnce,
    'opened': opened,
    'opened_count': openedCount,
    'link_preview': linkPreview?.toJson(),
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
      mentions: [for (final v in (j['mentions'] as List<dynamic>? ?? const [])) v as String],
      viewOnce: j['view_once'] as bool? ?? false,
      opened: j['opened'] as bool? ?? false,
      openedCount: (j['opened_count'] as num?)?.toInt(),
      linkPreview: j['link_preview'] == null
          ? null
          : LinkPreview.fromJson(Map<String, dynamic>.from(j['link_preview'] as Map)),
    );
  }
}

/// Lot 7.3b : aperçu d'un lien.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.site,
    this.imagePath,
    this.imageWidth,
    this.imageHeight,
  });

  final String url;
  final String? title;
  final String? description;
  final String? site;
  final String? imagePath;
  final int? imageWidth;
  final int? imageHeight;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'site': site,
    'image_path': imagePath,
    'image_width': imageWidth,
    'image_height': imageHeight,
  };

  factory LinkPreview.fromJson(Map<String, dynamic> j) => LinkPreview(
    url: j['url'] as String? ?? '',
    title: j['title'] as String?,
    description: j['description'] as String?,
    site: j['site'] as String?,
    imagePath: j['image_path'] as String?,
    imageWidth: (j['image_width'] as num?)?.toInt(),
    imageHeight: (j['image_height'] as num?)?.toInt(),
  );
}

/// Lot 7.3b : GIF proposé par la recherche (aperçu servi par KLIPY).
class GifResult {
  const GifResult({
    required this.slug,
    required this.url,
    required this.width,
    required this.height,
    this.title = '',
  });

  final String slug;
  final String url;
  final int width;
  final int height;
  final String title;

  factory GifResult.fromJson(Map<String, dynamic> j) => GifResult(
    slug: j['slug'] as String,
    url: j['url'] as String,
    width: (j['width'] as num).toInt(),
    height: (j['height'] as num).toInt(),
    title: j['title'] as String? ?? '',
  );
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
  final a = j['a'] as String? ?? L.t.quelqu;
  final t = j['t'] as String? ?? L.t.membre2;
  final v = j['v'] as String?;
  // Lot 8.2a : une phrase complète par événement (moi / un membre), pour la traduction.
  String ev(String Function() mineText, String Function() otherText) =>
      mine ? mineText() : otherText();
  final title = v ?? '';
  return switch (j['e']) {
    'created' => ev(() => L.t.evtCreatedMine(title), () => L.t.evtCreatedOther(a, title)),
    'joined' => mine ? L.t.vousAvezRejointGroupe : L.t.rejointGroupe(a),
    'left' => mine ? L.t.vousAvezQuitteGroupe : L.t.quitteGroupe(a),
    'removed' => ev(() => L.t.evtRemovedMine(t), () => L.t.evtRemovedOther(a, t)),
    'admin_added' => ev(() => L.t.evtAdminAddedMine(t), () => L.t.evtAdminAddedOther(a, t)),
    'admin_removed' => ev(() => L.t.evtAdminRemovedMine(t), () => L.t.evtAdminRemovedOther(a, t)),
    'owner_changed' =>
      j['a'] == null
          ? L.t.tEstMaintenantProprietaireGroupe(t)
          : ev(() => L.t.evtOwnerChangedMine(t), () => L.t.evtOwnerChangedOther(a, t)),
    'title' => ev(() => L.t.evtTitleMine(title), () => L.t.evtTitleOther(a, title)),
    'description' => ev(() => L.t.evtDescriptionMine, () => L.t.evtDescriptionOther(a)),
    'photo' => ev(() => L.t.evtPhotoMine, () => L.t.evtPhotoOther(a)),
    'photo_removed' => ev(() => L.t.evtPhotoRemovedMine, () => L.t.evtPhotoRemovedOther(a)),
    'posting' =>
      v == 'admins'
          ? ev(() => L.t.evtPostingAdminsMine, () => L.t.evtPostingAdminsOther(a))
          : ev(() => L.t.evtPostingAllMine, () => L.t.evtPostingAllOther(a)),
    'closed' => L.t.ceGroupeEteFermePar2,
    'info_editing' =>
      v == 'admins'
          ? ev(() => L.t.evtInfoAdminsMine, () => L.t.evtInfoAdminsOther(a))
          : ev(() => L.t.evtInfoAllMine, () => L.t.evtInfoAllOther(a)),
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
    this.about = 'contacts',
  });

  /// Lot 7.1a : qui voit mon « À propos » (par défaut : mes contacts).
  final String about;

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
    String? about,
  }) => PrivacySettings(
    about: about ?? this.about,
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
    about: j['about_visibility'] as String? ?? 'contacts',
  );

  Map<String, dynamic> toRpc() => {
    'p_presence_visibility': presence,
    'p_read_receipts': readReceipts,
    'p_typing_indicator': typing,
    'p_avatar_visibility': avatar,
    'p_group_invites': groupInvites,
    'p_default_ttl_seconds': defaultTtlSeconds,
    'p_about_visibility': about,
  };
}

/// Fiche d'un contact (lot 7.1a) : « À propos » et photo selon ses réglages.
class ContactProfile {
  const ContactProfile({
    required this.userId,
    required this.handle,
    required this.displayName,
    this.about,
    this.avatarPath,
  });

  final String userId;
  final String handle;
  final String displayName;
  final String? about;
  final String? avatarPath;

  factory ContactProfile.fromJson(Map<String, dynamic> j) => ContactProfile(
    userId: j['user_id'] as String,
    handle: j['handle'] as String,
    displayName: j['display_name'] as String? ?? '',
    about: j['about'] as String?,
    avatarPath: j['avatar_path'] as String?,
  );
}

/// Groupe en commun avec un contact (lot 7.1a).
class CommonGroup {
  const CommonGroup({
    required this.id,
    required this.title,
    required this.memberCount,
    this.avatarPath,
  });

  final String id;
  final String title;
  final int memberCount;
  final String? avatarPath;

  factory CommonGroup.fromJson(Map<String, dynamic> j) => CommonGroup(
    id: j['conversation_id'] as String,
    title: j['title'] as String? ?? L.t.groupe,
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
    avatarPath: j['avatar_path'] as String?,
  );
}

/// Média encore présent dans une discussion (lot 7.1a), sous forme de message.
ChatMessage mediaMessageFromJson(Map<String, dynamic> j) {
  final sentAt = DateTime.parse(j['sent_at'] as String);
  return ChatMessage(
    id: j['message_id'] as String,
    kind: j['kind'] as String,
    senderId: j['sender_id'] as String?,
    sentAt: sentAt,
    expiresAt: DateTime.parse(j['expires_at'] as String),
    updatedAt: sentAt,
    mediaPath: j['media_path'] as String?,
    durationMs: (j['media_duration_ms'] as num?)?.toInt(),
    width: (j['media_width'] as num?)?.toInt(),
    height: (j['media_height'] as num?)?.toInt(),
  );
}

/// Libellé d'une visibilité.
String visibilityLabel(String v) => switch (v) {
  'everyone' => L.t.toutMonde,
  'contacts' => L.t.mesContacts,
  _ => L.t.personne,
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

// ------------------------------------------------------------------------
// Lot 7.1b : rejoindre un groupe par code, demandes d'adhésion
// ------------------------------------------------------------------------
/// Situation face à un groupe désigné par un code.
enum JoinStatus {
  /// Code faux, réinitialisé ou groupe indisponible.
  invalid,

  /// Déjà membre : le groupe s'ouvre.
  member,

  /// Demande déjà envoyée, en attente.
  pending,

  /// Demande refusée il y a moins de 24 h.
  declined,

  /// Groupe complet.
  full,

  /// Entrée directe.
  open,

  /// Une demande sera envoyée aux administrateurs.
  approval,

  /// Entré dans le groupe.
  joined,

  /// Demande envoyée.
  requested;

  static JoinStatus parse(String? v) =>
      JoinStatus.values.where((s) => s.name == v).firstOrNull ?? JoinStatus.invalid;
}

/// Aperçu d'un groupe à partir de son code (nom et nombre de membres seulement).
class GroupPreview {
  const GroupPreview({required this.status, this.conversationId, this.title, this.memberCount});

  final JoinStatus status;
  final String? conversationId;
  final String? title;
  final int? memberCount;

  factory GroupPreview.fromJson(Map<String, dynamic> j) => GroupPreview(
    status: JoinStatus.parse(j['status'] as String?),
    conversationId: j['conversation_id'] as String?,
    title: j['title'] as String?,
    memberCount: (j['member_count'] as num?)?.toInt(),
  );
}

/// Résultat d'une entrée par code : entré (le groupe s'ouvre), demande envoyée, ou refus.
class JoinResult {
  const JoinResult({required this.status, this.conversationId});

  final JoinStatus status;
  final String? conversationId;

  factory JoinResult.fromJson(Map<String, dynamic> j) => JoinResult(
    status: JoinStatus.parse(j['status'] as String?),
    conversationId: j['conversation_id'] as String?,
  );
}

/// Réglages d'entrée d'un groupe (administrateurs).
class GroupJoinSettings {
  const GroupJoinSettings({
    required this.approvalRequired,
    required this.hasCode,
    required this.pendingRequests,
  });

  final bool approvalRequired;
  final bool hasCode;
  final int pendingRequests;

  factory GroupJoinSettings.fromJson(Map<String, dynamic> j) => GroupJoinSettings(
    approvalRequired: j['join_approval'] as bool? ?? true,
    hasCode: j['has_code'] as bool? ?? false,
    pendingRequests: (j['pending_requests'] as num?)?.toInt() ?? 0,
  );
}

/// Demande d'adhésion reçue par les administrateurs.
class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.createdAt,
    this.handle,
    this.wasRemoved = false,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? handle;
  final DateTime createdAt;

  /// Personne déjà retirée du groupe par un administrateur.
  final bool wasRemoved;

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
    id: j['request_id'] as String,
    userId: j['user_id'] as String,
    displayName: j['display_name'] as String? ?? L.t.compteSupprime,
    handle: j['handle'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    wasRemoved: j['was_removed'] as bool? ?? false,
  );
}

/// Ma demande en attente pour rejoindre un groupe.
class MyJoinRequest {
  const MyJoinRequest({required this.conversationId, required this.title, required this.createdAt});

  final String conversationId;
  final String title;
  final DateTime createdAt;

  factory MyJoinRequest.fromJson(Map<String, dynamic> j) => MyJoinRequest(
    conversationId: j['conversation_id'] as String,
    title: j['title'] as String? ?? L.t.groupe,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Code d'invitation lu dans un texte (saisie ou QR code) : « PRV-XXXXXX », ou null.
String? parseInviteCode(String? raw) {
  final v = (raw ?? '').toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  const sign = '[2-9A-HJ-NP-Z]';
  // « PRV » suivi de 3 signes : code incomplet, pas un code sans préfixe.
  if (RegExp('^$sign{6}\$').hasMatch(v) && !v.startsWith('PRV')) return 'PRV-$v';
  if (RegExp('^PRV$sign{6}\$').hasMatch(v)) return 'PRV-${v.substring(3)}';
  return null;
}

// ------------------------------------------------------------------------
// Lot 7.2a : confidentialité propre à une discussion ou un groupe
// ------------------------------------------------------------------------
/// Réglages d'une discussion ; null : « comme dans mes réglages ».
class ConversationPrivacy {
  const ConversationPrivacy({
    this.readReceipts,
    this.typing,
    this.showPresence,
    this.showAvatar,
    this.showAbout,
  });

  final bool? readReceipts;
  final bool? typing;

  /// Discussions à deux seulement : montré (true) ou caché (false) à ce contact.
  final bool? showPresence;
  final bool? showAvatar;
  final bool? showAbout;

  static const keys = ['receipts', 'typing', 'presence', 'avatar', 'about'];

  bool? valueOf(String key) => switch (key) {
    'receipts' => readReceipts,
    'typing' => typing,
    'presence' => showPresence,
    'avatar' => showAvatar,
    _ => showAbout,
  };

  ConversationPrivacy withValue(String key, bool? v) => ConversationPrivacy(
    readReceipts: key == 'receipts' ? v : readReceipts,
    typing: key == 'typing' ? v : typing,
    showPresence: key == 'presence' ? v : showPresence,
    showAvatar: key == 'avatar' ? v : showAvatar,
    showAbout: key == 'about' ? v : showAbout,
  );

  factory ConversationPrivacy.fromJson(Map<String, dynamic> j) => ConversationPrivacy(
    readReceipts: j['read_receipts'] as bool?,
    typing: j['typing_indicator'] as bool?,
    showPresence: j['show_presence'] as bool?,
    showAvatar: j['show_avatar'] as bool?,
    showAbout: j['show_about'] as bool?,
  );

  /// Paramètres de set_conversation_privacy (groupe : sans les trois derniers).
  Map<String, dynamic> toRpc(String conversationId, {required bool group}) => {
    'p_conversation_id': conversationId,
    'p_read_receipts': readReceipts,
    'p_typing_indicator': typing,
    if (!group) ...{
      'p_show_presence': showPresence,
      'p_show_avatar': showAvatar,
      'p_show_about': showAbout,
    },
  };
}

/// Lot 7.2b1 : avis « Le groupe X a été supprimé » (onglet Groupes).
class GroupDeletionNotice {
  const GroupDeletionNotice({required this.id, required this.title, required this.deletedAt});

  final String id;
  final String title;
  final DateTime deletedAt;

  factory GroupDeletionNotice.fromJson(Map<String, dynamic> j) => GroupDeletionNotice(
    id: j['id'] as String,
    title: j['title'] as String? ?? L.t.groupe,
    deletedAt: DateTime.parse(j['deleted_at'] as String),
  );
}

/// Lot 7.2c2 : message épinglé ou favori (aperçu pour le bandeau et la liste des favoris).
class MessageRef {
  const MessageRef({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.body,
    required this.sentAt,
    required this.at,
    this.expiresAt,
    this.conversationId,
  });

  final String id;

  /// Lot 8.3a : discussion du message (favoris de toutes les discussions).
  final String? conversationId;
  final String? senderId;
  final String? senderName;
  final String kind;
  final String? body;
  final DateTime sentAt;

  /// Épinglé le / ajouté aux favoris le.
  final DateTime at;
  final DateTime? expiresAt;

  factory MessageRef.pinned(Map<String, dynamic> j) => MessageRef(
    id: j['message_id'] as String,
    senderId: j['sender_id'] as String?,
    senderName: j['sender_name'] as String?,
    kind: j['kind'] as String? ?? 'text',
    body: j['body'] as String?,
    sentAt: DateTime.parse(j['sent_at'] as String),
    at: DateTime.parse(j['pinned_at'] as String),
  );

  factory MessageRef.favorite(Map<String, dynamic> j) => MessageRef(
    id: j['message_id'] as String,
    conversationId: j['conversation_id'] as String?,
    senderId: j['sender_id'] as String?,
    senderName: j['sender_name'] as String?,
    kind: j['kind'] as String? ?? 'text',
    body: j['body'] as String?,
    sentAt: DateTime.parse(j['sent_at'] as String),
    at: DateTime.parse(j['created_at'] as String),
    expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
  );
}

/// Lot 7.2c2 : infos d'un de mes messages, pour un destinataire.
class MessageReceipt {
  const MessageReceipt({
    required this.userId,
    required this.name,
    required this.delivered,
    required this.read,
    this.deliveredAt,
    this.readAt,
    this.receiptsHidden = false,
  });

  final String userId;
  final String name;
  final bool delivered;
  final DateTime? deliveredAt;
  final bool read;
  final DateTime? readAt;

  /// La personne a désactivé ses accusés de lecture : la lecture n'est pas connue.
  final bool receiptsHidden;

  factory MessageReceipt.fromJson(Map<String, dynamic> j) => MessageReceipt(
    userId: j['user_id'] as String,
    name: j['display_name'] as String? ?? L.t.ancienMembre,
    delivered: j['delivered'] as bool? ?? false,
    deliveredAt: j['delivered_at'] == null ? null : DateTime.parse(j['delivered_at'] as String),
    read: j['read'] as bool? ?? false,
    readAt: j['read_at'] == null ? null : DateTime.parse(j['read_at'] as String),
    receiptsHidden: j['receipts_hidden'] as bool? ?? false,
  );
}
