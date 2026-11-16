import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 10.2 — Discussions cachées : masquer (code Privio créé au besoin, sans verrouiller
/// Privio), appui long sur le logo + code, liste refermée, sonnerie neutre.
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

Future<TestDeps> _start(WidgetTester tester, {bool hidden = false, bool pin = false}) async {
  final deps = _deps();
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Rendez-vous ce soir');
  if (hidden) deps.messaging.secret.add('conv-bob');
  if (pin) {
    // Code Privio existant, verrouillage à l'ouverture désactivé.
    final salt = List<int>.generate(16, (i) => i);
    deps.lockStore.config = AppLockConfig(
      salt: base64Encode(salt),
      hash: await const FastPinHasher().hash(_pin, salt, 1),
    );
  }
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openHidden(WidgetTester tester, String pin) async {
  await tester.longPress(find.byKey(const Key('brand.logo')));
  await tester.pumpAndSettle();
  await _type(tester, pin);
}

void main() {
  testWidgets('masquer : code Privio créé, sans verrouiller Privio ; disparaît de la liste', (
    tester,
  ) async {
    final deps = await _start(tester);
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await tester.longPress(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv.secret')));
    await tester.pumpAndSettle();
    // Pas encore de code : on le crée (deux fois).
    expect(
      find.text(
        'Ce code ouvrira vos discussions cachées. Il ne verrouille pas Privio à l’ouverture.',
      ),
      findsOneWidget,
    );
    await _type(tester, _pin);
    await _type(tester, _pin);
    expect(deps.messaging.secret, {'conv-bob'});
    expect(deps.lockStore.config.hash, isNotNull);
    expect(deps.lockStore.config.enabled, isFalse, reason: 'B : pas de verrouillage imposé');
    expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);
    expect(
      find.text('Discussion masquée. Appui long sur le logo Privio pour la retrouver.'),
      findsOneWidget,
    );
  });

  testWidgets('appui long sur le logo, code, discussion ouverte ; refermée en sortant', (
    tester,
  ) async {
    final deps = await _start(tester, hidden: true, pin: true);
    expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);

    // Mauvais code : rien ne s'ouvre.
    await _openHidden(tester, '111222');
    expect(find.text('Code incorrect.'), findsOneWidget);
    expect(find.byKey(const Key('hidden.list')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _openHidden(tester, _pin);
    expect(find.byKey(const Key('hidden.list')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(find.text('Rendez-vous ce soir'), findsOneWidget);

    // Privio passe en arrière-plan : tout se referme, retour à Discussions.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Rendez-vous ce soir'), findsNothing);
    expect(find.byKey(const Key('hidden.list')), findsNothing);
    expect(find.byKey(const Key('brand.logo')), findsOneWidget);

    // Ne plus masquer.
    await _openHidden(tester, _pin);
    await tester.longPress(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv.secret')));
    await tester.pumpAndSettle();
    expect(deps.messaging.secret, isEmpty);
    expect(find.byKey(const Key('hidden.empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hidden.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
  });

  testWidgets('sonnerie neutre pour une discussion cachée', (tester) async {
    final deps = await _start(tester, hidden: true);
    final c = deps.calls.incoming();
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x'});
    deps.realtime.emitCall('conv-bob', c.id);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('call.name'))).data, isNot(contains('Bob')));
  });
}
