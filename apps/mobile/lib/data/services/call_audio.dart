import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Lot 9.3c (ADR-056) : son des appels — traitement du son, mesures, mode protégé.

/// Traitement du son de la bibliothèque d'appel (anti-écho, anti-bruit, niveau
/// automatique) au lieu de celui du téléphone : sur certains téléphones, celui-ci baissait
/// fortement la voix captée. À faire avant tout autre usage de la bibliothèque (le réglage
/// est lu une seule fois, à sa mise en route).
Future<void> prepareCallAudio() async {
  if (!Platform.isAndroid) return;
  await WebRTC.initialize(
    options: {
      'androidUseHardwareAudioProcessing': false,
      'androidAudioConfiguration': AndroidAudioConfiguration.communication.toMap(),
    },
  );
}

/// Indiqué au journal technique (le réglage ci-dessus).
const callAudioProcessing = 'traitement du son : Privio';

/// Niveaux moyens du son d'un appel, en dB (0 = maximum ; la voix courante est vers
/// −20 à −35 dB). Null si inconnu (aucun son reçu ou envoyé).
class CallAudioLevels {
  const CallAudioLevels({this.receivedDb, this.sentDb});

  final double? receivedDb;
  final double? sentDb;

  static const unknown = CallAudioLevels();
}

/// Calcule les niveaux moyens depuis les statistiques de la liaison : énergie totale du
/// son / durée (pistes reçues : « inbound-rtp » ; micro : « media-source »).
CallAudioLevels audioLevelsFromStats(Iterable<StatsReport> reports) {
  var inEnergy = 0.0, inDuration = 0.0, outEnergy = 0.0, outDuration = 0.0;
  for (final r in reports) {
    final v = r.values;
    final kind = v['kind'] ?? v['mediaType'];
    if (kind != 'audio') continue;
    final energy = (v['totalAudioEnergy'] as num?)?.toDouble() ?? 0;
    final duration = (v['totalSamplesDuration'] as num?)?.toDouble() ?? 0;
    if (r.type == 'inbound-rtp') {
      inEnergy += energy;
      inDuration += duration;
    } else if (r.type == 'media-source') {
      outEnergy += energy;
      outDuration += duration;
    }
  }
  double? db(double e, double d) {
    if (d <= 0) return null;
    if (e <= 0) return -100;
    return math.max(-100, 10 * math.log(e / d) / math.ln10);
  }

  return CallAudioLevels(receivedDb: db(inEnergy, inDuration), sentDb: db(outEnergy, outDuration));
}

/// État du son du téléphone pendant l'appel, lu côté Android.
class PhoneAudioState {
  const PhoneAudioState({
    required this.mode,
    required this.output,
    required this.speakerphone,
    required this.volume,
    required this.maxVolume,
  });

  /// communication, normal, appel, sonnerie…
  final String mode;

  /// Sortie réelle : haut-parleur, écouteur, bluetooth, casque, inconnue.
  final String output;
  final bool speakerphone;
  final int volume;
  final int maxVolume;

  static PhoneAudioState? fromMap(Map<Object?, Object?>? m) {
    if (m == null) return null;
    return PhoneAudioState(
      mode: m['mode'] as String? ?? 'inconnu',
      output: m['output'] as String? ?? 'inconnue',
      speakerphone: m['speakerphone'] as bool? ?? false,
      volume: (m['volume'] as num?)?.toInt() ?? -1,
      maxVolume: (m['max'] as num?)?.toInt() ?? -1,
    );
  }

  String describe() =>
      'mode $mode, sortie réelle $output${speakerphone ? ' (haut-parleur activé)' : ''}, '
      'volume d’appel $volume/$maxVolume';
}

/// Nom de la sortie choisie dans Privio, pour le journal.
String routeLabel(String route) => switch (route) {
  'speaker' => 'haut-parleur',
  'earpiece' => 'écouteur',
  'bluetooth' => 'bluetooth',
  'wired' => 'casque',
  _ => route,
};

String _db(double? v) => v == null ? '?' : '${v.round()} dB';

/// Ligne du journal technique à la fin d'un appel (aucun contenu, aucun nom).
String callAudioLine({
  required bool group,
  required Duration duration,
  required String route,
  required CallAudioLevels levels,
  PhoneAudioState? phone,
}) {
  final m = duration.inMinutes;
  final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return [
    'Son de l’appel${group ? ' de groupe' : ''} ($m min $s)',
    'sortie choisie ${routeLabel(route)}',
    'son reçu ${_db(levels.receivedDb)}, envoyé ${_db(levels.sentDb)}',
    if (phone != null) 'Android : ${phone.describe()}' else 'Android : état inconnu',
    callAudioProcessing,
  ].join(' · ');
}

/// Lot 9.3c : un appel est-il en cours (sons de Privio coupés pendant ce temps) ? La
/// bibliothèque qui joue ces sons remet le téléphone en mode normal et coupe le
/// haut-parleur à la préparation d'un son : jamais pendant un appel.
abstract final class CallAudioGate {
  static final Set<String> _sources = {};

  static bool get active => _sources.isNotEmpty;

  static void set(String source, bool on) => on ? _sources.add(source) : _sources.remove(source);

  /// Tests.
  static void reset() => _sources.clear();
}
