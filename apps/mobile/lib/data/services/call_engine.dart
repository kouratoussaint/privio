import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
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
    void Function(bool on)? onPeerCamera,
  });

  /// Lot 9.2 : caméra allumée ou coupée à tout moment, sans nouvelle négociation (la place
  /// de la vidéo est prévue dès le début de chaque appel). Le correspondant en est averti
  /// par la liaison elle-même ([open] → `onPeerCamera`).
  Future<void> setCamera(bool on, {bool front = true});
  Future<void> switchCamera();

  /// Données mobiles : image réduite (≈ 360p, 350 kbit/s) ; Wi-Fi : jusqu'à 720p.
  Future<void> setEconomy(bool economy);

  /// Image de la caméra (miroir pour la caméra avant) et image du correspondant.
  Widget localView({bool mirror = true});
  Widget remoteView();

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
  // Lot 9.2 : vidéo.
  RTCRtpTransceiver? _video;
  RTCDataChannel? _channel;
  MediaStream? _cam;
  bool _economy = true;
  final RTCVideoRenderer _localR = RTCVideoRenderer();
  final RTCVideoRenderer _remoteR = RTCVideoRenderer();
  void Function(bool on)? _onPeerCamera;

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
    void Function(bool weak)? onQuality,
    void Function(bool on)? onPeerCamera,
  }) async {
    await _localR.initialize();
    await _remoteR.initialize();
    _onPeerCamera = onPeerCamera;
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
    // Lot 9.2 : canal de la liaison (négocié des deux côtés, sans signal en plus) qui
    // annonce caméra allumée / coupée.
    final channel = await pc.createDataChannel(
      'privio',
      RTCDataChannelInit()
        ..negotiated = true
        ..id = 0,
    );
    _channel = channel;
    channel.onDataChannelState = (st) {
      if (st == RTCDataChannelState.RTCDataChannelOpen) unawaited(_announce());
    };
    channel.onMessage = (m) {
      try {
        final j = jsonDecode(m.text);
        if (j is Map && j['cam'] is bool) _onPeerCamera?.call(j['cam'] as bool);
      } on Object {
        // Message inconnu : ignoré.
      }
    };
    pc.onTrack = (e) {
      if (e.track.kind != 'video') return;
      unawaited(() async {
        if (e.streams.isNotEmpty) {
          _remoteR.srcObject = e.streams.first;
        } else {
          final s = await createLocalMediaStream('privio-distant');
          await s.addTrack(e.track);
          _remoteR.srcObject = s;
        }
      }());
    };
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

  Future<void> _announce() async {
    final ch = _channel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      await ch.send(RTCDataChannelMessage(jsonEncode({'cam': _cam != null})));
    } on Object {
      // Liaison en cours de reconnexion : annoncé à la réouverture.
    }
  }

  @override
  Future<void> setCamera(bool on, {bool front = true}) async {
    if (on) {
      _cam ??= await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': front ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 24, 'max': 30},
        },
      });
      final track = _cam!.getVideoTracks().first;
      await _video?.sender.replaceTrack(track);
      _localR.srcObject = _cam;
      await _applyQuality();
    } else {
      await _video?.sender.replaceTrack(null);
      _localR.srcObject = null;
      await _stopCamera();
    }
    await _announce();
  }

  Future<void> _stopCamera() async {
    for (final t in _cam?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _cam?.dispose();
    _cam = null;
  }

  @override
  Future<void> switchCamera() async {
    final track = _cam?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  @override
  Future<void> setEconomy(bool economy) async {
    _economy = economy;
    await _applyQuality();
  }

  Future<void> _applyQuality() async {
    final sender = _video?.sender;
    if (sender == null || _cam == null) return;
    try {
      final p = sender.parameters;
      final enc = (p.encodings == null || p.encodings!.isEmpty) ? [RTCRtpEncoding()] : p.encodings!;
      for (final e in enc) {
        e
          ..active = true
          ..maxBitrate = _economy ? 350000 : 1500000
          ..scaleResolutionDownBy = _economy ? 2.0 : 1.0
          ..maxFramerate = _economy ? 20 : 30;
      }
      p.encodings = enc;
      await sender.setParameters(p);
    } on Object {
      // Réglage refusé par le téléphone : WebRTC ajuste seul selon la connexion.
    }
  }

  /// Place de la vidéo dans la liaison (appelant : avant l'offre).
  Future<void> _ensureVideo() async {
    if (_video != null) return;
    _video = await _peer.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
  }

  /// Appelé : la place de la vidéo vient de l'offre ; on l'ouvre dans les deux sens.
  Future<void> _adoptVideo() async {
    if (_video != null) return;
    for (final t in await _peer.getTransceivers()) {
      if (t.receiver.track?.kind == 'video') {
        await t.setDirection(TransceiverDirection.SendRecv);
        _video = t;
        if (_cam != null) {
          await t.sender.replaceTrack(_cam!.getVideoTracks().first);
          await _applyQuality();
        }
        return;
      }
    }
  }

  @override
  Widget localView({bool mirror = true}) => RTCVideoView(
    _localR,
    mirror: mirror,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );

  @override
  Widget remoteView() =>
      RTCVideoView(_remoteR, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);

  @override
  Future<Map<String, dynamic>> restartIce() async {
    final offer = await _peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
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
    await _ensureVideo();
    final offer = await _peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
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
    await _adoptVideo();
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
    await _stopCamera();
    _localR.srcObject = null;
    _remoteR.srcObject = null;
    // Images libérées après la fermeture de l'écran d'appel (« Appel terminé » affiché).
    Timer(const Duration(seconds: 5), () {
      unawaited(_localR.dispose());
      unawaited(_remoteR.dispose());
    });
    await _channel?.close();
    _channel = null;
    _video = null;
    await _pc?.close();
    _pc = null;
    _pending.clear();
    _remoteSet = false;
  }
}
