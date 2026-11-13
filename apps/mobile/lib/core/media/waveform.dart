import 'dart:math' as math;

/// Spectre des messages vocaux (lot 4.5).
///
/// Pendant l'enregistrement, le micro donne un niveau en dBFS (≈ −160 à 0) environ
/// dix fois par seconde. On le ramène entre 0 et 1, puis, à l'arrêt, on en tire un
/// profil de [kWaveformBars] valeurs entières de 0 à 100, envoyé avec le son.

/// Nombre de barres du profil envoyé (le serveur accepte de 8 à 64 valeurs).
const kWaveformBars = 40;

/// Niveau sous lequel on considère qu'il n'y a que du silence.
const _floorDb = -50.0;

/// dBFS → 0..1 (la voix courante se situe vers −30 à −5 dBFS).
double levelFromDb(double db) {
  if (db.isNaN || db.isInfinite) return 0;
  return ((db - _floorDb) / -_floorDb).clamp(0.0, 1.0);
}

/// Profil de [bars] valeurs (0 à 100) à partir des niveaux mesurés ; null si aucune
/// mesure (le spectre affiché sera alors neutre). Le plus fort passage vaut 100, pour
/// qu'un enregistrement discret garde une forme lisible.
List<int>? buildWaveform(List<double> levels, {int bars = kWaveformBars}) {
  if (levels.isEmpty) return null;
  final buckets = List<double>.filled(bars, 0);
  for (var i = 0; i < bars; i++) {
    final start = (i * levels.length / bars).floor();
    final end = math.max(start + 1, ((i + 1) * levels.length / bars).floor());
    var peak = 0.0;
    for (var j = start; j < end && j < levels.length; j++) {
      peak = math.max(peak, levels[j]);
    }
    buckets[i] = peak;
  }
  final top = buckets.reduce(math.max);
  if (top <= 0.02) return List<int>.filled(bars, 0);
  return [for (final b in buckets) (b / top * 100).round()];
}

/// Profil ramené à [count] barres pour l'affichage (null : spectre neutre).
List<double> displayBars(List<int>? waveform, int count) {
  if (waveform == null || waveform.isEmpty) {
    // Forme neutre, régulière, pour les vocaux sans profil (anciennes versions).
    return [for (var i = 0; i < count; i++) 0.25 + 0.15 * math.sin(i * 0.9).abs()];
  }
  return [
    for (var i = 0; i < count; i++)
      (waveform[(i * waveform.length / count).floor().clamp(0, waveform.length - 1)] / 100).clamp(
        0.06,
        1.0,
      ),
  ];
}
