import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/media/waveform.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/domain/models/messaging.dart';

/// Lot 4.5 : profil sonore des vocaux.
void main() {
  test('dBFS → 0..1 : silence à 0, voix forte proche de 1', () {
    expect(levelFromDb(-160), 0);
    expect(levelFromDb(-50), 0);
    expect(levelFromDb(0), 1);
    expect(levelFromDb(-25), closeTo(0.5, 0.01));
    expect(levelFromDb(double.nan), 0);
    expect(levelFromDb(double.negativeInfinity), 0);
  });

  test('profil : 40 valeurs de 0 à 100, le plus fort passage vaut 100', () {
    final levels = [for (var i = 0; i < 300; i++) (i % 10) / 20];
    final w = buildWaveform(levels)!;
    expect(w, hasLength(kWaveformBars));
    expect(w.every((v) => v >= 0 && v <= 100), isTrue);
    expect(w.reduce((a, b) => a > b ? a : b), 100);
  });

  test('enregistrement très court (moins de mesures que de barres) : profil complet', () {
    final w = buildWaveform([0.2, 0.9, 0.4])!;
    expect(w, hasLength(kWaveformBars));
    expect(w.contains(100), isTrue);
  });

  test('aucune mesure : pas de profil ; silence : profil plat à 0', () {
    expect(buildWaveform(const []), isNull);
    expect(buildWaveform(List.filled(50, 0.0)), everyElement(0));
  });

  test('affichage : nombre de barres demandé, jamais invisible ; ancien vocal neutre', () {
    final bars = displayBars([0, 50, 100, 25, 0, 0, 0, 80], 24);
    expect(bars, hasLength(24));
    expect(bars.every((b) => b >= 0.06 && b <= 1), isTrue);
    final neutral = displayBars(null, 30);
    expect(neutral, hasLength(30));
    expect(neutral.every((b) => b > 0 && b < 1), isTrue);
  });

  test('le profil survit au cache chiffré (message et envoi en attente)', () {
    final now = DateTime.utc(2026, 11, 13);
    final m = ChatMessage(
      id: 'v1',
      kind: 'voice',
      senderId: 'u1',
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      updatedAt: now,
      mediaPath: 'c/v1.m4a',
      durationMs: 4000,
      waveform: const [0, 50, 100, 20, 0, 0, 10, 90],
    );
    expect(ChatMessage.fromJson(m.toJson()).waveform, m.waveform);
    final o = OutboxItem(
      clientId: 'c1',
      conversationId: 'c',
      body: '',
      createdAt: now,
      kind: 'voice',
      durationMs: 4000,
      waveform: const [1, 2, 3, 4, 5, 6, 7, 8],
    );
    expect(OutboxItem.fromJson(o.toJson()).waveform, o.waveform);
    expect(o.copyWith(failed: true).waveform, o.waveform);
  });
}
