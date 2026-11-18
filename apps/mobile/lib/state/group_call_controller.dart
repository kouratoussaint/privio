import 'dart:async';

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../data/services/audio/voice_recorder.dart' show MicPermission;
import '../data/services/call_engine.dart' show AudioRoute, CallMediaState;
import '../data/services/call_system.dart';
import '../data/services/call_tones.dart';
import '../data/services/device_services.dart' show NetKind;
import '../data/services/group_call_engine.dart';
import '../data/services/group_calls_api.dart';
import '../domain/models/group_call.dart';
import 'call_controller.dart';
import 'data_providers.dart';
import 'messaging_providers.dart';
import 'providers.dart';

/// Lot 9.4 — appels de groupe audio et vidéo (ADR-052). Mise en relation par la base (qui
/// est dans l'appel, sessions et pistes au relais), voix et image par le relais Cloudflare :
/// une seule liaison vers le relais, qui renvoie les pistes des autres personnes.
/// 8 personnes au plus ; un seul appel à la fois (appel à deux ou appel de groupe).

final groupCallsApiProvider = Provider<GroupCallsApi>(
  (ref) => throw UnimplementedError('groupCallsApiProvider doit être surchargé'),
);
final groupCallEngineFactoryProvider = Provider<GroupCallEngine Function()>(
  (ref) => WebRtcGroupCallEngine.new,
);

// ---------------------------------------------------------------------------
// Appels en cours dans mes groupes (bandeau « Rejoindre », sonnerie)
// ---------------------------------------------------------------------------
final activeGroupCallsProvider = NotifierProvider<ActiveGroupCalls, Map<String, GroupCallInfo>>(
  ActiveGroupCalls.new,
);

/// Appel de groupe en cours dans une discussion (null : aucun).
final groupCallInProvider = Provider.family<GroupCallInfo?, String>(
  (ref, conversationId) => ref.watch(activeGroupCallsProvider)[conversationId],
);

class ActiveGroupCalls extends Notifier<Map<String, GroupCallInfo>> {
  bool _loading = false;
  bool _again = false;

  @override
  Map<String, GroupCallInfo> build() {
    final user = ref.watch(currentUserIdProvider);
    if (user == null) return const {};
    ref.listen(realtimeSignalsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s.event == 'group_call' || s.event == 'resume' || s.event == 'reconnected') {
        unawaited(refresh());
      }
    });
    Future.microtask(refresh);
    return const {};
  }

  /// Relit les appels en cours (une lecture à la fois ; une demande pendant la lecture la
  /// relance à la fin).
  Future<void> refresh() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        try {
          final list = await ref.read(groupCallsApiProvider).active();
          state = {
            for (final c in list)
              if (c.active) c.conversationId: c,
          };
        } on Object {
          // Hors connexion : on garde la liste précédente.
        }
      } while (_again);
    } finally {
      _loading = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Mon appel de groupe
// ---------------------------------------------------------------------------
enum GroupCallPhase { ringing, joining, connected, reconnecting, ended }

class GroupCallState {
  const GroupCallState({
    required this.info,
    required this.phase,
    this.muted = false,
    this.camera = false,
    this.frontCamera = true,
    this.cameraDenied = false,
    this.route = AudioRoute.earpiece,
    this.weak = false,
    this.connectedAt,
    this.minimized = false,
    this.endStatus,
    this.media = 0,
  });

  final GroupCallInfo info;
  final GroupCallPhase phase;
  final bool muted;
  final bool camera;
  final bool frontCamera;
  final bool cameraDenied;
  final AudioRoute route;
  final bool weak;
  final DateTime? connectedAt;
  final bool minimized;

  /// 'ended', 'failed', 'full', 'unavailable'.
  final String? endStatus;

  /// Change quand une image reçue arrive ou s'en va (l'écran se redessine).
  final int media;

  bool get video => info.video;
  bool get live => phase != GroupCallPhase.ended;
  bool get speaker => route == AudioRoute.speaker;

  GroupCallState copyWith({
    GroupCallInfo? info,
    GroupCallPhase? phase,
    bool? muted,
    bool? camera,
    bool? frontCamera,
    bool? cameraDenied,
    AudioRoute? route,
    bool? weak,
    DateTime? connectedAt,
    bool? minimized,
    String? endStatus,
    int? media,
  }) => GroupCallState(
    info: info ?? this.info,
    phase: phase ?? this.phase,
    muted: muted ?? this.muted,
    camera: camera ?? this.camera,
    frontCamera: frontCamera ?? this.frontCamera,
    cameraDenied: cameraDenied ?? this.cameraDenied,
    route: route ?? this.route,
    weak: weak ?? this.weak,
    connectedAt: connectedAt ?? this.connectedAt,
    minimized: minimized ?? this.minimized,
    endStatus: endStatus ?? this.endStatus,
    media: media ?? this.media,
  );
}

/// Piste reçue : de qui, quel type, à quel emplacement de la liaison.
typedef _Pulled = ({String mid, String userId, String kind});

final groupCallControllerProvider = NotifierProvider<GroupCallController, GroupCallState?>(
  GroupCallController.new,
);

class GroupCallController extends Notifier<GroupCallState?> {
  GroupCallEngine? _engine;
  Timer? _poll;
  Timer? _linger;
  Timer? _giveUp;
  Timer? _rebuild;
  Timer? _deniedClear;
  bool _polling = false;
  Future<void> _queue = Future.value();

  /// Pistes reçues, par « session/nom ».
  final Map<String, _Pulled> _pulled = {};

  /// Appels qui ont sonné ici et ont été refusés ou laissés (ne sonnent plus).
  final Set<String> _dismissed = {};
  bool _systemRinging = false;
  bool _overLock = false;
  bool _callAudio = false;
  bool _proximity = false;
  Set<AudioRoute> _knownRoutes = const {};

  GroupCallsApi get _api => ref.read(groupCallsApiProvider);
  late CallTones _tones;
  late CallSystem _system;
  CallTimings get _t => ref.read(callTimingsProvider);

  @override
  GroupCallState? build() {
    _tones = ref.read(callTonesProvider);
    _system = ref.read(callSystemProvider);
    ref.listen(realtimeSignalsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s.event == 'group_call' && s.callId != null && s.callId == state?.info.id) {
        unawaited(_pollNow());
      }
      if (s.event == 'resume') _onResume();
    });
    // Sonnerie : un appel de mes groupes me fait sonner.
    ref.listen(activeGroupCallsProvider, (_, next) => _onActive(next));
    final events = _system.events.where((e) => e.group).listen(_onSystem);
    final net = ref.read(networkMonitorProvider).changes().listen(_onNetwork);
    listenSelf(_syncSystem);
    ref.onDispose(() {
      unawaited(events.cancel());
      unawaited(net.cancel());
      _linger?.cancel();
      _stopMedia();
    });
    return null;
  }

  bool get busy => state != null && state!.phase != GroupCallPhase.ended;

  /// En appel à deux : l'appel de groupe ne sonne pas, on ne peut pas en lancer.
  bool get _otherBusy => ref.read(callControllerProvider.notifier).busy;

  String? get _me => ref.read(currentUserIdProvider);

  // ---------------------------------------------------------------------------
  // Lancer, rejoindre
  // ---------------------------------------------------------------------------
  /// Lance un appel dans le groupe (ou rejoint celui qui est déjà en cours). Lève une
  /// [AppFailure] si impossible. Appel vidéo : ma caméra est allumée dès le début.
  Future<void> start(String conversationId, {String kind = 'audio'}) async {
    if (busy || _otherBusy) throw const AppFailure(FailureCode.callAlreadyActive);
    await _ensureMic();
    final info = await _api.start(conversationId, kind: kind);
    await _connect(info, video: info.video && !info.existing);
  }

  /// Rejoint un appel en cours (bandeau « Rejoindre »).
  Future<void> join(String callId) async {
    if (state?.info.id == callId && state?.phase == GroupCallPhase.ringing) return accept();
    if (busy || _otherBusy) throw const AppFailure(FailureCode.callAlreadyActive);
    await _ensureMic();
    final info = await _api.join(callId);
    await _connect(info, video: false);
  }

  /// Appel décroché depuis l'écran d'appel du téléphone (Privio fermé), ou appel de groupe
  /// qui sonne déjà à l'ouverture.
  Future<void> checkOpen() async {
    if (busy) return;
    try {
      final accepted = await _system.acceptedGroupCall();
      await ref.read(activeGroupCallsProvider.notifier).refresh();
      if (accepted == null || busy) return;
      final info = await _api.state(accepted);
      if (!info.active || info.joinedMe) {
        await _system.end(accepted);
        return;
      }
      _incoming(info);
      await accept();
    } on Object {
      // Hors connexion : le prochain retour réessaiera.
    }
  }

  void _onActive(Map<String, GroupCallInfo> calls) {
    if (busy || _otherBusy) return;
    for (final c in calls.values) {
      if (c.ringingMe && !_dismissed.contains(c.id)) {
        _incoming(c);
        return;
      }
    }
  }

  void _incoming(GroupCallInfo info) {
    _linger?.cancel();
    state = GroupCallState(info: info, phase: GroupCallPhase.ringing);
    if (ref.read(appForegroundProvider)()) {
      _systemRinging = false;
      unawaited(_system.hideIncoming(info.id));
      unawaited(_tones.ring());
    } else {
      _systemRinging = true;
      unawaited(_system.showIncoming(info.id, video: info.video, group: true));
    }
    _startPolling();
  }

  void _onResume() {
    final s = state;
    if (s != null && s.phase == GroupCallPhase.ringing && _systemRinging) {
      _systemRinging = false;
      unawaited(_system.hideIncoming(s.info.id));
      unawaited(_tones.ring());
    }
  }

  Future<void> _onSystem(CallSystemEvent e) async {
    final s = state;
    final same = s != null && s.info.id == e.callId;
    switch (e.action) {
      case CallSystemAction.accept:
        if (same && s.phase == GroupCallPhase.ringing) {
          await accept();
        } else if (!busy) {
          try {
            final info = await _api.state(e.callId);
            if (info.active && !busy) {
              _incoming(info);
              await accept();
            }
          } on Object {
            await _system.end(e.callId);
          }
        }
      case CallSystemAction.decline:
        if (same && s.phase == GroupCallPhase.ringing) await decline();
      case CallSystemAction.end:
        if (same && s.live && s.phase != GroupCallPhase.ringing) await hangUp();
    }
  }

  Future<void> accept() async {
    final s = state;
    if (s == null || s.phase != GroupCallPhase.ringing) return;
    // Sonnerie traitée : elle ne reprend pas, même si rejoindre échoue (appel complet).
    _dismissed.add(s.info.id);
    _systemRinging = false;
    unawaited(_tones.stop());
    try {
      await _ensureMic();
    } on AppFailure {
      await decline();
      rethrow;
    }
    state = s.copyWith(phase: GroupCallPhase.joining);
    final GroupCallInfo info;
    try {
      info = await _api.join(s.info.id);
    } on AppFailure catch (e) {
      _finish(e.code == FailureCode.groupCallFull ? 'full' : 'failed');
      return;
    } on Object {
      _finish('failed');
      return;
    }
    await _connect(info, video: false);
  }

  Future<void> decline() async {
    final s = state;
    if (s == null || s.phase != GroupCallPhase.ringing) return;
    _dismissed.add(s.info.id);
    _systemRinging = false;
    unawaited(_tones.stop());
    _poll?.cancel();
    state = null;
    try {
      await _api.decline(s.info.id);
    } on Object {
      // La sonnerie s'arrête d'elle-même au bout de 45 s.
    }
  }

  Future<void> _connect(GroupCallInfo info, {required bool video}) async {
    final prev = state;
    state = GroupCallState(
      info: info,
      phase: GroupCallPhase.joining,
      route: prev?.route ?? AudioRoute.earpiece,
    );
    await _ensureNearby();
    try {
      await _openEngine();
      var camera = false;
      if (video) camera = await _cameraAllowed();
      await _enqueue(() => _publish(fresh: true, video: camera));
      if (camera) state = state?.copyWith(camera: true);
    } on AppFailure catch (e) {
      await hangUp(reason: e.code == FailureCode.groupCallUnavailable ? 'unavailable' : 'failed');
      return;
    } on Object {
      await hangUp(reason: 'failed');
      return;
    }
    _startPolling();
    await _applyPreferredRoute(video: info.video);
    unawaited(_pollNow());
  }

  // ---------------------------------------------------------------------------
  // Pendant l'appel
  // ---------------------------------------------------------------------------
  /// Quitter l'appel ([reason] : 'failed' ou 'unavailable' si la liaison n'a pas pu se faire).
  Future<void> hangUp({String reason = 'hangup'}) async {
    final s = state;
    if (s == null || !s.live) return;
    if (s.phase == GroupCallPhase.ringing) return decline();
    _stopMedia();
    _finish(switch (reason) {
      'failed' => 'failed',
      'unavailable' => 'unavailable',
      _ => 'ended',
    });
    try {
      await _api.leave(s.info.id);
    } on Object {
      // Sans réseau : le serveur me sort de l'appel au bout de 40 s.
    }
  }

  Future<void> toggleMute() async {
    final s = state;
    if (s == null || !s.live) return;
    await _engine?.setMuted(!s.muted);
    state = s.copyWith(muted: !s.muted);
    unawaited(_media(muted: !s.muted));
  }

  Future<void> toggleCamera() async {
    final s = state;
    final engine = _engine;
    if (s == null || engine == null || !s.live || s.phase == GroupCallPhase.ringing) return;
    if (s.camera) {
      state = s.copyWith(camera: false);
      try {
        await engine.setCamera(false);
      } on Object {
        // Déjà coupée.
      }
      unawaited(_media(camera: false));
      return;
    }
    if (!await _cameraAllowed()) return;
    try {
      if (engine.videoPublished) {
        await engine.setCamera(true, front: s.frontCamera);
      } else {
        await _enqueue(() => _publish(fresh: false, video: true));
      }
    } on Object {
      state = state?.copyWith(cameraDenied: true);
      return;
    }
    state = state?.copyWith(camera: true, cameraDenied: false);
    unawaited(_media(camera: true));
    if (state?.route == AudioRoute.earpiece) await selectRoute(AudioRoute.speaker);
  }

  Future<void> switchCamera() async {
    final s = state;
    if (s == null || !s.camera) return;
    try {
      await _engine?.switchCamera();
      state = state?.copyWith(frontCamera: !s.frontCamera);
    } on Object {
      // Une seule caméra.
    }
  }

  void setMinimized(bool value) {
    final s = state;
    if (s != null) state = s.copyWith(minimized: value);
  }

  /// Ma caméra (miroir pour la caméra avant).
  Widget? localView() => _engine?.localView(mirror: state?.frontCamera ?? true);

  /// Image d'une personne de l'appel (null : caméra coupée ou image pas encore arrivée).
  Widget? remoteView(String userId) {
    final engine = _engine;
    if (engine == null) return null;
    for (final p in _pulled.values) {
      if (p.userId == userId && p.kind == 'video') return engine.remoteView(p.mid);
    }
    return null;
  }

  Future<void> _media({bool? camera, bool? muted}) async {
    final s = state;
    if (s == null) return;
    try {
      final info = await _api.setMedia(s.info.id, camera: camera, muted: muted);
      if (state?.info.id == info.id && state!.live) state = state!.copyWith(info: info);
    } on Object {
      // Affichage seulement : corrigé au prochain état.
    }
  }

  Future<bool> _cameraAllowed() async {
    var granted = false;
    try {
      granted = await ref.read(permissionGatewayProvider).requestCamera();
    } on Object {
      granted = false;
    }
    if (!granted) {
      state = state?.copyWith(cameraDenied: true);
      _deniedClear?.cancel();
      _deniedClear = Timer(const Duration(seconds: 4), () {
        if (state?.cameraDenied == true) state = state!.copyWith(cameraDenied: false);
      });
    }
    return granted;
  }

  // ---------------------------------------------------------------------------
  // Sortie du son (comme les appels à deux, lot 9.3)
  // ---------------------------------------------------------------------------
  Future<List<AudioRoute>> audioRoutes() async {
    try {
      return await _engine?.audioRoutes() ?? const [AudioRoute.earpiece, AudioRoute.speaker];
    } on Object {
      return const [AudioRoute.earpiece, AudioRoute.speaker];
    }
  }

  static AudioRoute _preferred(List<AudioRoute> routes, {required bool video}) {
    if (routes.contains(AudioRoute.bluetooth)) return AudioRoute.bluetooth;
    if (routes.contains(AudioRoute.wired)) return AudioRoute.wired;
    return video ? AudioRoute.speaker : AudioRoute.earpiece;
  }

  Future<void> _applyPreferredRoute({required bool video}) async {
    final routes = await audioRoutes();
    _knownRoutes = routes.toSet();
    await selectRoute(_preferred(routes, video: video));
  }

  Future<void> _onAudioDevices() async {
    final s = state;
    if (s == null || !s.live) return;
    final routes = await audioRoutes();
    final added = routes.toSet().difference(_knownRoutes);
    _knownRoutes = routes.toSet();
    final now = state;
    if (now == null) return;
    final AudioRoute? next;
    if (added.contains(AudioRoute.bluetooth)) {
      next = AudioRoute.bluetooth;
    } else if (added.contains(AudioRoute.wired)) {
      next = AudioRoute.wired;
    } else if (!routes.contains(now.route)) {
      next = _preferred(routes, video: now.video || now.camera);
    } else {
      next = null;
    }
    if (next != null && next != now.route) await selectRoute(next);
  }

  Future<void> selectRoute(AudioRoute route) async {
    if (state == null) return;
    try {
      await _engine?.setSpeaker(route == AudioRoute.speaker);
      if (route != AudioRoute.speaker) await _engine?.selectAudioRoute(route);
    } on Object {
      return;
    }
    state = state?.copyWith(route: route);
  }

  // ---------------------------------------------------------------------------
  // Mécanique
  // ---------------------------------------------------------------------------
  Future<void> _ensureMic() async {
    final p = await ref.read(voiceRecorderProvider).ensurePermission();
    if (p != MicPermission.granted) throw const AppFailure(FailureCode.microphoneDenied);
  }

  Future<void> _ensureNearby() async {
    try {
      await ref.read(permissionGatewayProvider).requestNearbyDevices();
    } on Object {
      // Refusé : écouteur ou haut-parleur.
    }
  }

  /// Négociations avec le relais : une à la fois, dans l'ordre.
  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _openEngine() async {
    final engine = ref.read(groupCallEngineFactoryProvider)();
    _engine = engine;
    _pulled.clear();
    final servers = await ref.read(callsApiProvider).iceServers();
    await engine.open(
      iceServers: servers,
      onState: _onLink,
      onRemoteChanged: () {
        final s = state;
        if (s != null) state = s.copyWith(media: s.media + 1);
      },
      onAudioDevicesChanged: () => unawaited(_onAudioDevices()),
      onQuality: (weak) {
        final s = state;
        if (s != null && s.phase == GroupCallPhase.connected && s.weak != weak) {
          state = s.copyWith(weak: weak);
        }
      },
    );
    try {
      final kind = await ref.read(networkMonitorProvider).current();
      await engine.setEconomy(ref.read(ecoOnProvider) || kind != NetKind.wifi);
    } on Object {
      // Réseau inconnu : image réduite.
    }
    if (state?.muted == true) await engine.setMuted(true);
  }

  Future<void> _publish({required bool fresh, required bool video}) async {
    final s = state;
    final engine = _engine;
    if (s == null || engine == null) return;
    final offer = await engine.publishOffer(audio: true, video: video, front: s.frontCamera);
    if (offer.tracks.isEmpty && !fresh) return;
    final answer = await _api.push(s.info.id, sdp: offer.sdp, tracks: offer.tracks, fresh: fresh);
    await engine.setAnswer(answer);
  }

  void _onLink(CallMediaState m) {
    final s = state;
    if (s == null || !s.live || s.phase == GroupCallPhase.ringing) return;
    switch (m) {
      case CallMediaState.connected:
        _giveUp?.cancel();
        _giveUp = null;
        _rebuild?.cancel();
        state = s.copyWith(
          phase: GroupCallPhase.connected,
          connectedAt: s.connectedAt ?? DateTime.now(),
          weak: false,
        );
        _startPolling();
      case CallMediaState.reconnecting:
      case CallMediaState.failed:
        state = s.copyWith(phase: GroupCallPhase.reconnecting, weak: false);
        _giveUp ??= Timer(_t.giveUpAfter, () => unawaited(hangUp(reason: 'failed')));
        _rebuild?.cancel();
        _rebuild = Timer(
          m == CallMediaState.failed ? Duration.zero : const Duration(seconds: 4),
          () => unawaited(_rebuildLink()),
        );
      case CallMediaState.connecting:
        break;
    }
  }

  void _onNetwork(NetKind kind) {
    final engine = _engine;
    if (engine != null && kind != NetKind.none) {
      unawaited(
        engine
            .setEconomy(ref.read(ecoOnProvider) || kind != NetKind.wifi)
            .catchError((Object _) {}),
      );
    }
  }

  /// Liaison perdue (réseau changé ou coupé) : nouvelle liaison au relais, mêmes pistes.
  Future<void> _rebuildLink() => _enqueue(() async {
    final s = state;
    if (s == null || s.phase != GroupCallPhase.reconnecting) return;
    final old = _engine;
    _engine = null;
    if (old != null) unawaited(_closeEngine(old));
    try {
      await _openEngine();
      await _publish(fresh: true, video: s.camera);
      if (s.camera) await _engine?.setCamera(true, front: s.frontCamera);
    } on Object {
      _rebuild = Timer(const Duration(seconds: 4), () => unawaited(_rebuildLink()));
      return;
    }
    unawaited(_pollNow());
  });

  void _startPolling() {
    _poll?.cancel();
    final fast = state?.phase != GroupCallPhase.connected;
    _poll = Timer.periodic(fast ? _t.fastPoll : _t.slowPoll, (_) => unawaited(_pollNow()));
  }

  Future<void> _pollNow() async {
    final s = state;
    if (s == null || !s.live || _polling) return;
    _polling = true;
    try {
      _apply(await _api.state(s.info.id));
    } on AppFailure catch (e) {
      // Groupe quitté, appel disparu : fin.
      if (e.code == FailureCode.callNotFound) _apply(null);
    } on Object {
      // Réseau instable : au prochain tour.
    } finally {
      _polling = false;
    }
  }

  void _apply(GroupCallInfo? info) {
    final s = state;
    if (s == null || !s.live || (info != null && info.id != s.info.id)) return;
    if (s.phase == GroupCallPhase.ringing) {
      if (info == null || !info.ringingMe) {
        // Rejoint ailleurs, refusé, manqué ou appel terminé : la sonnerie s'arrête.
        _dismissed.add(s.info.id);
        _systemRinging = false;
        unawaited(_tones.stop());
        unawaited(_system.end(s.info.id));
        _poll?.cancel();
        state = null;
      } else {
        state = s.copyWith(info: info);
      }
      return;
    }
    if (info == null || !info.joinedMe) {
      _stopMedia();
      _finish('ended');
      return;
    }
    state = s.copyWith(info: info);
    unawaited(_enqueue(() => _sync(info)).catchError((Object _) {}));
  }

  /// Reçoit les pistes des personnes arrivées, arrête celles des personnes parties.
  Future<void> _sync(GroupCallInfo info) async {
    final engine = _engine;
    final me = _me;
    if (engine == null || state?.info.id != info.id) return;
    final wanted = <String, ({String session, String name, String userId, String kind})>{};
    for (final p in info.joined) {
      final session = p.session;
      if (p.userId == me || session == null) continue;
      for (final t in p.tracks.entries) {
        wanted['$session/${t.value}'] = (
          session: session,
          name: t.value,
          userId: p.userId,
          kind: t.key,
        );
      }
    }
    final gone = [
      for (final e in _pulled.entries)
        if (!wanted.containsKey(e.key)) e,
    ];
    if (gone.isNotEmpty) {
      for (final e in gone) {
        _pulled.remove(e.key);
      }
      try {
        await _api.close(info.id, [for (final e in gone) e.value.mid]);
      } on Object {
        // Le relais arrête de lui-même les pistes d'une session fermée.
      }
      _bumpMedia();
    }
    final fresh = [
      for (final e in wanted.entries)
        if (!_pulled.containsKey(e.key)) e,
    ];
    if (fresh.isEmpty) return;
    final pull = await _api.pull(info.id, [
      for (final e in fresh) (session: e.value.session, name: e.value.name),
    ]);
    for (final t in pull.tracks) {
      final key = '${t.session}/${t.name}';
      final w = wanted[key];
      if (w == null || t.mid == null || t.error != null) continue;
      _pulled[key] = (mid: t.mid!, userId: w.userId, kind: w.kind);
    }
    final sdp = pull.sdp;
    if (pull.renegotiate && sdp != null && _engine == engine) {
      final answer = await engine.answerOffer(sdp);
      await _api.answer(info.id, answer);
    }
    _bumpMedia();
  }

  void _bumpMedia() {
    final s = state;
    if (s != null) state = s.copyWith(media: s.media + 1);
  }

  void _finish(String status) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(phase: GroupCallPhase.ended, endStatus: status, minimized: false);
    _linger?.cancel();
    _linger = Timer(_t.endedLinger, () {
      if (state?.phase == GroupCallPhase.ended) state = null;
    });
    unawaited(ref.read(activeGroupCallsProvider.notifier).refresh());
  }

  void _stopMedia() {
    _poll?.cancel();
    _poll = null;
    _giveUp?.cancel();
    _giveUp = null;
    _rebuild?.cancel();
    _rebuild = null;
    _deniedClear?.cancel();
    _systemRinging = false;
    unawaited(_tones.stop());
    _pulled.clear();
    _queue = Future.value();
    final engine = _engine;
    _engine = null;
    if (engine != null) unawaited(_closeEngine(engine));
  }

  /// Lot 10.3 : données de l'appel comptées (type « appels »), puis fermeture.
  Future<void> _closeEngine(GroupCallEngine engine) async {
    try {
      final bytes = await engine.trafficBytes();
      if (bytes > 0) countData(ref, received: bytes, kind: 'call');
    } on Object {
      // Compteur indicatif.
    }
    try {
      await engine.close();
    } on Object {
      // Déjà fermé.
    }
  }

  // ---------------------------------------------------------------------------
  // Intégration au téléphone (comme les appels à deux, lot 9.1b)
  // ---------------------------------------------------------------------------
  void _syncSystem(GroupCallState? prev, GroupCallState? next) {
    final inCall = next != null && next.live && next.phase != GroupCallPhase.ringing;
    final active = inCall && !next.minimized;
    if (active != _overLock) {
      _overLock = active;
      unawaited(_system.setOverLock(active));
    }
    if (inCall != _callAudio) {
      _callAudio = inCall;
      unawaited(_system.setCallAudio(inCall));
    }
    final proximity = active && next.route == AudioRoute.earpiece && !next.camera && !next.video;
    if (proximity != _proximity) {
      _proximity = proximity;
      unawaited(_system.setProximity(proximity));
    }
    final id = next?.info.id ?? prev?.info.id;
    if (id == null || prev?.phase == next?.phase) return;
    switch (next?.phase) {
      case GroupCallPhase.joining when prev?.phase != GroupCallPhase.reconnecting:
        unawaited(_system.activate(id, video: next!.video, group: true));
      case GroupCallPhase.connected when prev?.phase != GroupCallPhase.reconnecting:
        unawaited(_system.connected(id));
      case GroupCallPhase.ended:
        unawaited(_system.end(id));
      case null when prev?.phase != GroupCallPhase.ended && prev?.phase != GroupCallPhase.ringing:
        unawaited(_system.end(id));
      default:
        break;
    }
  }
}
