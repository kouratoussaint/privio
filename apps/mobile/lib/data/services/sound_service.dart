import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Lot 7.2b2 : sons courts de l'application (créés pour Privio, voir tools/sons).
enum PrivioSound {
  sent('envoye'),
  received('recu'),
  cleared('vider'),
  deletedForAll('supprime'),
  reaction('reaction'),
  voiceStart('vocal_debut'),
  voiceStop('vocal_fin'),
  unlocked('deverrouille'),
  pinError('code_faux'),
  success('succes');

  const PrivioSound(this.file);

  final String file;
}

abstract interface class SoundPlayer {
  Future<void> play(PrivioSound sound);
}

/// Lecture en « son d'interface » (Android : flux des sons système) : silencieux quand le
/// téléphone est en mode silencieux ou vibreur, et sans interrompre la musique ni un
/// vocal en cours (pas de prise du focus audio).
class DeviceSoundPlayer implements SoundPlayer {
  final Map<PrivioSound, AudioPlayer> _players = {};

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  @override
  Future<void> play(PrivioSound sound) async {
    try {
      final p = _players[sound] ??= await _create(sound);
      await p.stop();
      await p.resume();
    } on Object {
      // Un son qui ne joue pas ne doit jamais gêner l'usage.
    }
  }

  Future<AudioPlayer> _create(PrivioSound sound) async {
    final p = AudioPlayer();
    await p.setAudioContext(_context);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setSource(AssetSource('sounds/${sound.file}.wav'));
    return p;
  }
}
