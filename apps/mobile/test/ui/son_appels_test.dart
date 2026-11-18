import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 9.3 — son des appels : flux d'appel pendant l'appel (touches de volume), écouteurs
/// et Bluetooth choisis d'office et suivis en cours d'appel ; réglage d'envoi des vocaux.
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

Future<TestDeps> _start(WidgetTester tester, {TestDeps? deps}) async {
  final d = deps ?? _deps();
  await d.messaging.startDirectConversation('u2');
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> _tick(WidgetTester tester, [int ms = 500]) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _connect(WidgetTester tester, TestDeps deps) async {
  final id = deps.calls.calls.keys.single;
  deps.calls
    ..peerAnswer(id)
    ..peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b'});
  await _tick(tester);
  deps.callEngine.onState!(CallMediaState.connected);
  await _tick(tester);
}

void main() {
  testWidgets('appel : flux d’appel pendant l’appel, rendu après', (tester) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(deps.callSystem.log, contains('audio:true'));
    await _connect(tester, deps);
    expect(deps.callEngine.selected, AudioRoute.earpiece, reason: 'appel audio : écouteur');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1500);
    expect(deps.callSystem.log.where((l) => l.startsWith('audio:')), ['audio:true', 'audio:false']);
  });

  testWidgets('écouteurs Bluetooth déjà connectés : le son y passe d’office', (tester) async {
    final deps = await _start(tester);
    deps.callEngine.routes = const [AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.bluetooth];
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.bluetooth);
    expect(deps.callEngine.speaker, isFalse);
  });

  testWidgets('écouteurs branchés puis retirés en cours d’appel : bascule automatique', (
    tester,
  ) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    await _connect(tester, deps);
    expect(deps.callEngine.selected, AudioRoute.earpiece);

    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.wired]);
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.wired, reason: 'casque branché');

    deps.callEngine.plug(const [
      AudioRoute.earpiece,
      AudioRoute.speaker,
      AudioRoute.wired,
      AudioRoute.bluetooth,
    ]);
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.bluetooth, reason: 'AirPods connectés');

    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.wired]);
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.wired, reason: 'Bluetooth coupé : le casque');

    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker]);
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.earpiece, reason: 'casque retiré');

    // Haut-parleur choisi à la main : il reste tant qu'aucun accessoire n'arrive.
    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker]);
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.speaker')));
    await _tick(tester);
    expect(deps.callEngine.speaker, isTrue);
    // Correctif du 18/11 : haut-parleur imposé aussi côté Android (et volume remonté).
    expect(deps.callSystem.log.where((l) => l.startsWith('route:')).last, 'route:speaker');
    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker]);
    await _tick(tester);
    expect(deps.callEngine.speaker, isTrue);
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1500);
  });

  testWidgets('appel vidéo avec écouteurs : les écouteurs, pas le haut-parleur', (tester) async {
    final deps = await _start(tester);
    deps.callEngine.routes = const [AudioRoute.earpiece, AudioRoute.speaker, AudioRoute.wired];
    await tester.tap(find.byKey(const Key('chat.video')));
    await _tick(tester);
    expect(deps.callEngine.selected, AudioRoute.wired);
    expect(deps.callEngine.speaker, isFalse);
    deps.callEngine.plug(const [AudioRoute.earpiece, AudioRoute.speaker]);
    await _tick(tester);
    expect(deps.callEngine.speaker, isTrue, reason: 'casque retiré en vidéo : haut-parleur');
  });

  testWidgets('réglage « Écouter les vocaux avant de les envoyer »', (tester) async {
    final deps = _deps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
    );
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.chats');
    await scrollToKey(tester, 'settings.voice_listen_first');
    expect(find.text('En levant le doigt, le vocal part tout de suite.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.voice_listen_first')));
    await tester.pumpAndSettle();
    expect(deps.flags.listenFirst, isTrue);
    expect(
      find.text('En levant le doigt, vous écoutez le vocal, puis vous l’envoyez ou le supprimez.'),
      findsOneWidget,
    );
  });
}
