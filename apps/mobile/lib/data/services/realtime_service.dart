import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Signal sans contenu reçu du serveur : « quelque chose a changé dans telle discussion ».
class RealtimeSignal {
  const RealtimeSignal({required this.event, this.conversationId});

  final String event;
  final String? conversationId;
}

abstract interface class RealtimeService {
  Stream<RealtimeSignal> get signals;
  Future<void> start(String userId);
  Future<void> stop();
}

/// Canal PRIVÉ `user:<id>` (politique RLS côté serveur : chacun n'écoute que le sien).
class SupabaseRealtimeService implements RealtimeService {
  SupabaseRealtimeService(this._client);

  static const events = ['message', 'message_changed', 'receipt'];

  final SupabaseClient _client;
  final _controller = StreamController<RealtimeSignal>.broadcast();
  RealtimeChannel? _channel;
  String? _userId;

  @override
  Stream<RealtimeSignal> get signals => _controller.stream;

  @override
  Future<void> start(String userId) async {
    if (_userId == userId && _channel != null) return;
    await stop();
    _userId = userId;
    var channel = _client.channel('user:$userId', opts: const RealtimeChannelConfig(private: true));
    for (final event in events) {
      channel = channel.onBroadcast(
        event: event,
        callback: (payload) {
          final inner = payload['payload'];
          final data = inner is Map ? inner : payload;
          _controller.add(
            RealtimeSignal(event: event, conversationId: data['conversation_id'] as String?),
          );
        },
      );
    }
    _channel = channel.subscribe();
  }

  @override
  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _userId = null;
    if (channel != null) await _client.removeChannel(channel);
  }
}
