import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signal sans contenu reçu du serveur : « quelque chose a changé dans telle discussion ».
/// `conversationId == null` : rafraîchir tout (reconnexion, retour dans l'application).
class RealtimeSignal {
  const RealtimeSignal({required this.event, this.conversationId});

  final String event;
  final String? conversationId;
}

enum RealtimeState { stopped, connecting, connected, error }

class RealtimeStatus {
  const RealtimeStatus(this.state, [this.detail]);

  final RealtimeState state;
  final String? detail;

  String get label => switch (state) {
    RealtimeState.connected => 'Connecté',
    RealtimeState.connecting => 'Connexion…',
    RealtimeState.error => 'Indisponible${detail == null ? '' : ' ($detail)'}',
    RealtimeState.stopped => 'Arrêté',
  };
}

abstract interface class RealtimeService {
  Stream<RealtimeSignal> get signals;
  ValueListenable<RealtimeStatus> get status;
  Future<void> start(String userId);
  Future<void> stop();
}

/// Canal PRIVÉ `user:<id>` (politique RLS côté serveur : chacun n'écoute que le sien).
/// Robustesse : jeton transmis AVANT l'abonnement, reconnexion automatique avec délai
/// croissant, réabonnement au retour au premier plan.
class SupabaseRealtimeService implements RealtimeService {
  SupabaseRealtimeService(this._client);

  // « invitation » (groupes) et « request » (demandes de connexion, lot 4.7) : listes à jour.
  static const events = [
    'message',
    'message_changed',
    'receipt',
    'invitation',
    'request',
    // Lot 5.3 : suspension, avertissement ou réactivation du compte.
    'moderation',
    // Lot 5.4 : réponse de l'assistance ; téléphone déconnecté par l'assistance.
    'support',
    'disconnected',
  ];
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final SupabaseClient _client;
  final _controller = StreamController<RealtimeSignal>.broadcast();
  final _status = ValueNotifier(const RealtimeStatus(RealtimeState.stopped));
  RealtimeChannel? _channel;
  String? _userId;
  Timer? _retry;
  int _attempt = 0;
  AppLifecycleListener? _lifecycle;

  @override
  Stream<RealtimeSignal> get signals => _controller.stream;

  @override
  ValueListenable<RealtimeStatus> get status => _status;

  @override
  Future<void> start(String userId) async {
    if (_userId == userId && _channel != null) return;
    await stop();
    _userId = userId;
    _attempt = 0;
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    await _subscribe();
  }

  void _onResume() {
    // Au retour dans l'app : rafraîchir les écrans, et réabonner si nécessaire.
    _controller.add(const RealtimeSignal(event: 'resume'));
    if (_status.value.state != RealtimeState.connected) unawaited(_resubscribe());
  }

  Future<void> _subscribe() async {
    final userId = _userId;
    if (userId == null) return;
    _status.value = const RealtimeStatus(RealtimeState.connecting);
    // Le canal privé est autorisé avec le jeton de l'utilisateur : on le transmet
    // explicitement avant de rejoindre (sinon le serveur refuse l'abonnement).
    await _client.realtime.setAuth(_client.auth.currentSession?.accessToken);

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
    _channel = channel.subscribe((status, error) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          final reconnected = _attempt > 0;
          _attempt = 0;
          _status.value = const RealtimeStatus(RealtimeState.connected);
          // Après une coupure, des messages ont pu arriver : on rafraîchit tout.
          if (reconnected) _controller.add(const RealtimeSignal(event: 'reconnected'));
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _status.value = RealtimeStatus(RealtimeState.error, _short(error));
          _scheduleRetry();
        case RealtimeSubscribeStatus.closed:
          if (_userId != null) {
            _status.value = const RealtimeStatus(RealtimeState.error, 'fermé');
            _scheduleRetry();
          }
      }
    });
  }

  static String? _short(Object? error) {
    if (error == null) return null;
    final s = error.toString();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    final delay = _retryDelays[_attempt.clamp(0, _retryDelays.length - 1)];
    _attempt++;
    _retry = Timer(delay, () => unawaited(_resubscribe()));
  }

  Future<void> _resubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel).catchError((Object _) => '');
    await _subscribe();
  }

  @override
  Future<void> stop() async {
    _retry?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    final channel = _channel;
    _channel = null;
    _userId = null;
    _status.value = const RealtimeStatus(RealtimeState.stopped);
    if (channel != null) await _client.removeChannel(channel).catchError((Object _) => '');
  }
}
