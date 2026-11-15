import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Lot 9.1a — liaison audio d'un appel (WebRTC). Interface : remplacée dans les tests.
enum CallMediaState { connecting, connected, reconnecting, failed }

/// Lot 9.1b — sortie du son pendant un appel.
enum AudioRoute { earpiece, speaker, bluetooth, wired }

abstract interface class CallEngine {
  /// Ouvre le micro et prépare la liaison. [onCandidate] : candidat réseau local à envoyer
  /// au correspondant ; [onState] : état de la liaison.
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
    void Function(bool weak)? onQuality,
  });

  /// Lot 9.1b : nouvelle offre après un changement de réseau (Wi-Fi ↔ données). L'offre
  /// suivante du correspondant passe par [acceptOffer], sa réponse par [setAnswer].
  Future<Map<String, dynamic>> restartIce();

  /// Sorties disponibles (écouteur et haut-parleur toujours ; Bluetooth, casque filaire).
  Future<List<AudioRoute>> audioRoutes();
  Future<void> selectAudioRoute(AudioRoute route);

  /// Appelant : description de session à envoyer.
  Future<Map<String, dynamic>> createOffer();

  /// Appelé : applique l'offre reçue et renvoie la réponse à envoyer.
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer);

  /// Appelant : applique la réponse reçue.
  Future<void> setAnswer(Map<String, dynamic> answer);

  Future<void> addCandidate(Map<String, dynamic> candidate);
  Future<void> setMuted(bool muted);
  Future<void> setSpeaker(bool on);
  Future<void> close();
}

class WebRtcCallEngine implements CallEngine {
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pending = [];
  Timer? _quality;
  int _lost = 0;
  int _received = 0;

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
    void Function(bool weak)? onQuality,
  }) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    _mic = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': false,
    });
    for (final t in _mic!.getAudioTracks()) {
      await pc.addTrack(t, _mic!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      onCandidate({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onIceConnectionState = (s) {
      switch (s) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          onState(CallMediaState.connected);
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          onState(CallMediaState.reconnecting);
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          onState(CallMediaState.failed);
        default:
          break;
      }
    };
    // Appel audio : écouteur par défaut (haut-parleur sur demande).
    await Helper.setSpeakerphoneOn(false);
    if (onQuality != null) {
      _quality = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          onQuality(await _weak());
        } on Object {
          // Statistiques indisponibles : pas d'indication.
        }
      });
    }
  }

  /// Connexion faible : aller-retour > 600 ms ou plus de 8 % de paquets perdus (3 s).
  Future<bool> _weak() async {
    final pc = _pc;
    if (pc == null) return false;
    var rtt = 0.0;
    var lost = _lost;
    var received = _received;
    for (final r in await pc.getStats()) {
      final v = r.values;
      if (r.type == 'candidate-pair' && v['state'] == 'succeeded' && v['nominated'] == true) {
        rtt = (v['currentRoundTripTime'] as num?)?.toDouble() ?? rtt;
      }
      if (r.type == 'inbound-rtp' && v['kind'] == 'audio') {
        lost = (v['packetsLost'] as num?)?.toInt() ?? lost;
        received = (v['packetsReceived'] as num?)?.toInt() ?? received;
      }
    }
    final dLost = lost - _lost;
    final dTotal = dLost + received - _received;
    _lost = lost;
    _received = received;
    return rtt > 0.6 || (dTotal > 20 && dLost / dTotal > 0.08);
  }

  @override
  Future<Map<String, dynamic>> restartIce() async {
    final offer = await _peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
      'iceRestart': true,
    });
    await _peer.setLocalDescription(offer);
    return _desc(offer);
  }

  static const _ids = {
    AudioRoute.earpiece: 'earpiece',
    AudioRoute.speaker: 'speaker',
    AudioRoute.bluetooth: 'bluetooth',
    AudioRoute.wired: 'wired-headset',
  };

  @override
  Future<List<AudioRoute>> audioRoutes() async {
    final ids = (await Helper.audiooutputs).map((d) => d.deviceId).toSet();
    return [
      for (final r in AudioRoute.values)
        if (r == AudioRoute.earpiece || r == AudioRoute.speaker || ids.contains(_ids[r])) r,
    ];
  }

  @override
  Future<void> selectAudioRoute(AudioRoute route) => Helper.selectAudioOutput(_ids[route]!);

  RTCPeerConnection get _peer => _pc ?? (throw StateError('liaison fermée'));

  Map<String, dynamic> _desc(RTCSessionDescription d) => {'sdp': d.sdp, 'type': d.type};

  Future<void> _flush() async {
    _remoteSet = true;
    for (final c in _pending) {
      await _peer.addCandidate(c);
    }
    _pending.clear();
  }

  @override
  Future<Map<String, dynamic>> createOffer() async {
    final offer = await _peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peer.setLocalDescription(offer);
    return _desc(offer);
  }

  @override
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer) async {
    await _peer.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    await _flush();
    final answer = await _peer.createAnswer({'offerToReceiveAudio': true});
    await _peer.setLocalDescription(answer);
    return _desc(answer);
  }

  @override
  Future<void> setAnswer(Map<String, dynamic> answer) async {
    await _peer.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?),
    );
    await _flush();
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> c) async {
    final candidate = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      (c['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_remoteSet) {
      await _peer.addCandidate(candidate);
    } else {
      _pending.add(candidate);
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<void> close() async {
    _quality?.cancel();
    _quality = null;
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    _mic = null;
    await _pc?.close();
    _pc = null;
    _pending.clear();
    _remoteSet = false;
  }
}
