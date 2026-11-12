import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../data/services/audio/audio_engine.dart';
import '../data/services/audio/voice_recorder.dart';
import '../data/storage/local_cache.dart';
import '../domain/models/messaging.dart';
import 'messaging_providers.dart';
import 'providers.dart';

// ------------------------------------------------------------------------
// Lecture (VOICE-005) : un seul son à la fois ; vitesse 1×, 1,5×, 2×.
// ------------------------------------------------------------------------
const kPreviewId = 'preview';
const kVoiceSpeeds = [1.0, 1.5, 2.0];

class VoicePlayback {
  const VoicePlayback({
    this.id,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.speed = 1.0,
  });

  /// Message en cours (ou [kPreviewId] pour la préécoute), null si rien.
  final String? id;
  final bool playing;
  final bool loading;
  final Duration position;
  final double speed;

  VoicePlayback copyWith({bool? playing, Duration? position, double? speed}) => VoicePlayback(
    id: id,
    playing: playing ?? this.playing,
    loading: loading,
    position: position ?? this.position,
    speed: speed ?? this.speed,
  );
}

final voicePlayerProvider = NotifierProvider.autoDispose<VoicePlayerController, VoicePlayback>(
  VoicePlayerController.new,
);

class VoicePlayerController extends Notifier<VoicePlayback> {
  DateTime? _expiresAt;
  late AudioEngine _engine;

  @override
  VoicePlayback build() {
    _engine = ref.watch(audioEngineProvider);
    final pos = _engine.position.listen(_onPosition);
    final done = _engine.completed.listen((_) => _reset());
    ref.onDispose(() {
      unawaited(pos.cancel());
      unawaited(done.cancel());
      unawaited(_engine.stop().catchError((Object _) {}));
    });
    return const VoicePlayback();
  }

  void _reset() {
    _expiresAt = null;
    if (ref.mounted) state = VoicePlayback(speed: state.speed);
  }

  void _onPosition(Duration p) {
    if (state.id == null) return;
    // Un message qui expire pendant l'écoute s'interrompt aussitôt.
    final until = _expiresAt;
    if (until != null && !until.isAfter(DateTime.now())) {
      unawaited(stop());
      return;
    }
    state = state.copyWith(position: p);
  }

  /// Écouter / mettre en pause un vocal. Le son vient du coffre local s'il y est,
  /// sinon il est téléchargé (avec le jeton) puis rangé chiffré jusqu'à l'expiration.
  Future<void> toggle(ChatMessage m) async {
    if (state.id == m.id && !state.loading) {
      if (state.playing) {
        await _engine.pause();
        state = state.copyWith(playing: false);
      } else {
        await _engine.resume();
        state = state.copyWith(playing: true);
      }
      return;
    }
    if (!m.hasPlayableVoice) throw const AppFailure(FailureCode.mediaNotFound);
    if (!m.isVisibleAt(DateTime.now())) throw const AppFailure(FailureCode.messageExpired);
    final speed = state.speed;
    await _engine.stop();
    state = VoicePlayback(id: m.id, loading: true, speed: speed);
    try {
      final cache = ref.read(localCacheProvider);
      final key = LocalCache.messageMediaKey(m.id);
      var audio = await cache.readMedia(key);
      if (audio == null) {
        audio = await ref.read(messagingApiProvider).downloadVoice(m.mediaPath!);
        await cache.putMedia(key, audio, m.expiresAt);
        if (ref.mounted) ref.read(offlineProvider.notifier).report(offline: false);
      }
      if (!ref.mounted || state.id != m.id) return; // un autre son a été demandé entre-temps
      _expiresAt = m.expiresAt;
      await _engine.play(audio, speed: speed);
      state = VoicePlayback(id: m.id, playing: true, speed: speed);
    } on Object catch (e) {
      final failure = toAppFailure(e);
      if (ref.mounted) {
        if (failure.code == FailureCode.network) {
          ref.read(offlineProvider.notifier).report(offline: true);
        }
        if (state.id == m.id) _reset();
      }
      throw failure;
    }
  }

  /// Préécoute d'un enregistrement avant envoi (VOICE-004).
  Future<void> togglePreview(Uint8List audio) async {
    if (state.id == kPreviewId) {
      if (state.playing) {
        await _engine.pause();
        state = state.copyWith(playing: false);
      } else {
        await _engine.resume();
        state = state.copyWith(playing: true);
      }
      return;
    }
    _expiresAt = null;
    await _engine.play(audio, speed: state.speed);
    state = VoicePlayback(id: kPreviewId, playing: true, speed: state.speed);
  }

  Future<void> seek(Duration position) async {
    if (state.id == null) return;
    await _engine.seek(position);
    state = state.copyWith(position: position);
  }

  /// 1× → 1,5× → 2× → 1×.
  Future<void> cycleSpeed() async {
    final next = kVoiceSpeeds[(kVoiceSpeeds.indexOf(state.speed) + 1) % kVoiceSpeeds.length];
    if (state.id != null) await _engine.setSpeed(next);
    state = state.copyWith(speed: next);
  }

  Future<void> stop() async {
    await _engine.stop();
    _reset();
  }
}

// ------------------------------------------------------------------------
// Enregistrement (VOICE-001 à 004) : maintenir ou toucher, verrouiller, arrêt
// automatique à la limite, préécoute ou annulation avant tout envoi.
// ------------------------------------------------------------------------
sealed class VoiceRecState {
  const VoiceRecState();
}

class VoiceIdle extends VoiceRecState {
  const VoiceIdle();
}

class VoiceRecording extends VoiceRecState {
  const VoiceRecording({required this.elapsed, required this.locked, required this.max});

  final Duration elapsed;

  /// Verrouillé : l'enregistrement continue sans garder le doigt sur le micro.
  final bool locked;
  final Duration max;

  Duration get remaining => max - elapsed;
}

class VoicePreview extends VoiceRecState {
  const VoicePreview({required this.audio, required this.duration});

  final Uint8List audio;
  final Duration duration;
}

/// Résultat de l'arrêt d'un enregistrement.
enum VoiceStopResult { preview, tooShort, failed, none }

final voiceRecorderControllerProvider =
    NotifierProvider.autoDispose<VoiceRecorderController, VoiceRecState>(
      VoiceRecorderController.new,
    );

class VoiceRecorderController extends Notifier<VoiceRecState> {
  static const tick = Duration(milliseconds: 100);
  static const minDuration = Duration(seconds: 1);

  /// Marge : l'enregistrement s'arrête juste avant la limite (le serveur mesure le son
  /// et tolère 0,5 s ; les délais d'arrêt du micro ne doivent pas la faire dépasser).
  static const safety = Duration(milliseconds: 300);

  Timer? _timer;
  bool _starting = false;
  bool _releasedWhileStarting = false;
  late VoiceRecorder _recorder;

  /// Appelé à l'arrêt automatique (limite atteinte), pour prévenir l'interface.
  void Function(VoiceStopResult result)? onAutoStop;

  @override
  VoiceRecState build() {
    _recorder = ref.watch(voiceRecorderProvider);
    ref.onDispose(() {
      _timer?.cancel();
      // Écran quitté pendant un enregistrement : rien n'est conservé.
      if (_timer != null || _starting) unawaited(_recorder.cancel());
    });
    return const VoiceIdle();
  }

  Duration get _max => (ref.read(messagingRulesProvider).value ?? const MessagingRules()).voiceMax;

  /// Démarre l'enregistrement (après accord pour le micro). [locked] : sans maintien.
  Future<MicPermission> start({required bool locked}) async {
    if (state is! VoiceIdle || _starting) return MicPermission.granted;
    _starting = true;
    _releasedWhileStarting = false;
    try {
      final permission = await _recorder.ensurePermission();
      if (permission != MicPermission.granted || !ref.mounted) return permission;
      if (_releasedWhileStarting && !locked) return MicPermission.granted; // doigt déjà levé
      await ref.read(voicePlayerProvider.notifier).stop();
      await _recorder.start();
      if (!ref.mounted) return MicPermission.granted;
      state = VoiceRecording(elapsed: Duration.zero, locked: locked, max: _max);
      _timer = Timer.periodic(tick, (_) => _onTick());
      if (_releasedWhileStarting && !locked) await cancel();
      return MicPermission.granted;
    } finally {
      _starting = false;
    }
  }

  void _onTick() {
    final s = state;
    if (s is! VoiceRecording) return;
    final elapsed = s.elapsed + tick;
    state = VoiceRecording(elapsed: elapsed, locked: s.locked, max: s.max);
    if (elapsed >= s.max - safety) {
      unawaited(stop().then((r) => onAutoStop?.call(r)));
    }
  }

  /// Glisser vers le haut : l'enregistrement continue sans maintien (VOICE-002).
  void lock() {
    final s = state;
    if (s is VoiceRecording && !s.locked) {
      state = VoiceRecording(elapsed: s.elapsed, locked: true, max: s.max);
    }
  }

  /// Doigt levé : arrêt et préécoute (si l'enregistrement n'est pas verrouillé).
  Future<VoiceStopResult> release() async {
    if (_starting) {
      _releasedWhileStarting = true;
      return VoiceStopResult.none;
    }
    final s = state;
    if (s is VoiceRecording && !s.locked) return stop();
    return VoiceStopResult.none;
  }

  /// Arrêt : le son passe en préécoute ; rien n'est envoyé sans confirmation.
  Future<VoiceStopResult> stop() async {
    final s = state;
    if (s is! VoiceRecording) return VoiceStopResult.none;
    _timer?.cancel();
    _timer = null;
    state = const VoiceIdle();
    final audio = await _recorder.stop();
    if (!ref.mounted) return VoiceStopResult.none;
    if (s.elapsed < minDuration) return VoiceStopResult.tooShort;
    if (audio == null || audio.isEmpty) return VoiceStopResult.failed;
    state = VoicePreview(audio: audio, duration: s.elapsed);
    return VoiceStopResult.preview;
  }

  /// Annulation (glisser vers la gauche, ou bouton) : rien n'est conservé.
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    final wasRecording = state is VoiceRecording;
    state = const VoiceIdle();
    if (wasRecording) await _recorder.cancel();
  }

  /// Préécoute abandonnée.
  Future<void> discard() async {
    if (state is VoicePreview) {
      await ref.read(voicePlayerProvider.notifier).stop();
      state = const VoiceIdle();
    }
  }

  /// Prend l'enregistrement en préécoute pour l'envoyer (l'état revient au repos).
  Future<VoicePreview?> take() async {
    final s = state;
    if (s is! VoicePreview) return null;
    await ref.read(voicePlayerProvider.notifier).stop();
    state = const VoiceIdle();
    return s;
  }
}
