import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/call.dart';

/// Lot 9.1a — mise en relation des appels (la voix ne passe jamais par le serveur).
abstract interface class CallsApi {
  /// [kind] : « audio » ou « video » (lot 9.2).
  Future<CallInfo> startCall(String conversationId, {String kind = 'audio'});
  Future<CallInfo> answer(String callId);
  Future<CallInfo> decline(String callId);
  Future<CallInfo> end(String callId, {String reason = 'hangup'});
  Future<void> signal(String callId, String kind, Map<String, dynamic> payload);
  Future<CallSnapshot> state(String callId, {int after = 0});

  /// Appel encore ouvert qui me concerne (ouverture de l'application).
  Future<CallInfo?> openCall();

  /// Serveurs réseau (STUN, et relais TURN s'il est configuré), le temps d'un appel.
  Future<List<Map<String, dynamic>>> iceServers();

  /// Réglage « Recevoir des appels » (activé par défaut).
  Future<bool> acceptCalls();
  Future<bool> setAcceptCalls(bool on);

  /// Lot 5.7 : fin d'un appel décroché — relais ou non, octets échangés (santé du service).
  Future<void> reportQuality(String callId, {required bool relayed, required int bytes});
}

class SupabaseCallsApi implements CallsApi {
  SupabaseCallsApi(this._client);

  final SupabaseClient _client;

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  Future<CallInfo> _call(String fn, Map<String, dynamic> params) async =>
      CallInfo.fromJson(Map<String, dynamic>.from(await _rpc(fn, params) as Map));

  @override
  Future<CallInfo> startCall(String conversationId, {String kind = 'audio'}) =>
      _call('start_call', {'p_conversation_id': conversationId, 'p_kind': kind});

  @override
  Future<CallInfo> answer(String callId) => _call('answer_call', {'p_call_id': callId});

  @override
  Future<CallInfo> decline(String callId) => _call('decline_call', {'p_call_id': callId});

  @override
  Future<CallInfo> end(String callId, {String reason = 'hangup'}) =>
      _call('end_call', {'p_call_id': callId, 'p_reason': reason});

  @override
  Future<void> signal(String callId, String kind, Map<String, dynamic> payload) =>
      _rpc('send_call_signal', {'p_call_id': callId, 'p_kind': kind, 'p_payload': payload});

  @override
  Future<CallSnapshot> state(String callId, {int after = 0}) async => CallSnapshot.fromJson(
    Map<String, dynamic>.from(
      await _rpc('call_state', {'p_call_id': callId, 'p_after': after}) as Map,
    ),
  );

  @override
  Future<CallInfo?> openCall() async {
    final r = await _rpc('my_open_call');
    return r == null ? null : CallInfo.fromJson(Map<String, dynamic>.from(r as Map));
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async {
    try {
      final res = await _client.functions.invoke('call-ice', method: HttpMethod.post);
      final list = (res.data as Map)['iceServers'] as List<dynamic>;
      return [for (final s in list) Map<String, dynamic>.from(s as Map)];
    } on Object {
      // Sans réponse : le STUN public suffit souvent en Wi-Fi.
      return const [
        {
          'urls': ['stun:stun.cloudflare.com:3478'],
        },
      ];
    }
  }

  @override
  Future<bool> acceptCalls() async => await _rpc('get_accept_calls') as bool;

  @override
  Future<bool> setAcceptCalls(bool on) async =>
      await _rpc('set_accept_calls', {'p_on': on}) as bool;

  @override
  Future<void> reportQuality(String callId, {required bool relayed, required int bytes}) =>
      _rpc('report_call_quality', {'p_call_id': callId, 'p_relayed': relayed, 'p_bytes': bytes});
}
