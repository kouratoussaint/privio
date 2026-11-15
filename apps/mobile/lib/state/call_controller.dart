import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../data/services/audio/voice_recorder.dart' show MicPermission;
import '../data/services/call_engine.dart';
import '../data/services/call_system.dart';
import '../data/services/call_tones.dart';
import '../data/services/calls_api.dart';
import '../domain/models/call.dart';
import '../data/services/device_services.dart' show NetKind;
import 'data_providers.dart';
import 'messaging_providers.dart';
import 'providers.dart';

/// Lot 9.1a — appels audio à deux (ADR-036). Mise en relation par la base (état, signaux),
/// voix de téléphone à téléphone (WebRTC). Un seul appel à la fois.
///
/// Lot 9.1b (ADR-037) : appel reçu Privio fermé ou téléphone verrouillé (écran d'appel du
/// téléphone), appel maintenu écran éteint, sortie du son, reconnexion au changement de
/// réseau, « Connexion faible ».

final callsApiProvider = Provider<CallsApi>(
  (ref) => throw UnimplementedError('callsApiProvider doit être surchargé'),
);
final callEngineFactoryProvider = Provider<CallEngine Function()>((ref) => WebRtcCallEngine.new);
final callTonesProvider = Provider<CallTones>((ref) => DeviceCallTones());
final callSystemProvider = Provider<CallSystem>((ref) => const NoCallSystem());

/// Privio au premier plan ? (Sinon, c'est l'écran d'appel du téléphone qui sonne.)
final appForegroundProvider = Provider<bool Function()>(
  (ref) => () {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  },
);

/// Délais (réduits dans les tests).
class CallTimings {
  const CallTimings({
    this.fastPoll = const Duration(seconds: 1),
    this.slowPoll = const Duration(seconds: 4),
    this.endedLinger = const Duration(milliseconds: 1800),
    this.iceRestartAfter = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(seconds: 30),
  });

  final Duration fastPoll;
  final Duration slowPoll;

  /// Temps pendant lequel « Appel terminé » reste affiché.
  final Duration endedLinger;

  /// Liaison coupée : nouvelle négociation après ce délai (appelant), abandon après.
  final Duration iceRestartAfter;
  final Duration giveUpAfter;
}

final callTimingsProvider = Provider<CallTimings>((ref) => const CallTimings());

enum CallPhase { outgoingRinging, incomingRinging, connecting, connected, reconnecting, ended }

class CallState {
  const CallState({
    required this.info,
    required this.phase,
    this.muted = false,
    this.route = AudioRoute.earpiece,
    this.weak = false,
    this.connectedAt,
    this.endStatus,
    this.minimized = false,
  });

  final CallInfo info;
  final CallPhase phase;
  final bool muted;

  /// Sortie du son (lot 9.1b).
  final AudioRoute route;
  bool get speaker => route == AudioRoute.speaker;

  /// Connexion faible (pertes, latence), appel toujours en cours.
  final bool weak;
  final DateTime? connectedAt;

  /// Statut final (ex. 'declined', 'missed', 'busy', 'failed', 'ended').
  final String? endStatus;

  /// Écran d'appel réduit en bandeau (on continue d'utiliser Privio).
  final bool minimized;

  CallState copyWith({
    CallInfo? info,
    CallPhase? phase,
    bool? muted,
    AudioRoute? route,
    bool? weak,
    DateTime? connectedAt,
    String? endStatus,
    bool? minimized,
  }) => CallState(
    info: info ?? this.info,
    phase: phase ?? this.phase,
    muted: muted ?? this.muted,
    route: route ?? this.route,
    weak: weak ?? this.weak,
    connectedAt: connectedAt ?? this.connectedAt,
    endStatus: endStatus ?? this.endStatus,
    minimized: minimized ?? this.minimized,
  );
}

final callControllerProvider = NotifierProvider<CallController, CallState?>(CallController.new);

class CallController extends Notifier<CallState?> {
  CallEngine? _engine;
  Timer? _poll;
  Timer? _linger;
  int _after = 0;
  bool _polling = false;
  bool _engineOpen = false;
  Map<String, dynamic>? _pendingOffer;
  final List<Map<String, dynamic>> _pendingIce = [];
  Timer? _restart;
  Timer? _giveUp;
  DateTime? _lastRestart;
  NetKind? _net;

  /// Appel annoncé par l'écran d'appel du téléphone (Privio en arrière-plan).
  bool _systemRinging = false;
  bool _overLock = false;
  bool _proximity = false;

  CallsApi get _api => ref.read(callsApiProvider);
  // Lu une fois (build) : utilisable aussi à la destruction, où Ref est interdit.
  late CallTones _tones;
  late CallSystem _system;
  CallTimings get _t => ref.read(callTimingsProvider);

  @override
  CallState? build() {
    _tones = ref.read(callTonesProvider);
    _system = ref.read(callSystemProvider);
    // Appel annoncé par le canal temps réel (nouvel appel, réponse, signal, fin).
    ref.listen(realtimeSignalsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s.event == 'call' && s.callId != null) unawaited(_onSignal(s.callId!));
      if (s.event == 'resume') _onResume();
      if (s.event == 'resume' || s.event == 'reconnected') unawaited(checkOpenCall());
    });
    // Lot 9.1b : actions faites sur l'écran d'appel du téléphone ou sa notification.
    final events = _system.events.listen(_onSystem);
    // Changement de réseau pendant l'appel (Wi-Fi ↔ données) : renégocier la liaison.
    final net = ref.read(networkMonitorProvider).changes().listen(_onNetwork);
    listenSelf(_syncSystem);
    ref.onDispose(() {
      unawaited(events.cancel());
      unawaited(net.cancel());
      _reset();
    });
    return null;
  }

  bool get busy => state != null && state!.phase != CallPhase.ended;

  // ---------------------------------------------------------------------------
  // Appeler
  // ---------------------------------------------------------------------------
  /// Lance un appel audio dans une discussion à deux. Lève une [AppFailure] si impossible.
  Future<void> start(String conversationId) async {
    if (busy) throw const AppFailure(FailureCode.callAlreadyActive);
    await _ensureMic();
    final info = await _api.startCall(conversationId);
    if (!info.open) {
      // Correspondant déjà en appel.
      _show(
        CallState(info: info, phase: CallPhase.ended, endStatus: info.endReason ?? info.status),
      );
      return;
    }
    state = CallState(info: info, phase: CallPhase.outgoingRinging);
    _startPolling();
    unawaited(_tones.ringback());
    await _ensureNearby();
    try {
      await _openEngine();
      final offer = await _engine!.createOffer();
      await _api.signal(info.id, 'offer', offer);
    } on Object {
      await hangUp(reason: 'failed');
    }
  }

  // ---------------------------------------------------------------------------
  // Recevoir
  // ---------------------------------------------------------------------------
  /// Appel encore ouvert à l'ouverture de l'application (ou au retour au premier plan).
  Future<void> checkOpenCall() async {
    if (busy) return;
    try {
      // Décroché sur l'écran d'appel du téléphone pendant que Privio était fermé.
      final accepted = await _system.acceptedCall();
      final open = await _api.openCall();
      if (open != null && !open.outgoing && open.status == 'ringing' && !busy) {
        _incoming(open);
        if (accepted == open.id) await accept();
      } else if (accepted != null && accepted != open?.id) {
        await _system.end(accepted);
      }
    } on Object {
      // Hors connexion : le canal temps réel ou le prochain retour réessaiera.
    }
  }

  Future<void> _onSignal(String callId) async {
    final current = state;
    if (current != null && current.info.id == callId) {
      await _pollNow();
      return;
    }
    if (busy) return; // Un appel à la fois (le serveur répond « occupé »).
    try {
      final snap = await _api.state(callId);
      if (!snap.call.outgoing && snap.call.status == 'ringing' && !busy) {
        _incoming(snap.call);
        _process(snap);
      }
    } on Object {
      // Ignoré : l'appel sera retrouvé au prochain retour dans l'application.
    }
  }

  void _incoming(CallInfo info) {
    _linger?.cancel();
    _after = 0;
    state = CallState(info: info, phase: CallPhase.incomingRinging);
    if (ref.read(appForegroundProvider)()) {
      // L'écran de Privio sonne : celui du téléphone (message de réveil) s'efface.
      _systemRinging = false;
      unawaited(_system.hideIncoming(info.id));
      unawaited(_tones.ring());
    } else {
      _systemRinging = true;
      unawaited(_system.showIncoming(info.id));
    }
    _startPolling();
  }

  void _onResume() {
    final s = state;
    if (s != null && s.phase == CallPhase.incomingRinging && _systemRinging) {
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
        if (same && s.phase == CallPhase.incomingRinging) {
          await accept();
        } else if (!busy) {
          try {
            final snap = await _api.state(e.callId);
            if (!snap.call.outgoing && snap.call.status == 'ringing' && !busy) {
              _incoming(snap.call);
              _process(snap);
              await accept();
            }
          } on Object {
            await _system.end(e.callId);
          }
        }
      case CallSystemAction.decline:
        if (same && s.phase == CallPhase.incomingRinging) await decline();
      case CallSystemAction.end:
        if (same && s.phase != CallPhase.ended && s.phase != CallPhase.incomingRinging) {
          await hangUp();
        }
    }
  }

  Future<void> accept() async {
    final s = state;
    if (s == null || s.phase != CallPhase.incomingRinging) return;
    _systemRinging = false;
    unawaited(_tones.stop());
    try {
      await _ensureMic();
    } on AppFailure {
      await decline();
      rethrow;
    }
    state = s.copyWith(phase: CallPhase.connecting);
    await _ensureNearby();
    try {
      final info = await _api.answer(s.info.id);
      state = state?.copyWith(info: info);
      await _openEngine();
      await _pollNow();
      await _answerIfReady();
    } on Object {
      await hangUp(reason: 'failed');
    }
  }

  Future<void> decline() async {
    final s = state;
    if (s == null || s.phase != CallPhase.incomingRinging) return;
    unawaited(_tones.stop());
    try {
      final info = await _api.decline(s.info.id);
      _finish(info, 'declined');
    } on Object {
      _finish(s.info, 'declined');
    }
  }

  // ---------------------------------------------------------------------------
  // Pendant l'appel
  // ---------------------------------------------------------------------------
  Future<void> hangUp({String reason = 'hangup'}) async {
    final s = state;
    if (s == null || s.phase == CallPhase.ended) return;
    try {
      final info = await _api.end(s.info.id, reason: reason);
      _finish(info, reason == 'failed' ? 'failed' : info.status);
    } on Object {
      _finish(s.info, reason == 'failed' ? 'failed' : 'ended');
    }
  }

  Future<void> toggleMute() async {
    final s = state;
    if (s == null) return;
    await _engine?.setMuted(!s.muted);
    state = s.copyWith(muted: !s.muted);
  }

  Future<void> toggleSpeaker() =>
      selectRoute(state?.speaker == true ? AudioRoute.earpiece : AudioRoute.speaker);

  /// Sorties du son disponibles maintenant (Bluetooth, casque filaire s'ils sont branchés).
  Future<List<AudioRoute>> audioRoutes() async {
    try {
      return await _engine?.audioRoutes() ?? const [AudioRoute.earpiece, AudioRoute.speaker];
    } on Object {
      return const [AudioRoute.earpiece, AudioRoute.speaker];
    }
  }

  Future<void> selectRoute(AudioRoute route) async {
    final s = state;
    if (s == null) return;
    try {
      await _engine?.setSpeaker(route == AudioRoute.speaker);
      if (route != AudioRoute.speaker) await _engine?.selectAudioRoute(route);
    } on Object {
      // Sortie indisponible (appareil débranché entre-temps) : on garde la précédente.
      return;
    }
    state = state?.copyWith(route: route);
  }

  void setMinimized(bool value) {
    final s = state;
    if (s != null) state = s.copyWith(minimized: value);
  }

  // ---------------------------------------------------------------------------
  // Mécanique
  // ---------------------------------------------------------------------------
  Future<void> _ensureMic() async {
    final p = await ref.read(voiceRecorderProvider).ensurePermission();
    if (p != MicPermission.granted) throw const AppFailure(FailureCode.microphoneDenied);
  }

  /// Appareils Bluetooth (écouteurs, voiture) : facultatif, jamais bloquant.
  Future<void> _ensureNearby() async {
    try {
      await ref.read(permissionGatewayProvider).requestNearbyDevices();
    } on Object {
      // Refusé : l'appel passe par l'écouteur ou le haut-parleur.
    }
  }

  Future<void> _openEngine() async {
    if (_engineOpen) return;
    final id = state!.info.id;
    final engine = ref.read(callEngineFactoryProvider)();
    _engine = engine;
    final servers = await _api.iceServers();
    await engine.open(
      iceServers: servers,
      onCandidate: (c) => unawaited(_api.signal(id, 'ice', c).catchError((Object _) {})),
      onState: _onMedia,
      onQuality: (weak) {
        final s = state;
        if (s != null && s.phase == CallPhase.connected && s.weak != weak) {
          state = s.copyWith(weak: weak);
        }
      },
    );
    _engineOpen = true;
    for (final c in _pendingIce) {
      await engine.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void _onMedia(CallMediaState m) {
    final s = state;
    if (s == null || s.phase == CallPhase.ended) return;
    switch (m) {
      case CallMediaState.connected:
        unawaited(_tones.stop());
        _restart?.cancel();
        _giveUp?.cancel();
        _giveUp = null;
        state = s.copyWith(
          phase: CallPhase.connected,
          connectedAt: s.connectedAt ?? DateTime.now(),
          weak: false,
        );
        _startPolling();
      case CallMediaState.reconnecting:
      case CallMediaState.failed:
        // Lot 9.1b : réseau changé ou coupé. On garde l'appel : l'appelant renégocie,
        // l'appel ne s'arrête qu'au bout de [CallTimings.giveUpAfter].
        if (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting) {
          state = s.copyWith(phase: CallPhase.reconnecting, weak: false);
          _giveUp ??= Timer(_t.giveUpAfter, () => unawaited(hangUp(reason: 'failed')));
          _restart?.cancel();
          _restart = Timer(
            m == CallMediaState.failed ? Duration.zero : _t.iceRestartAfter,
            () => unawaited(_restartIce()),
          );
        } else if (m == CallMediaState.failed) {
          unawaited(hangUp(reason: 'failed'));
        }
      case CallMediaState.connecting:
        break;
    }
  }

  void _onNetwork(NetKind kind) {
    final previous = _net;
    _net = kind;
    final s = state;
    if (s == null || kind == NetKind.none || previous == kind) return;
    if (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting) {
      _restart?.cancel();
      _restart = Timer(const Duration(milliseconds: 500), () => unawaited(_restartIce()));
    }
  }

  /// L'appelant propose une nouvelle liaison (le correspondant répond comme au début).
  Future<void> _restartIce() async {
    final s = state;
    final engine = _engine;
    if (s == null || !s.info.outgoing || engine == null || !_engineOpen) return;
    if (s.phase != CallPhase.connected && s.phase != CallPhase.reconnecting) return;
    final last = _lastRestart;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 3)) {
      // Une renégociation à la fois ; nouvel essai si la liaison ne revient pas.
      _restart = Timer(const Duration(seconds: 4), () => unawaited(_restartIce()));
      return;
    }
    _lastRestart = DateTime.now();
    try {
      final offer = await engine.restartIce();
      await _api.signal(s.info.id, 'offer', offer);
    } on Object {
      // Réseau encore absent : nouvel essai tant que l'appel n'est pas abandonné.
      _restart = Timer(const Duration(seconds: 4), () => unawaited(_restartIce()));
    }
  }

  // ---------------------------------------------------------------------------
  // Intégration au téléphone (lot 9.1b)
  // ---------------------------------------------------------------------------
  void _syncSystem(CallState? prev, CallState? next) {
    final active =
        next != null &&
        !next.minimized &&
        next.phase != CallPhase.ended &&
        next.phase != CallPhase.incomingRinging;
    // Écran d'appel par-dessus l'écran de verrouillage ; réduit, on retrouve le verrouillage.
    if (active != _overLock) {
      _overLock = active;
      unawaited(_system.setOverLock(active));
    }
    final proximity = active && next.route == AudioRoute.earpiece;
    if (proximity != _proximity) {
      _proximity = proximity;
      unawaited(_system.setProximity(proximity));
    }
    final id = next?.info.id ?? prev?.info.id;
    if (id == null || prev?.phase == next?.phase) return;
    switch (next?.phase) {
      case CallPhase.outgoingRinging:
        unawaited(_system.activate(id));
      case CallPhase.connecting when prev?.phase == CallPhase.incomingRinging:
        unawaited(_system.activate(id));
      case CallPhase.connected when prev?.phase != CallPhase.reconnecting:
        unawaited(_system.connected(id));
      case CallPhase.ended:
        unawaited(_system.end(id));
      case null when prev?.phase != CallPhase.ended:
        unawaited(_system.end(id));
      default:
        break;
    }
  }

  Future<void> _answerIfReady() async {
    final offer = _pendingOffer;
    final s = state;
    if (offer == null || !_engineOpen || s == null || s.info.outgoing) return;
    if (s.phase == CallPhase.incomingRinging) return; // pas encore décroché
    _pendingOffer = null;
    final answer = await _engine!.acceptOffer(offer);
    await _api.signal(s.info.id, 'answer', answer);
  }

  void _startPolling() {
    _poll?.cancel();
    final fast = state?.phase != CallPhase.connected;
    _poll = Timer.periodic(fast ? _t.fastPoll : _t.slowPoll, (_) => unawaited(_pollNow()));
  }

  Future<void> _pollNow() async {
    final s = state;
    if (s == null || s.phase == CallPhase.ended || _polling) return;
    _polling = true;
    try {
      final snap = await _api.state(s.info.id, after: _after);
      _process(snap);
    } on Object {
      // Réseau instable : on réessaie au prochain tour (le serveur clôt après 60 s).
    } finally {
      _polling = false;
    }
  }

  void _process(CallSnapshot snap) {
    final s = state;
    if (s == null || s.info.id != snap.call.id || s.phase == CallPhase.ended) return;
    final call = snap.call;
    for (final sig in snap.signals) {
      if (sig.id <= _after) continue;
      _after = sig.id;
      switch (sig.kind) {
        case 'offer':
          // Première offre, ou renégociation après un changement de réseau (lot 9.1b).
          _pendingOffer = sig.payload;
        case 'answer':
          if (_engineOpen) {
            _lastRestart = null;
            unawaited(_engine!.setAnswer(sig.payload).catchError((Object _) {}));
          }
        case 'ice':
          if (_engineOpen) {
            unawaited(_engine!.addCandidate(sig.payload).catchError((Object _) {}));
          } else {
            _pendingIce.add(sig.payload);
          }
      }
    }
    if (!call.open) {
      _finish(call, call.endReason == 'busy' ? 'busy' : call.status);
      return;
    }
    if (call.status == 'accepted' && s.phase == CallPhase.outgoingRinging) {
      unawaited(_tones.stop());
      state = s.copyWith(info: call, phase: CallPhase.connecting);
    }
    unawaited(_answerIfReady().catchError((Object _) => hangUp(reason: 'failed')));
  }

  void _finish(CallInfo info, String status) {
    final s = state;
    if (s == null) return;
    _show(s.copyWith(info: info, phase: CallPhase.ended, endStatus: status, minimized: false));
  }

  /// Affiche l'état final un instant, puis ferme l'écran d'appel.
  void _show(CallState ended) {
    _stopMedia();
    state = ended;
    _linger?.cancel();
    _linger = Timer(_t.endedLinger, () {
      if (state?.phase == CallPhase.ended) state = null;
    });
  }

  void _stopMedia() {
    _poll?.cancel();
    _poll = null;
    _restart?.cancel();
    _restart = null;
    _giveUp?.cancel();
    _giveUp = null;
    _lastRestart = null;
    _systemRinging = false;
    unawaited(_tones.stop());
    final engine = _engine;
    _engine = null;
    _engineOpen = false;
    _pendingOffer = null;
    _pendingIce.clear();
    _after = 0;
    if (engine != null) unawaited(engine.close().catchError((Object _) {}));
  }

  void _reset() {
    _linger?.cancel();
    _stopMedia();
  }
}
