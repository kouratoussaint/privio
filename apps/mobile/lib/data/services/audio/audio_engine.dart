import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Lecture d'un son déjà en mémoire (jamais écrit en clair sur le disque).
abstract interface class AudioEngine {
  Stream<Duration> get position;
  Stream<void> get completed;
  Future<void> play(Uint8List bytes, {double speed = 1.0});
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();
}

/// Implémentation Android (paquet `audioplayers`, source en mémoire).
class DeviceAudioEngine implements AudioEngine {
  DeviceAudioEngine() : _player = AudioPlayer() {
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  final AudioPlayer _player;

  @override
  Stream<Duration> get position => _player.onPositionChanged;

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List bytes, {double speed = 1.0}) async {
    await _player.stop();
    await _player.setSource(BytesSource(bytes, mimeType: 'audio/mp4'));
    await _player.setPlaybackRate(speed);
    await _player.resume();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setPlaybackRate(speed);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
