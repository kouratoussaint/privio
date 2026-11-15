import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Lot 9.1a — sonnerie (appel reçu) et tonalité d'attente (appel émis), en boucle.
abstract interface class CallTones {
  Future<void> ring();
  Future<void> ringback();
  Future<void> stop();
}

class DeviceCallTones implements CallTones {
  AudioPlayer? _player;
  Timer? _vibrate;

  Future<void> _loop(String asset, AudioContext context) async {
    await stop();
    final p = AudioPlayer();
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

  @override
  Future<void> ringback() => _loop(
    'sounds/tonalite.wav',
    AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.voiceCommunication,
        contentType: AndroidContentType.speech,
        audioFocus: AndroidAudioFocus.gainTransient,
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
