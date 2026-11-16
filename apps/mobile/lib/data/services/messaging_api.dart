import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/messaging.dart';
import '../../domain/models/moderation.dart';

/// Messagerie via les RPC sécurisées du lot 2.1. Aucune écriture directe en table,
/// sauf les blocages (table `blocks`, protégée par RLS : on ne bloque qu'en son nom).
abstract interface class MessagingApi {
  Future<List<ConversationSummary>> listConversations();
  Future<FoundUser?> findByHandle(String handle);
  Future<FoundUser?> findByPhone(String phoneE164);
  Future<String> startDirectConversation(String otherUserId);

  // Demandes de connexion (lot 4.7) : premier contact par demande, acceptée ou refusée.
  Future<ConnectionStatus> connectionStatus(String userId);
  Future<ConnectionSendResult> sendConnectionRequest(String userId, {String? note});

  /// Renvoie l'identifiant de la discussion ouverte (acceptation), sinon null.
  Future<String?> respondConnectionRequest(String requestId, ConnectionAction action);
  Future<void> cancelConnectionRequest(String requestId);
  Future<List<ConnectionRequest>> listConnectionRequests();
  Future<bool> getAcceptConnectionRequests();
  Future<void> setAcceptConnectionRequests(bool accept);
  Future<List<ChatMessage>> getMessages(String conversationId, {int limit = 50});
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String clientMsgId,
    required String body,
    String? replyToId,
    int? ttlSeconds,
    List<String> mentions = const [],
  });

  /// Vocal : envoyé à la fonction voice-send, qui MESURE le son avant de le publier.
  /// Idempotent par [clientMsgId] (un renvoi renvoie le même message).
  /// Lot 7.3a : autocollant (« série/nom ») ; aucune image n'est envoyée.
  Future<ChatMessage> sendSticker({
    required String conversationId,
    required String clientMsgId,
    required String sticker,
    String? replyToId,
    int? ttlSeconds,
  });

  Future<ChatMessage> sendVoice({
    required String conversationId,
    required String clientMsgId,
    required Uint8List audio,
    String? replyToId,
    int? ttlSeconds,
    List<int>? waveform,
    bool viewOnce = false,
  });

  /// Son d'un vocal, téléchargé du stockage privé avec le jeton de l'utilisateur
  /// (refusé si le message a expiré, a été supprimé, ou si l'on n'est pas membre).
  Future<Uint8List> downloadVoice(String mediaPath);

  /// Photo : envoyée à photo-send, qui DÉBITE le quota du jour, vérifie la photo et en
  /// retire les métadonnées avant de la publier. Idempotent par [clientMsgId].
  Future<ChatMessage> sendPhoto({
    required String conversationId,
    required String clientMsgId,
    required Uint8List jpeg,
    String? caption,
    String? replyToId,
    int? ttlSeconds,
    bool viewOnce = false,
  });

  /// Photo d'un message (stockage privé, avec le jeton ; refusée après expiration).
  Future<Uint8List> downloadPhoto(String mediaPath);

  // Lot 7.3b : vue unique, GIF, aperçus des liens.
  /// Ouvre une photo ou un vocal en vue unique (lisible 2 minutes, jusqu'à la fermeture).
  Future<void> openViewOnce(String messageId);
  Future<void> closeViewOnce(String messageId);

  /// Recherche (ou tendances si [query] est vide) ; [filter] : « g » ou « pg13 ».
  Future<(List<GifResult>, bool)> searchGifs(String query, {int page = 1, String filter = 'g'});
  Future<ChatMessage> sendGif({
    required String conversationId,
    required String clientMsgId,
    required String slug,
    String? replyToId,
    int? ttlSeconds,
    String filter = 'g',
  });
  Future<Uint8List> downloadGif(String mediaPath);

  /// Demande au serveur l'aperçu du premier lien de MON message (sans effet sinon).
  Future<void> requestLinkPreview(String messageId);
  Future<Uint8List> downloadLinkImage(String imagePath);

  /// Photo de profil d'une personne visible (jamais en cas de blocage).
  Future<Uint8List> downloadAvatar(String avatarPath);

  /// Compteur de photos du jour.
  Future<PhotoQuota> getPhotoQuota();

  // ---------------------------------------------------------------- groupes (lot 3.3)
  /// Crée un groupe (on en devient propriétaire) et invite ces personnes.
  Future<String> createGroup({
    required String title,
    String? description,
    List<String> inviteeIds = const [],
  });

  /// Invite des personnes (administrateurs) ; renvoie le nombre d'invitations envoyées.
  Future<int> inviteToGroup(String conversationId, List<String> userIds);
  Future<List<GroupInvitation>> listInvitations();

  /// Accepter (renvoie l'identifiant du groupe) ou refuser une invitation.
  Future<String?> respondToInvitation(String invitationId, {required bool accept});
  Future<List<GroupMember>> getMembers(String conversationId);
  Future<void> setMemberRole(String conversationId, String userId, {required bool admin});
  Future<void> transferOwnership(String conversationId, String userId);
  Future<void> removeMember(String conversationId, String userId);
  Future<void> leaveGroup(String conversationId);
  Future<void> updateGroupInfo(String conversationId, {String? title, String? description});
  Future<void> setGroupSettings(String conversationId, {String? posting, String? infoEditing});

  /// Sourdine jusqu'à [until] (null : levée). Groupes et discussions 1:1.
  Future<void> setMute(String conversationId, DateTime? until);
  Future<void> setGroupAvatar(String conversationId, Uint8List jpeg);
  Future<void> removeGroupAvatar(String conversationId);

  /// Lot 10.2 : cacher (ou ne plus cacher) une discussion, pour moi seulement.
  Future<void> setConversationSecret(String conversationId, bool secret);

  /// Lot 10.1 : effacer après lecture (30, 300 ou 3600 s ; null : couper).
  Future<void> setReadErase(String conversationId, int? seconds);

  Future<int> setConversationTtl(String conversationId, int seconds);
  Future<void> setConversationFlags(String conversationId, {bool? pinned, bool? archived});
  Future<void> signalTyping(String conversationId);

  /// Signaler un message ou un contact ; `reason == 'support'` : demande d'assistance.
  Future<void> report({
    required String reason,
    String? reportedUserId,
    String? conversationId,
    String? messageId,
    String? details,
    bool includeMessage = false,
  });

  /// Lot 5.4 : mes demandes d'assistance (90 jours) et les réponses de l'équipe.
  Future<List<SupportRequest>> mySupportRequests();

  /// Suppression définitive du compte (confirmation « SUPPRIMER » exigée par le serveur).
  Future<void> deleteMyAccount();
  Future<void> markConversation(
    String conversationId, {
    DateTime? deliveredUpTo,
    DateTime? readUpTo,
  });
  Future<void> editMessage(String messageId, String body);
  Future<void> deleteForEveryone(String messageId);
  Future<void> deleteForMe(String messageId);
  Future<void> setReaction(String messageId, String emoji);
  Future<void> removeReaction(String messageId);
  Future<Map<String, Object?>> getClientPolicies();
  Future<List<BlockedUser>> listBlockedUsers();
  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);

  // Confidentialité et présence (lot 4.3)
  Future<PrivacySettings> getMyPrivacy();
  Future<void> setMyPrivacy(PrivacySettings settings);

  /// Lot 7.1a : fiche d'un contact (null : aucune discussion commune).
  Future<ContactProfile?> getContactProfile(String userId);
  Future<List<CommonGroup>> listCommonGroups(String userId);

  /// Photos et vocaux encore présents dans la discussion (72 h au plus).
  Future<List<ChatMessage>> listConversationMedia(String conversationId);

  /// L'application est ouverte ([online]) ou passe en arrière-plan.
  Future<void> touchPresence({required bool online});
  Future<UserPresence> getPresence(String userId);

  /// Vider : chez moi, ou pour tout le monde (1:1 : demande d'accord ; groupe : admin).
  /// Renvoie 'cleared' ou 'requested'.
  Future<String> clearConversation(String conversationId, {required bool everyone});

  /// Réponse à une demande de l'autre personne : 'cleared' ou 'refused'.
  Future<String> respondClearRequest(String conversationId, {required bool accept});
  Future<void> cancelClearRequest(String conversationId);

  // Lot 7.1b : rejoindre un groupe par code (ou QR code), demandes d'adhésion.
  /// Code du groupe (administrateurs), créé au premier appel.
  Future<String> getGroupInviteCode(String conversationId);

  /// Nouveau code : l'ancien cesse aussitôt de fonctionner.
  Future<String> resetGroupInviteCode(String conversationId);
  Future<GroupJoinSettings> getGroupJoinSettings(String conversationId);
  Future<void> setGroupJoinApproval(String conversationId, {required bool required});
  Future<GroupPreview> previewGroupByCode(String code);
  Future<JoinResult> joinGroupByCode(String code);
  Future<void> cancelJoinRequest(String conversationId);
  Future<List<MyJoinRequest>> listMyJoinRequests();
  Future<List<JoinRequest>> listGroupJoinRequests(String conversationId);
  Future<void> respondToJoinRequest(String requestId, {required bool approve});

  // Lot 7.2b1 : supprimer une discussion (chez moi / pour nous deux) ou un groupe (pour tous).
  /// Renvoie 'deleted' ou 'requested' (accord de l'autre personne attendu).
  Future<String> deleteConversation(String conversationId, {required bool everyone});
  Future<List<GroupDeletionNotice>> listGroupDeletionNotices();
  Future<void> dismissGroupDeletionNotice(String id);

  // Lot 7.2c2 : épinglés, favoris, infos d'un message, « Mentions seulement ».
  Future<void> pinMessage(String messageId, {required bool pin});
  Future<List<MessageRef>> listPinnedMessages(String conversationId);
  Future<int> setFavorites(List<String> messageIds, {required bool on});
  Future<List<MessageRef>> listFavorites(String conversationId);

  /// Lot 8.3a : favoris de toutes mes discussions (les plus récents d'abord).
  Future<List<MessageRef>> listAllFavorites();
  Future<List<MessageReceipt>> getMessageInfo(String messageId);

  /// 'all' ou 'mentions'.
  Future<String> getNotifyMode(String conversationId);
  Future<void> setNotifyMode(String conversationId, String mode);

  // Lot 7.2a : confidentialité propre à une discussion ou un groupe.
  Future<ConversationPrivacy> getConversationPrivacy(String conversationId);
  Future<void> setConversationPrivacy(
    String conversationId,
    ConversationPrivacy privacy, {
    required bool group,
  });
}

class SupabaseMessagingApi implements MessagingApi {
  SupabaseMessagingApi(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? params]) =>
      _guard(() async {
        final res = await _client.rpc<dynamic>(fn, params: params) as List<dynamic>;
        return [for (final r in res) Map<String, dynamic>.from(r as Map)];
      });

  @override
  Future<List<ConversationSummary>> listConversations() async =>
      (await _rows('list_conversations')).map(ConversationSummary.fromJson).toList();

  @override
  Future<FoundUser?> findByHandle(String handle) async {
    final rows = await _rows('find_user_by_handle', {'p_handle': handle});
    return rows.isEmpty ? null : FoundUser.fromJson(rows.first);
  }

  @override
  Future<FoundUser?> findByPhone(String phoneE164) async {
    final rows = await _rows('find_user_by_phone', {'p_phone': phoneE164});
    return rows.isEmpty ? null : FoundUser.fromJson(rows.first);
  }

  @override
  Future<String> startDirectConversation(String otherUserId) => _guard(
    () async => await _client.rpc<dynamic>(
      'start_direct_conversation',
      params: {'p_other_user_id': otherUserId},
    ) as String,
  );

  @override
  Future<ConnectionStatus> connectionStatus(String userId) async =>
      ConnectionStatus.fromJson((await _rows('connection_status', {'p_user_id': userId})).first);

  @override
  Future<ConnectionSendResult> sendConnectionRequest(String userId, {String? note}) async =>
      ConnectionSendResult.fromJson(
        (await _rows('send_connection_request', {'p_user_id': userId, 'p_note': note})).first,
      );

  @override
  Future<String?> respondConnectionRequest(String requestId, ConnectionAction action) async =>
      (await _rows('respond_connection_request', {
            'p_request_id': requestId,
            'p_action': action.name,
          })).first['conversation_id']
          as String?;

  @override
  Future<void> cancelConnectionRequest(String requestId) => _guard(
    () => _client.rpc<dynamic>('cancel_connection_request', params: {'p_request_id': requestId}),
  );

  @override
  Future<List<ConnectionRequest>> listConnectionRequests() async =>
      (await _rows('list_connection_requests')).map(ConnectionRequest.fromJson).toList();

  @override
  Future<bool> getAcceptConnectionRequests() async =>
      (await _rows('get_connection_settings')).first['accept_requests'] as bool? ?? true;

  @override
  Future<void> setAcceptConnectionRequests(bool accept) => _guard(
    () => _client.rpc<dynamic>('set_connection_settings', params: {'p_accept_requests': accept}),
  );

  @override
  Future<List<ChatMessage>> getMessages(String conversationId, {int limit = 50}) async {
    final rows = await _rows('get_messages', {
      'p_conversation_id': conversationId,
      'p_limit': limit,
    });
    return rows.map(ChatMessage.fromJson).toList().reversed.toList();
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String clientMsgId,
    required String body,
    String? replyToId,
    int? ttlSeconds,
    List<String> mentions = const [],
  }) async {
    final row = (await _rows('send_message', {
      'p_conversation_id': conversationId,
      'p_client_msg_id': clientMsgId,
      'p_body': body,
      'p_reply_to_id': replyToId,
      'p_ttl_seconds': ttlSeconds,
      // Seulement s'il y en a : un serveur d'avant le lot 7.1b reste compatible.
      if (mentions.isNotEmpty) 'p_mentions': mentions,
    })).single;
    final sentAt = DateTime.parse(row['sent_at'] as String);
    return ChatMessage(
      id: row['id'] as String,
      senderId: _client.auth.currentUser?.id,
      body: body.trim(),
      replyToId: replyToId,
      sentAt: sentAt,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      updatedAt: sentAt,
      mentions: mentions,
    );
  }

  @override
  Future<ChatMessage> sendSticker({
    required String conversationId,
    required String clientMsgId,
    required String sticker,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    final row = (await _rows('send_sticker', {
      'p_conversation_id': conversationId,
      'p_client_msg_id': clientMsgId,
      'p_sticker': sticker,
      'p_reply_to_id': replyToId,
      'p_ttl_seconds': ttlSeconds,
    })).single;
    final sentAt = DateTime.parse(row['sent_at'] as String);
    return ChatMessage(
      id: row['id'] as String,
      senderId: _client.auth.currentUser?.id,
      kind: 'sticker',
      body: sticker,
      replyToId: replyToId,
      sentAt: sentAt,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      updatedAt: sentAt,
    );
  }

  @override
  Future<ChatMessage> sendVoice({
    required String conversationId,
    required String clientMsgId,
    required Uint8List audio,
    String? replyToId,
    int? ttlSeconds,
    List<int>? waveform,
    bool viewOnce = false,
  }) => _guard(() async {
    final res = await _client.functions.invoke(
      'voice-send',
      body: audio,
      headers: const {'Content-Type': 'audio/mp4'},
      queryParameters: {
        'conversation_id': conversationId,
        'client_msg_id': clientMsgId,
        'reply_to_id': ?replyToId,
        if (ttlSeconds != null) 'ttl_seconds': '$ttlSeconds',
        if (waveform != null && waveform.isNotEmpty) 'waveform': waveform.join(','),
        if (viewOnce) 'view_once': '1',
      },
    );
    final row = Map<String, dynamic>.from(res.data as Map);
    final sentAt = DateTime.parse(row['sent_at'] as String);
    return ChatMessage(
      id: row['id'] as String,
      kind: 'voice',
      waveform: (row['media_waveform'] as List<dynamic>?)?.map((v) => (v as num).toInt()).toList(),
      senderId: _client.auth.currentUser?.id,
      replyToId: replyToId,
      sentAt: sentAt,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      updatedAt: sentAt,
      mediaPath: viewOnce ? null : row['media_path'] as String?,
      durationMs: (row['media_duration_ms'] as num?)?.toInt(),
      viewOnce: viewOnce,
    );
  });

  @override
  Future<Uint8List> downloadVoice(String mediaPath) =>
      _guard(() => _client.storage.from('voice').download(mediaPath));

  @override
  Future<ChatMessage> sendPhoto({
    required String conversationId,
    required String clientMsgId,
    required Uint8List jpeg,
    String? caption,
    String? replyToId,
    int? ttlSeconds,
    bool viewOnce = false,
  }) => _guard(() async {
    final res = await _client.functions.invoke(
      'photo-send',
      body: jpeg,
      headers: const {'Content-Type': 'image/jpeg'},
      queryParameters: {
        'conversation_id': conversationId,
        'client_msg_id': clientMsgId,
        if (!viewOnce && caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
        'reply_to_id': ?replyToId,
        if (ttlSeconds != null) 'ttl_seconds': '$ttlSeconds',
        if (viewOnce) 'view_once': '1',
      },
    );
    final row = Map<String, dynamic>.from(res.data as Map);
    final sentAt = DateTime.parse(row['sent_at'] as String);
    return ChatMessage(
      id: row['id'] as String,
      kind: 'photo',
      senderId: _client.auth.currentUser?.id,
      body: row['body'] as String?,
      replyToId: replyToId,
      sentAt: sentAt,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      updatedAt: sentAt,
      mediaPath: viewOnce ? null : row['media_path'] as String?,
      width: (row['media_width'] as num?)?.toInt(),
      height: (row['media_height'] as num?)?.toInt(),
      viewOnce: viewOnce,
    );
  });

  @override
  Future<Uint8List> downloadPhoto(String mediaPath) =>
      _guard(() => _client.storage.from('photos').download(mediaPath));

  @override
  Future<void> openViewOnce(String messageId) =>
      _call('open_view_once', {'p_message_id': messageId});

  @override
  Future<void> closeViewOnce(String messageId) =>
      _call('close_view_once', {'p_message_id': messageId});

  @override
  Future<(List<GifResult>, bool)> searchGifs(String query, {int page = 1, String filter = 'g'}) =>
      _guard(() async {
        final res = await _client.functions.invoke(
          'gif-search',
          method: HttpMethod.get,
          queryParameters: {'q': query, 'page': '$page', 'filter': filter},
        );
        final data = Map<String, dynamic>.from(res.data as Map);
        return (
          [
            for (final g in data['items'] as List<dynamic>? ?? const [])
              GifResult.fromJson(Map<String, dynamic>.from(g as Map)),
          ],
          data['has_next'] as bool? ?? false,
        );
      });

  @override
  Future<ChatMessage> sendGif({
    required String conversationId,
    required String clientMsgId,
    required String slug,
    String? replyToId,
    int? ttlSeconds,
    String filter = 'g',
  }) => _guard(() async {
    final res = await _client.functions.invoke(
      'gif-send',
      queryParameters: {
        'conversation_id': conversationId,
        'client_msg_id': clientMsgId,
        'slug': slug,
        'filter': filter,
        'reply_to_id': ?replyToId,
        if (ttlSeconds != null) 'ttl_seconds': '$ttlSeconds',
      },
    );
    final row = Map<String, dynamic>.from(res.data as Map);
    final sentAt = DateTime.parse(row['sent_at'] as String);
    return ChatMessage(
      id: row['id'] as String,
      kind: 'gif',
      senderId: _client.auth.currentUser?.id,
      replyToId: replyToId,
      sentAt: sentAt,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      updatedAt: sentAt,
      mediaPath: row['media_path'] as String?,
      width: (row['media_width'] as num?)?.toInt(),
      height: (row['media_height'] as num?)?.toInt(),
    );
  });

  @override
  Future<Uint8List> downloadGif(String mediaPath) =>
      _guard(() => _client.storage.from('gifs').download(mediaPath));

  @override
  Future<void> requestLinkPreview(String messageId) => _guard(
    () => _client.functions.invoke('link-preview', queryParameters: {'message_id': messageId}),
  );

  @override
  Future<Uint8List> downloadLinkImage(String imagePath) =>
      _guard(() => _client.storage.from('previews').download(imagePath));

  @override
  Future<Uint8List> downloadAvatar(String avatarPath) =>
      _guard(() => _client.storage.from('avatars').download(avatarPath));

  @override
  Future<String> createGroup({
    required String title,
    String? description,
    List<String> inviteeIds = const [],
  }) => _guard(
    () async => await _client.rpc<dynamic>(
      'create_group',
      params: {'p_title': title, 'p_description': description, 'p_invitee_ids': inviteeIds},
    ) as String,
  );

  @override
  Future<int> inviteToGroup(String conversationId, List<String> userIds) => _guard(
    () async => (await _client.rpc<dynamic>(
      'invite_to_group',
      params: {'p_conversation_id': conversationId, 'p_user_ids': userIds},
    ) as num).toInt(),
  );

  @override
  Future<List<GroupInvitation>> listInvitations() async =>
      (await _rows('list_my_invitations')).map(GroupInvitation.fromJson).toList();

  @override
  Future<String?> respondToInvitation(String invitationId, {required bool accept}) => _guard(
    () async => await _client.rpc<dynamic>(
      'respond_to_invitation',
      params: {'p_invitation_id': invitationId, 'p_accept': accept},
    ) as String?,
  );

  @override
  Future<List<GroupMember>> getMembers(String conversationId) async => (await _rows(
    'get_conversation_members',
    {'p_conversation_id': conversationId},
  )).map(GroupMember.fromJson).toList();

  @override
  Future<void> setMemberRole(String conversationId, String userId, {required bool admin}) =>
      _call('set_member_role', {
        'p_conversation_id': conversationId,
        'p_user_id': userId,
        'p_role': admin ? 'admin' : 'member',
      });

  @override
  Future<void> transferOwnership(String conversationId, String userId) =>
      _call('transfer_group_ownership', {'p_conversation_id': conversationId, 'p_user_id': userId});

  @override
  Future<void> removeMember(String conversationId, String userId) =>
      _call('remove_group_member', {'p_conversation_id': conversationId, 'p_user_id': userId});

  @override
  Future<void> leaveGroup(String conversationId) =>
      _call('leave_group', {'p_conversation_id': conversationId});

  @override
  Future<void> updateGroupInfo(String conversationId, {String? title, String? description}) =>
      _call('update_group_info', {
        'p_conversation_id': conversationId,
        'p_title': title,
        'p_description': description,
      });

  @override
  Future<void> setGroupSettings(String conversationId, {String? posting, String? infoEditing}) =>
      _call('set_group_settings', {
        'p_conversation_id': conversationId,
        'p_posting': posting,
        'p_info_editing': infoEditing,
      });

  @override
  Future<void> setMute(String conversationId, DateTime? until) => _call('set_conversation_mute', {
    'p_conversation_id': conversationId,
    'p_until': until?.toUtc().toIso8601String(),
  });

  @override
  Future<void> setGroupAvatar(String conversationId, Uint8List jpeg) => _guard(() async {
    await _client.functions.invoke(
      'avatar-set',
      body: jpeg,
      headers: const {'Content-Type': 'image/jpeg'},
      queryParameters: {'conversation_id': conversationId},
    );
  });

  @override
  Future<void> removeGroupAvatar(String conversationId) =>
      _call('remove_group_avatar', {'p_conversation_id': conversationId});

  @override
  Future<PhotoQuota> getPhotoQuota() => _guard(
    () async => PhotoQuota.fromJson(
      Map<String, dynamic>.from(await _client.rpc<dynamic>('get_photo_quota') as Map),
    ),
  );

  @override
  Future<void> markConversation(
    String conversationId, {
    DateTime? deliveredUpTo,
    DateTime? readUpTo,
  }) => _guard(
    () => _client.rpc<dynamic>(
      'mark_conversation',
      params: {
        'p_conversation_id': conversationId,
        'p_delivered_up_to': deliveredUpTo?.toUtc().toIso8601String(),
        'p_read_up_to': readUpTo?.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<void> setConversationSecret(String conversationId, bool secret) =>
      _call('set_conversation_secret', {'p_conversation_id': conversationId, 'p_secret': secret});

  @override
  Future<void> setReadErase(String conversationId, int? seconds) =>
      _call('set_read_erase', {'p_conversation_id': conversationId, 'p_seconds': seconds});

  @override
  Future<int> setConversationTtl(String conversationId, int seconds) => _guard(
    () async => (await _client.rpc<dynamic>(
      'set_conversation_ttl',
      params: {'p_conversation_id': conversationId, 'p_ttl_seconds': seconds},
    ) as num).toInt(),
  );

  @override
  Future<void> setConversationFlags(String conversationId, {bool? pinned, bool? archived}) => _call(
    'set_conversation_flags',
    {'p_conversation_id': conversationId, 'p_pinned': pinned, 'p_archived': archived},
  );

  @override
  Future<void> signalTyping(String conversationId) =>
      _call('signal_typing', {'p_conversation_id': conversationId});

  @override
  Future<PrivacySettings> getMyPrivacy() => _guard(() async {
    final rows = await _client.rpc<dynamic>('get_my_privacy') as List<dynamic>;
    return rows.isEmpty
        ? const PrivacySettings()
        : PrivacySettings.fromJson(Map<String, dynamic>.from(rows.first as Map));
  });

  @override
  Future<void> setMyPrivacy(PrivacySettings settings) => _call('set_my_privacy', settings.toRpc());

  @override
  Future<ContactProfile?> getContactProfile(String userId) async {
    final rows = await _rows('get_contact_profile', {'p_user_id': userId});
    return rows.isEmpty ? null : ContactProfile.fromJson(rows.first);
  }

  @override
  Future<List<CommonGroup>> listCommonGroups(String userId) async =>
      (await _rows('list_common_groups', {'p_user_id': userId})).map(CommonGroup.fromJson).toList();

  @override
  Future<List<ChatMessage>> listConversationMedia(String conversationId) async => (await _rows(
    'list_conversation_media',
    {'p_conversation_id': conversationId},
  )).map(mediaMessageFromJson).toList();

  @override
  Future<void> touchPresence({required bool online}) =>
      _call('touch_presence', {'p_online': online});

  @override
  Future<UserPresence> getPresence(String userId) => _guard(() async {
    final rows =
        await _client.rpc<dynamic>('get_presence', params: {'p_user_id': userId}) as List<dynamic>;
    return rows.isEmpty
        ? const UserPresence()
        : UserPresence.fromJson(Map<String, dynamic>.from(rows.first as Map));
  });

  @override
  Future<String> clearConversation(String conversationId, {required bool everyone}) => _guard(
    () async => await _client.rpc<dynamic>(
      'clear_conversation',
      params: {'p_conversation_id': conversationId, 'p_scope': everyone ? 'everyone' : 'me'},
    ) as String,
  );

  @override
  Future<String> respondClearRequest(String conversationId, {required bool accept}) => _guard(
    () async => await _client.rpc<dynamic>(
      'respond_clear_request',
      params: {'p_conversation_id': conversationId, 'p_accept': accept},
    ) as String,
  );

  @override
  Future<void> cancelClearRequest(String conversationId) =>
      _call('cancel_clear_request', {'p_conversation_id': conversationId});

  @override
  Future<void> report({
    required String reason,
    String? reportedUserId,
    String? conversationId,
    String? messageId,
    String? details,
    bool includeMessage = false,
  }) => _call('report', {
    'p_reason': reason,
    'p_reported_user_id': reportedUserId,
    'p_conversation_id': conversationId,
    'p_message_id': messageId,
    'p_details': details,
    'p_include_message': includeMessage,
  });

  @override
  Future<List<SupportRequest>> mySupportRequests() async =>
      (await _rows('my_support_requests')).map(SupportRequest.fromJson).toList();

  @override
  Future<void> deleteMyAccount() => _call('delete_my_account', {'p_confirmation': 'SUPPRIMER'});

  Future<void> _call(String fn, Map<String, dynamic> params) =>
      _guard(() => _client.rpc<dynamic>(fn, params: params));

  @override
  Future<void> editMessage(String messageId, String body) =>
      _call('edit_message', {'p_message_id': messageId, 'p_body': body});

  @override
  Future<void> deleteForEveryone(String messageId) =>
      _call('delete_message_for_everyone', {'p_message_id': messageId});

  @override
  Future<void> deleteForMe(String messageId) =>
      _call('delete_message_for_me', {'p_message_id': messageId});

  @override
  Future<void> setReaction(String messageId, String emoji) =>
      _call('set_reaction', {'p_message_id': messageId, 'p_emoji': emoji});

  @override
  Future<void> removeReaction(String messageId) =>
      _call('remove_reaction', {'p_message_id': messageId});

  @override
  Future<Map<String, Object?>> getClientPolicies() => _guard(() async {
    final res = await _client.rpc<dynamic>('get_client_policies') as Map;
    return Map<String, Object?>.from(res['values'] as Map? ?? const {});
  });

  @override
  Future<List<BlockedUser>> listBlockedUsers() async =>
      (await _rows('list_blocked_users')).map(BlockedUser.fromJson).toList();

  @override
  Future<void> blockUser(String userId) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AppFailure(FailureCode.authRequired);
    await _client
        .from('blocks')
        .upsert(
          {'blocker_id': me, 'blocked_id': userId},
          onConflict: 'blocker_id,blocked_id',
          ignoreDuplicates: true,
        );
  });

  @override
  Future<void> unblockUser(String userId) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AppFailure(FailureCode.authRequired);
    await _client.from('blocks').delete().eq('blocker_id', me).eq('blocked_id', userId);
  });

  @override
  Future<String> getGroupInviteCode(String conversationId) => _guard(
    () async => await _client.rpc<dynamic>(
      'get_group_invite_code',
      params: {'p_conversation_id': conversationId},
    ) as String,
  );

  @override
  Future<String> resetGroupInviteCode(String conversationId) => _guard(
    () async => await _client.rpc<dynamic>(
      'reset_group_invite_code',
      params: {'p_conversation_id': conversationId},
    ) as String,
  );

  @override
  Future<GroupJoinSettings> getGroupJoinSettings(String conversationId) async =>
      GroupJoinSettings.fromJson(
        (await _rows('get_group_join_settings', {'p_conversation_id': conversationId})).single,
      );

  @override
  Future<void> setGroupJoinApproval(String conversationId, {required bool required}) => _call(
    'set_group_join_approval',
    {'p_conversation_id': conversationId, 'p_required': required},
  );

  @override
  Future<GroupPreview> previewGroupByCode(String code) async =>
      GroupPreview.fromJson((await _rows('preview_group_by_code', {'p_code': code})).single);

  @override
  Future<JoinResult> joinGroupByCode(String code) async =>
      JoinResult.fromJson((await _rows('join_group_by_code', {'p_code': code})).single);

  @override
  Future<void> cancelJoinRequest(String conversationId) =>
      _call('cancel_join_request', {'p_conversation_id': conversationId});

  @override
  Future<List<MyJoinRequest>> listMyJoinRequests() async =>
      (await _rows('list_my_join_requests')).map(MyJoinRequest.fromJson).toList();

  @override
  Future<List<JoinRequest>> listGroupJoinRequests(String conversationId) async => (await _rows(
    'list_group_join_requests',
    {'p_conversation_id': conversationId},
  )).map(JoinRequest.fromJson).toList();

  @override
  Future<void> respondToJoinRequest(String requestId, {required bool approve}) =>
      _call('respond_to_join_request', {'p_request_id': requestId, 'p_approve': approve});

  @override
  Future<ConversationPrivacy> getConversationPrivacy(String conversationId) async =>
      ConversationPrivacy.fromJson(
        (await _rows('get_conversation_privacy', {'p_conversation_id': conversationId})).single,
      );

  @override
  Future<void> setConversationPrivacy(
    String conversationId,
    ConversationPrivacy privacy, {
    required bool group,
  }) => _call('set_conversation_privacy', privacy.toRpc(conversationId, group: group));

  @override
  Future<String> deleteConversation(String conversationId, {required bool everyone}) => _guard(
    () async => await _client.rpc<dynamic>(
      'delete_conversation',
      params: {'p_conversation_id': conversationId, 'p_scope': everyone ? 'everyone' : 'me'},
    ) as String,
  );

  @override
  Future<List<GroupDeletionNotice>> listGroupDeletionNotices() async =>
      (await _rows('list_group_deletion_notices')).map(GroupDeletionNotice.fromJson).toList();

  @override
  Future<void> dismissGroupDeletionNotice(String id) =>
      _call('dismiss_group_deletion_notice', {'p_id': id});

  @override
  Future<void> pinMessage(String messageId, {required bool pin}) =>
      _call('pin_message', {'p_message_id': messageId, 'p_pin': pin});

  @override
  Future<List<MessageRef>> listPinnedMessages(String conversationId) async => (await _rows(
    'list_pinned_messages',
    {'p_conversation_id': conversationId},
  )).map(MessageRef.pinned).toList();

  @override
  Future<int> setFavorites(List<String> messageIds, {required bool on}) => _guard(
    () async =>
        (await _client.rpc<dynamic>(
          'set_message_favorites',
          params: {'p_message_ids': messageIds, 'p_on': on},
        ) as num?)?.toInt() ??
        0,
  );

  @override
  Future<List<MessageRef>> listFavorites(String conversationId) async => (await _rows(
    'list_favorite_messages',
    {'p_conversation_id': conversationId},
  )).map(MessageRef.favorite).toList();

  @override
  Future<List<MessageRef>> listAllFavorites() async =>
      (await _rows('list_all_favorite_messages')).map(MessageRef.favorite).toList();

  @override
  Future<List<MessageReceipt>> getMessageInfo(String messageId) async => (await _rows(
    'get_message_info',
    {'p_message_id': messageId},
  )).map(MessageReceipt.fromJson).toList();

  @override
  Future<String> getNotifyMode(String conversationId) => _guard(
    () async =>
        (await _client.rpc<dynamic>(
          'get_notify_mode',
          params: {'p_conversation_id': conversationId},
        ) as String?) ??
        'all',
  );

  @override
  Future<void> setNotifyMode(String conversationId, String mode) =>
      _call('set_notify_mode', {'p_conversation_id': conversationId, 'p_mode': mode});
}
