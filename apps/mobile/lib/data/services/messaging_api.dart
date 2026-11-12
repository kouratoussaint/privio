import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/messaging.dart';

/// Messagerie via les RPC sécurisées du lot 2.1. Aucune écriture directe en table,
/// sauf les blocages (table `blocks`, protégée par RLS : on ne bloque qu'en son nom).
abstract interface class MessagingApi {
  Future<List<ConversationSummary>> listConversations();
  Future<FoundUser?> findByHandle(String handle);
  Future<FoundUser?> findByPhone(String phoneE164);
  Future<String> startDirectConversation(String otherUserId);
  Future<List<ChatMessage>> getMessages(String conversationId, {int limit = 50});
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String clientMsgId,
    required String body,
    String? replyToId,
  });
  Future<void> markConversation(
    String conversationId, {
    DateTime? deliveredUpTo,
    DateTime? readUpTo,
  });
  Future<List<BlockedUser>> listBlockedUsers();
  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);
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
  }) async {
    final row = (await _rows('send_message', {
      'p_conversation_id': conversationId,
      'p_client_msg_id': clientMsgId,
      'p_body': body,
      'p_reply_to_id': replyToId,
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
    );
  }

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
}
