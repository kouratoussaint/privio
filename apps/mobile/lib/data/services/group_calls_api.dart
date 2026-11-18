import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/group_call.dart';

/// Lot 9.4 — appels de groupe (ADR-052) : mise en relation par la base, voix et image par
/// le relais Cloudflare (fonction call-sfu, qui garde la clé du relais).
abstract interface class GroupCallsApi {
  /// Lance un appel dans le groupe (ou rejoint celui qui est déjà en cours).
  Future<GroupCallInfo> start(String conversationId, {String kind = 'audio'});
  Future<GroupCallInfo> join(String callId);
  Future<GroupCallInfo> decline(String callId);
  Future<GroupCallInfo> leave(String callId);

  /// État ; pour une personne dans l'appel, sert aussi de présence.
  Future<GroupCallInfo> state(String callId);
  Future<GroupCallInfo> setMedia(String callId, {bool? camera, bool? muted});

  /// Appels en cours dans mes groupes (bandeaux « Rejoindre », sonnerie).
  Future<List<GroupCallInfo>> active();

  /// Relais : publie ma voix (et mon image). [fresh] : nouvelle liaison (nouvelle session).
  /// Renvoie la réponse du relais.
  Future<String> push(
    String callId, {
    required String sdp,
    required List<({String mid, String kind})> tracks,
    bool fresh = false,
  });

  /// Relais : demande des pistes d'autres personnes de l'appel (offre du relais).
  Future<SfuPull> pull(String callId, List<({String session, String name})> tracks);

  /// Relais : réponse à son offre.
  Future<void> answer(String callId, String sdp);

  /// Relais : arrête des pistes reçues (personne partie).
  Future<void> close(String callId, List<String> mids);
}

class SupabaseGroupCallsApi implements GroupCallsApi {
  SupabaseGroupCallsApi(this._client);

  final SupabaseClient _client;

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  Future<GroupCallInfo> _call(String fn, Map<String, dynamic> params) async =>
      GroupCallInfo.fromJson(Map<String, dynamic>.from(await _rpc(fn, params) as Map));

  Future<Map<String, dynamic>> _sfu(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('call-sfu', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<GroupCallInfo> start(String conversationId, {String kind = 'audio'}) =>
      _call('start_group_call', {'p_conversation_id': conversationId, 'p_kind': kind});

  @override
  Future<GroupCallInfo> join(String callId) => _call('join_group_call', {'p_call_id': callId});

  @override
  Future<GroupCallInfo> decline(String callId) =>
      _call('decline_group_call', {'p_call_id': callId});

  @override
  Future<GroupCallInfo> leave(String callId) => _call('leave_group_call', {'p_call_id': callId});

  @override
  Future<GroupCallInfo> state(String callId) => _call('group_call_state', {'p_call_id': callId});

  @override
  Future<GroupCallInfo> setMedia(String callId, {bool? camera, bool? muted}) =>
      _call('set_group_call_media', {'p_call_id': callId, 'p_camera': camera, 'p_muted': muted});

  @override
  Future<List<GroupCallInfo>> active() async {
    final list = await _rpc('my_group_calls') as List<dynamic>? ?? const [];
    return [for (final c in list) GroupCallInfo.fromJson(Map<String, dynamic>.from(c as Map))];
  }

  @override
  Future<String> push(
    String callId, {
    required String sdp,
    required List<({String mid, String kind})> tracks,
    bool fresh = false,
  }) async {
    final r = await _sfu({
      'action': 'push',
      'call_id': callId,
      'sdp': sdp,
      'fresh': fresh,
      'tracks': [
        for (final t in tracks) {'mid': t.mid, 'kind': t.kind},
      ],
    });
    return r['sdp'] as String;
  }

  @override
  Future<SfuPull> pull(String callId, List<({String session, String name})> tracks) async =>
      SfuPull.fromJson(
        await _sfu({
          'action': 'pull',
          'call_id': callId,
          'tracks': [
            for (final t in tracks) {'session': t.session, 'name': t.name},
          ],
        }),
      );

  @override
  Future<void> answer(String callId, String sdp) =>
      _sfu({'action': 'answer', 'call_id': callId, 'sdp': sdp});

  @override
  Future<void> close(String callId, List<String> mids) =>
      _sfu({'action': 'close', 'call_id': callId, 'mids': mids});
}
