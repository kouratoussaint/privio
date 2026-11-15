import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../data/services/audio/voice_recorder.dart' show MicPermission;
import '../data/services/call_engine.dart';
import '../data/services/call_tones.dart';
import '../data/services/calls_api.dart';
import '../domain/models/call.dart';
import 'messaging_providers.dart';
import 'providers.dart';

/// Lot 9.1a — appels audio à deux (ADR-036). Mise en relation par la base (état, signaux),
/// voix de téléphone à téléphone (WebRTC). Un seul appel à la fois.

final callsApiProvider = Provider<CallsApi>(
  (ref) => throw UnimplementedError('callsApiProvider doit être surchargé'),
);
final callEngineFactoryProvider = Provider<CallEngine Function()>((ref) => WebRtcCallEngine.new);
final callTonesProvider = Provider<CallTones>((ref) => DeviceCallTones());

/// Délais (réduits dans les tests).
class CallTimings {
  const CallTimings({
    this.fastPoll = const Duration(seconds: 1),
    this.slowPoll = const Duration(seconds: 4),
    this.endedLinger = const Duration(milliseconds: 1800),
  });

  final Duration fastPoll;
  final Duration slowPoll;

  /// Temps pendant lequel « Appel terminé » reste affiché.
  final Duration endedLinger;
}

final callTimingsProvider = Provider<CallTimings>((ref) => const CallTimings());

enum CallPhase { outgoingRinging, incomingRinging, connecting, connected, reconnecting, ended }

class CallState {
  const CallState({
    required this.info,
    required this.phase,
    this.muted = false,
    this.speaker = false,
    this.connectedAt,
    this.endStatus,
    this.minimized = false,
  });

  final CallInfo info;
  final CallPhase phase;
  final bool muted;
  final bool speaker;
  final DateTime? connectedAt;

  /// Statut final (ex. 'declined', 'missed', 'busy', 'failed', 'ended').
  final String? endStatus;

  /// Écran d'appel réduit en bandeau (on continue d'utiliser Privio).
  final bool minimized;

  CallState copyWith({
    CallInfo? info,
    CallPhase? phase,
    bool? muted,
    bool? speaker,
    DateTime? connectedAt,
    String? endStatus,
    bool? minimized,
  }) => CallState(
    info: info ?? this.info,
    phase: phase ?? this.phase,
    muted: muted ?? this.muted,
    speaker: speaker ?? this.speaker,
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

  CallsApi get _api => ref.read(callsApiProvider);
  // Lu une fois (build) : utilisable aussi à la destruction, où Ref est interdit.
  late CallTones _tones;
  CallTimings get _t => ref.read(callTimingsProvider);

  @override
  CallState? build() {
    _tones = ref.read(callTonesProvider);
    // Appel annoncé par le canal temps réel (nouvel appel, réponse, signal, fin).
    ref.listen(realtimeSignalsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s.event == 'call' && s.callId != null) unawaited(_onSignal(s.callId!));
      if (s.event == 'resume' || s.event == 'reconnected') unawaited(checkOpenCall());
    });
    ref.onDispose(_reset);
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
      final open = await _api.openCall();
      if (open != null && !open.outgoing && open.status == 'ringing' && !busy) {
        _incoming(open);
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
    unawaited(_tones.ring());
    _startPolling();
  }

  Future<void> accept() async {
    final s = state;
    if (s == null || s.phase != CallPhase.incomingRinging) return;
    unawaited(_tones.stop());
    try {
      await _ensureMic();
    } on AppFailure {
      await decline();
      rethrow;
    }
    state = s.copyWith(phase: CallPhase.connecting);
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
    if (s == null) return;
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

  Future<void> toggleSpeaker() async {
    final s = state;
    if (s == null) return;
    await _engine?.setSpeaker(!s.speaker);
    state = s.copyWith(speaker: !s.speaker);
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
        state = s.copyWith(
          phase: CallPhase.connected,
          connectedAt: s.connectedAt ?? DateTime.now(),
        );
        _startPolling();
      case CallMediaState.reconnecting:
        state = s.copyWith(phase: CallPhase.reconnecting);
      case CallMediaState.failed:
        unawaited(hangUp(reason: 'failed'));
      case CallMediaState.connecting:
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
          _pendingOffer = sig.payload;
        case 'answer':
          if (_engineOpen) unawaited(_engine!.setAnswer(sig.payload).catchError((Object _) {}));
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
