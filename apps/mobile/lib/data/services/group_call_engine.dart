import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_audio.dart';

import 'call_engine.dart' show AudioRoute, CallMediaState;

/// Lot 9.4 — liaison d'un appel de groupe (ADR-052) : UNE liaison WebRTC vers le relais
/// Cloudflare (SFU). Ma voix (et mon image) y partent une seule fois ; les pistes des autres
/// arrivent par la même liaison, chacune à son emplacement (« mid »). Le relais propose les
/// changements (offre) ; on lui répond. Interface : remplacée dans les tests.
typedef PublishedTrack = ({String mid, String kind});

abstract interface class GroupCallEngine {
  /// Prépare la liaison (sans micro ni caméra : voir [publishOffer]).
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(CallMediaState state) onState,
    void Function()? onRemoteChanged,
    void Function()? onAudioDevicesChanged,
    void Function(bool weak)? onQuality,
  });

  /// Places de ma voix ([audio]) et de mon image ([video], caméra allumée) dans la liaison :
  /// description à envoyer au relais et emplacements à publier.
  Future<({String sdp, List<PublishedTrack> tracks})> publishOffer({
    bool audio = true,
    bool video = false,
    bool front = true,
  });

  /// Réponse du relais à [publishOffer].
  Future<void> setAnswer(String sdp);

  /// Offre du relais (nouvelles pistes à recevoir) : renvoie ma réponse.
  Future<String> answerOffer(String sdp);

  /// Image déjà publiée : allumer ou couper la caméra sans nouvelle négociation.
  bool get videoPublished;
  Future<void> setCamera(bool on, {bool front = true});
  Future<void> switchCamera();

  /// Données mobiles ou Mode éco : image réduite.
  Future<void> setEconomy(bool economy);
  Future<void> setMuted(bool muted);
  Future<void> setSpeaker(bool on);
  Future<List<AudioRoute>> audioRoutes();
  Future<void> selectAudioRoute(AudioRoute route);

  Widget localView({bool mirror = true});

  /// Image reçue à cet emplacement (null tant qu'elle n'est pas arrivée).
  Widget? remoteView(String mid);

  Future<int> trafficBytes();

  /// Lot 9.3c : niveaux moyens du son reçu (tous les participants) et envoyé.
  Future<CallAudioLevels> audioLevels();
  Future<void> close();
}

class WebRtcGroupCallEngine implements GroupCallEngine {
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  MediaStream? _cam;
  RTCRtpSender? _videoSender;
  bool _economy = true;
  Timer? _quality;
  int _lost = 0;
  int _received = 0;
  final RTCVideoRenderer _localR = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remote = {};
  void Function()? _onRemoteChanged;

  RTCPeerConnection get _peer => _pc ?? (throw StateError('liaison fermée'));

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(CallMediaState state) onState,
    void Function()? onRemoteChanged,
    void Function()? onAudioDevicesChanged,
    void Function(bool weak)? onQuality,
  }) async {
    // Lot 9.3c : traitement du son de la bibliothèque, avant tout autre usage.
    await prepareCallAudio();
    await _localR.initialize();
    _onRemoteChanged = onRemoteChanged;
    // Lot 9.3 : mode « communication » (touches de volume = son de l'appel).
    await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication);
    navigator.mediaDevices.ondevicechange = (_) => onAudioDevicesChanged?.call();
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    _pc = pc;
    pc.onTrack = (e) {
      if (e.track.kind != 'video') return;
      unawaited(_attachVideo(e));
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
    if (onQuality != null) {
      _quality = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          onQuality(await _weak());
        } on Object {
          // Statistiques indisponibles.
        }
      });
    }
  }

  Future<void> _attachVideo(RTCTrackEvent e) async {
    var mid = e.transceiver?.mid;
    if (mid == null || mid.isEmpty) {
      for (final t in await _peer.getTransceivers()) {
        if (t.receiver.track?.id == e.track.id) mid = t.mid;
      }
    }
    if (mid == null || mid.isEmpty) return;
    final r = _remote[mid] ?? RTCVideoRenderer();
    if (!_remote.containsKey(mid)) {
      await r.initialize();
      _remote[mid] = r;
    }
    if (e.streams.isNotEmpty) {
      r.srcObject = e.streams.first;
    } else {
      final s = await createLocalMediaStream('privio-groupe-$mid');
      await s.addTrack(e.track);
      r.srcObject = s;
    }
    _onRemoteChanged?.call();
  }

  /// Connexion faible : aller-retour > 600 ms ou plus de 8 % de paquets audio perdus.
  Future<bool> _weak() async {
    final pc = _pc;
    if (pc == null) return false;
    var rtt = 0.0;
    var lost = 0;
    var received = 0;
    for (final r in await pc.getStats()) {
      final v = r.values;
      if (r.type == 'candidate-pair' && v['state'] == 'succeeded' && v['nominated'] == true) {
        rtt = (v['currentRoundTripTime'] as num?)?.toDouble() ?? rtt;
      }
      if (r.type == 'inbound-rtp' && v['kind'] == 'audio') {
        lost += (v['packetsLost'] as num?)?.toInt() ?? 0;
        received += (v['packetsReceived'] as num?)?.toInt() ?? 0;
      }
    }
    final dLost = lost - _lost;
    final dTotal = dLost + received - _received;
    _lost = lost;
    _received = received;
    return rtt > 0.6 || (dTotal > 20 && dLost / dTotal > 0.08);
  }

  Future<MediaStream> _camera(bool front) async =>
      _cam ??= await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': front ? 'user' : 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 20, 'max': 24},
        },
      });

  @override
  Future<({String sdp, List<PublishedTrack> tracks})> publishOffer({
    bool audio = true,
    bool video = false,
    bool front = true,
  }) async {
    final pc = _peer;
    final ids = <String, String>{};
    if (audio && _mic == null) {
      final mic = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
      _mic = mic;
      final track = mic.getAudioTracks().first;
      await pc.addTransceiver(
        track: track,
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [mic]),
      );
      ids[track.id!] = 'audio';
    }
    if (video && _videoSender == null) {
      final cam = await _camera(front);
      final track = cam.getVideoTracks().first;
      final t = await pc.addTransceiver(
        track: track,
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [cam]),
      );
      _videoSender = t.sender;
      _localR.srcObject = cam;
      ids[track.id!] = 'video';
    }
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    final tracks = <PublishedTrack>[];
    for (final t in await pc.getTransceivers()) {
      final kind = ids[t.sender.track?.id];
      if (kind != null && t.mid.isNotEmpty) tracks.add((mid: t.mid, kind: kind));
    }
    await _applyQuality();
    return (sdp: offer.sdp!, tracks: tracks);
  }

  @override
  Future<void> setAnswer(String sdp) =>
      _peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));

  @override
  Future<String> answerOffer(String sdp) async {
    await _peer.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await _peer.createAnswer();
    await _peer.setLocalDescription(answer);
    return answer.sdp!;
  }

  @override
  bool get videoPublished => _videoSender != null;

  @override
  Future<void> setCamera(bool on, {bool front = true}) async {
    final sender = _videoSender;
    if (sender == null) return;
    if (on) {
      final cam = await _camera(front);
      await sender.replaceTrack(cam.getVideoTracks().first);
      _localR.srcObject = cam;
      await _applyQuality();
    } else {
      await sender.replaceTrack(null);
      _localR.srcObject = null;
      await _stopCamera();
    }
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

  /// À plusieurs, l'image est plus petite qu'à deux : ≈ 240p à 150 kbit/s en données
  /// mobiles, ≈ 480p à 450 kbit/s en Wi-Fi.
  Future<void> _applyQuality() async {
    final sender = _videoSender;
    if (sender == null || _cam == null) return;
    try {
      final p = sender.parameters;
      final enc = (p.encodings == null || p.encodings!.isEmpty) ? [RTCRtpEncoding()] : p.encodings!;
      for (final e in enc) {
        e
          ..active = true
          ..maxBitrate = _economy ? 150000 : 450000
          ..scaleResolutionDownBy = _economy ? 2.0 : 1.0
          ..maxFramerate = _economy ? 15 : 20;
      }
      p.encodings = enc;
      await sender.setParameters(p);
    } on Object {
      // Réglage refusé : WebRTC ajuste seul.
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

  @override
  Widget localView({bool mirror = true}) => RTCVideoView(
    _localR,
    mirror: mirror,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );

  @override
  Widget? remoteView(String mid) {
    final r = _remote[mid];
    if (r == null || r.srcObject == null) return null;
    return RTCVideoView(r, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }

  @override
  Future<CallAudioLevels> audioLevels() async {
    final pc = _pc;
    if (pc == null) return CallAudioLevels.unknown;
    return audioLevelsFromStats(await pc.getStats());
  }

  @override
  Future<int> trafficBytes() async {
    final pc = _pc;
    if (pc == null) return 0;
    var total = 0;
    for (final r in await pc.getStats()) {
      if (r.type != 'transport') continue;
      total += ((r.values['bytesSent'] as num?) ?? 0).toInt();
      total += ((r.values['bytesReceived'] as num?) ?? 0).toInt();
    }
    return total;
  }

  @override
  Future<void> close() async {
    _quality?.cancel();
    _quality = null;
    navigator.mediaDevices.ondevicechange = null;
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    _mic = null;
    await _stopCamera();
    _videoSender = null;
    _localR.srcObject = null;
    final renderers = [_localR, ..._remote.values];
    for (final r in _remote.values) {
      r.srcObject = null;
    }
    _remote.clear();
    // Images libérées après la fermeture de l'écran d'appel.
    Timer(const Duration(seconds: 5), () {
      for (final r in renderers) {
        unawaited(r.dispose());
      }
    });
    await _pc?.close();
    _pc = null;
  }
}
