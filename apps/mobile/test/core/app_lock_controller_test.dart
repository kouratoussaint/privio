import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/state/app_lock_providers.dart';
import 'package:privio/state/data_providers.dart';

import '../helpers/fakes.dart';

/// Lot 4.2 — règles du verrouillage (sans écran) et formats.
void main() {
  Future<(TestDeps, DateTime Function(), void Function(Duration))> setup() async {
    var now = DateTime(2026, 11, 13, 9);
    final d = TestDeps()..clock = () => now;
    final salt = List<int>.filled(16, 7);
    d.lockStore.config = AppLockConfig(
      enabled: true,
      delaySeconds: 0,
      salt: base64Encode(salt),
      hash: await const FastPinHasher().hash('258014', salt, 1),
    );
    return (d, () => now, (Duration x) => now = now.add(x));
  }

  test('attente doublée à chaque erreur au-delà de 5, plafonnée à 15 min', () async {
    final (d, now, advance) = await setup();
    final c = d.container();
    final lock = c.read(appLockProvider.notifier);
    await c.read(appLockProvider.future);
    final waits = <Duration>[];
    for (var i = 0; i < 12; i++) {
      final r = await lock.unlock('000000');
      if (r is MustWait) {
        waits.add(r.until.difference(now()));
        advance(r.until.difference(now()));
      }
    }
    expect(waits.take(4), const [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 4),
    ]);
    expect(waits.last, const Duration(minutes: 15));
    expect(await lock.unlock('258014'), isA<Unlocked>());
    expect(d.lockStore.config.failures, 0);
  });

  test('appareil photo ou galerie\u202F: pas de reverrouillage au retour', () async {
    final (d, _, advance) = await setup();
    final c = d.container();
    final lock = c.read(appLockProvider.notifier);
    await c.read(appLockProvider.future);
    await lock.unlock('258014');
    await lock.runExternal(() async {
      lock.onBackground();
      advance(const Duration(minutes: 3));
      lock.onForeground();
    });
    expect(c.read(appLockProvider).value!.locked, isFalse);
    // Sortie ordinaire (délai « immédiatement ») : verrouillé.
    lock.onBackground();
    advance(const Duration(seconds: 1));
    lock.onForeground();
    expect(c.read(appLockProvider).value!.locked, isTrue);
  });

  test('formats', () {
    expect(formatBytes(512), '512 o');
    expect(formatBytes(150 * 1024), '150 Ko');
    expect(formatBytes((1.5 * 1024 * 1024).round()), '1,5 Mo');
    expect(formatWait(const Duration(seconds: 30)), '30 s');
    expect(formatWait(const Duration(seconds: 90)), '2 min');
    expect(monthKey(DateTime(2026, 1, 5)), '2026-01');
  });
}
