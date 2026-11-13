import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 4.2 — verrouillage de l'application (SEC-004), via les écrans réels.
const _pin = '258014';

TestDeps _deps() =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

/// Verrouillage déjà actif (comme après un redémarrage).
Future<TestDeps> _lockedDeps({int delay = 60, bool biometrics = false}) async {
  final d = _deps();
  final salt = List<int>.generate(16, (i) => i);
  d.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: delay,
    biometrics: biometrics,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  return d;
}

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Message secret');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

const _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('activer : code à 6 chiffres, refus des codes trop simples, confirmation', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.lock')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Désactivé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.lock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lock.enabled')));
    await tester.pumpAndSettle();

    await _type(tester, '111111');
    expect(find.textContaining('trop simple'), findsOneWidget);
    await _type(tester, '123456');
    expect(find.textContaining('trop simple'), findsOneWidget);

    await _type(tester, _pin);
    expect(find.text('Confirmez le code'), findsOneWidget);
    await _type(tester, '258015');
    expect(find.textContaining('ne correspondent pas'), findsOneWidget);
    await _type(tester, _pin);
    await _type(tester, _pin);
    expect(find.text('Verrouillage activé.'), findsOneWidget);

    final c = deps.lockStore.config;
    expect(c.enabled, isTrue);
    expect(c.hash, isNotNull);
    expect(jsonEncode(c.toJson()).contains(_pin), isFalse, reason: 'le code n\'est jamais gardé');
    expect(find.byKey(const Key('lock.delay')), findsOneWidget);
    expect(find.text('Après 1 minute'), findsOneWidget);
  });

  testWidgets('au démarrage : contenu masqué jusqu\'au bon code', (tester) async {
    final deps = await _lockedDeps();
    await _start(tester, deps);
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);
    expect(find.text('Message secret'), findsNothing);
    expect(find.text('Discussions'), findsNothing);

    await _type(tester, '000001');
    expect(find.text('Code incorrect.'), findsOneWidget);
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);

    await _type(tester, _pin);
    expect(find.byKey(const Key('lock.screen')), findsNothing);
    expect(find.text('Message secret'), findsOneWidget);
    expect(deps.lockStore.config.failures, 0);
  });

  testWidgets('5 erreurs : attente imposée, gardée après redémarrage, puis nouvel essai', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 13, 10);
    final deps = await _lockedDeps();
    deps.clock = () => now;
    await _start(tester, deps);
    for (var i = 0; i < 4; i++) {
      await _type(tester, '000001');
    }
    expect(find.textContaining('Encore 1 essai avant une attente'), findsOneWidget);
    await _type(tester, '000001');
    expect(find.textContaining('Trop d\'essais. Réessayez dans 30 s'), findsOneWidget);
    expect(deps.lockStore.config.retryAt, now.add(const Duration(seconds: 30)));

    // Pavé désactivé pendant l'attente : même le bon code n'est pas essayé.
    await _type(tester, _pin);
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);

    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    await _type(tester, _pin);
    expect(find.byKey(const Key('lock.screen')), findsNothing);
  });

  testWidgets('retour au premier plan : reverrouillé seulement après le délai', (tester) async {
    var now = DateTime(2026, 11, 13, 10);
    final deps = await _lockedDeps();
    deps.clock = () => now;
    await _start(tester, deps);
    await _type(tester, _pin);
    expect(find.byKey(const Key('lock.screen')), findsNothing);

    // 30 s en arrière-plan (délai : 1 min) : pas de code.
    await _lifecycle(tester, _toBackground);
    now = now.add(const Duration(seconds: 30));
    await _lifecycle(tester, _toForeground);
    expect(find.byKey(const Key('lock.screen')), findsNothing);

    // 2 min : code demandé.
    await _lifecycle(tester, _toBackground);
    now = now.add(const Duration(minutes: 2));
    await _lifecycle(tester, _toForeground);
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);
    expect(find.text('Message secret'), findsNothing);
  });

  testWidgets('empreinte : proposée d\'office, et le code reste accepté si elle échoue', (
    tester,
  ) async {
    final deps = await _lockedDeps(biometrics: true);
    deps.biometrics
      ..isAvailable = true
      ..accept = false;
    await _start(tester, deps);
    expect(deps.biometrics.prompts, 1, reason: 'demandée à l\'affichage');
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);

    deps.biometrics.accept = true;
    await tester.tap(find.byKey(const Key('lock.biometrics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock.screen')), findsNothing);
  });

  testWidgets('code oublié : déconnexion, données du téléphone et verrouillage effacés', (
    tester,
  ) async {
    final deps = await _lockedDeps();
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('lock.forgot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock.forgot.panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lock.forgot.signout')));
    await tester.pumpAndSettle();
    expect(deps.auth.signedIn, isFalse);
    expect(deps.lockStore.config.enabled, isFalse);
    expect(find.byKey(const Key('lock.screen')), findsNothing);
  });

  testWidgets('désactiver demande le code actuel ; changer le code', (tester) async {
    final deps = await _lockedDeps();
    await _start(tester, deps);
    await _type(tester, _pin);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.lock')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('settings.lock')));
    await tester.pumpAndSettle();

    // Changer le code.
    await tester.tap(find.byKey(const Key('lock.change')));
    await tester.pumpAndSettle();
    await _type(tester, '999990');
    expect(find.text('Code incorrect.'), findsOneWidget);
    await _type(tester, _pin);
    await _type(tester, '470352');
    await _type(tester, '470352');
    expect(find.text('Code modifié.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Délai : immédiatement.
    await tester.tap(find.byKey(const Key('lock.delay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lock.delay.0')));
    await tester.pumpAndSettle();
    expect(deps.lockStore.config.delaySeconds, 0);

    // Désactiver : l'ancien code ne marche plus, le nouveau oui.
    await tester.tap(find.byKey(const Key('lock.enabled')));
    await tester.pumpAndSettle();
    await _type(tester, _pin);
    expect(find.text('Code incorrect.'), findsOneWidget);
    await _type(tester, '470352');
    expect(deps.lockStore.config.enabled, isFalse);
    expect(find.byKey(const Key('lock.delay')), findsNothing);
  });
}
