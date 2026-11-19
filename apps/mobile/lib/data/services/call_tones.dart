import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Lot 9.1a — sonnerie (appel reçu) et tonalité d'attente (appel émis), en boucle.
abstract interface class CallTones {
  Future<void> ring();

  /// [speaker] : appel vidéo (haut-parleur d'emblée).
  Future<void> ringback({bool speaker = false});
  Future<void> stop();
}

class DeviceCallTones implements CallTones {
  AudioPlayer? _player;
  Timer? _vibrate;

  Future<void> _loop(String asset, AudioContext context) async {
    await stop();
    // Lot 6.1 : pas de suivi de position (il redessinait l'écran à chaque image).
    final p = AudioPlayer()..positionUpdater = null;
    _player = p;
    await p.setAudioContext(context);
    await p.setReleaseMode(ReleaseMode.loop);
    await p.play(AssetSource(asset));
  }

  @override
  Future<void> ring() async {
    // Sonnerie : suit le mode silencieux / vibreur du téléphone.
    await _loop(
      'sounds/sonnerie.wav',
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.notificationRingtone,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ),
    );
    _vibrate = Timer.periodic(const Duration(seconds: 2), (_) => HapticFeedback.vibrate());
  }

  // Lot 9.3c : la bibliothèque des sons règle le mode et le haut-parleur de TOUT le
  // téléphone en préparant un son : la tonalité d'attente garde donc le mode « appel » et
  // la sortie de l'appel (sinon le téléphone repassait en mode normal, écouteur).
  @override
  Future<void> ringback({bool speaker = false}) => _loop(
    'sounds/tonalite.wav',
    AudioContext(
      android: AudioContextAndroid(
        usageType: AndroidUsageType.voiceCommunication,
        contentType: AndroidContentType.speech,
        audioFocus: AndroidAudioFocus.gainTransient,
        audioMode: AndroidAudioMode.inCommunication,
        isSpeakerphoneOn: speaker,
      ),
    ),
  );

  @override
  Future<void> stop() async {
    _vibrate?.cancel();
    _vibrate = null;
    final p = _player;
    _player = null;
    if (p != null) {
      await p.stop();
      await p.dispose();
    }
  }
}
