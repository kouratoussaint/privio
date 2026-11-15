import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Lot 9.1a — liaison audio d'un appel (WebRTC). Interface : remplacée dans les tests.
enum CallMediaState { connecting, connected, reconnecting, failed }

abstract interface class CallEngine {
  /// Ouvre le micro et prépare la liaison. [onCandidate] : candidat réseau local à envoyer
  /// au correspondant ; [onState] : état de la liaison.
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
  });

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

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
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
  }

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
