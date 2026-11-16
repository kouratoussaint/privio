import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/call_background.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/services/device_services.dart' show NetKind;
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';

/// Lot 9.2 — appels vidéo à deux (ADR-038).
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

Future<TestDeps> _start(WidgetTester tester, {TestDeps? deps, bool openBob = false}) async {
  final d = deps ?? _deps();
  await d.messaging.startDirectConversation('u2');
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  if (openBob) {
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
  }
  return d;
}

Future<void> _tick(WidgetTester tester, [int ms = 500]) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

/// Appel audio établi, appelé par A (moi).
Future<String> _audioCall(WidgetTester tester, TestDeps deps) async {
  await tester.tap(find.byKey(const Key('chat.call')));
  await _tick(tester);
  final id = deps.calls.calls.keys.last;
  deps.calls
    ..peerAnswer(id)
    ..peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b'});
  await _tick(tester);
  deps.callEngine.onState!(CallMediaState.connected);
  await _tick(tester);
  return id;
}

Future<void> _hangUp(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('call.hangup')));
  await _tick(tester, 1000);
}

void main() {
  test('trace d’un appel vidéo dans la discussion', () {
    ChatMessage m(String v, {String sender = 'u1'}) => ChatMessage(
      id: 'x',
      senderId: sender,
      kind: 'system',
      body: '{"e":"call","k":"video","v":"$v"}',
      sentAt: DateTime(2026, 11, 15),
      expiresAt: DateTime(2026, 11, 18),
      updatedAt: DateTime(2026, 11, 15),
    );
    expect(groupEventText(m('ended:65'), me: 'u1'), 'Appel vidéo sortant · 01:05');
    expect(groupEventText(m('ended:65', sender: 'u2'), me: 'u1'), 'Appel vidéo entrant · 01:05');
    expect(groupEventText(m('missed'), me: 'u1'), 'Appel vidéo sans réponse');
    expect(groupEventText(m('missed', sender: 'u2'), me: 'u1'), 'Appel vidéo manqué');
    expect(groupEventText(m('declined'), me: 'u1'), 'Appel vidéo refusé');
    expect(groupEventText(m('cancelled'), me: 'u1'), 'Appel vidéo annulé');
  });

  test('message de réveil d’un appel vidéo : annoncé sans nom', () async {
    final shown = <CallKitParams>[];
    await handleCallPush(
      {'type': 'call', 'call_id': '0b12aacb-775a-41de-9cbe-46e0a9e99469', 'kind': 'video'},
      show: (p) async => shown.add(p),
      end: (_) async {},
    );
    expect(shown.single.nameCaller, 'Appel vidéo Privio entrant');
    expect(shown.single.type, 1);
  });

  testWidgets('appel vidéo depuis la discussion : caméra allumée, haut-parleur', (tester) async {
    final deps = await _start(tester, openBob: true);
    expect(find.byKey(const Key('chat.video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat.video')));
    await _tick(tester);
    final id = deps.calls.calls.keys.last;
    expect(deps.calls.calls[id]!.kind, 'video');
    expect(deps.permissions.cameraRequests, 1);
    expect(deps.callEngine.log, containsAllInOrder(['open', 'offer', 'camera:true']));
    expect(deps.callEngine.speaker, isTrue);
    expect(find.byKey(const Key('call.local')), findsOneWidget);
    expect(find.byKey(const Key('fake.local.true')), findsOneWidget, reason: 'miroir (avant)');
    expect(deps.callSystem.log, contains('proximity:false'));

    // Changer de caméra : plus de miroir.
    await tester.tap(find.byKey(const Key('call.flip')));
    await _tick(tester);
    expect(deps.callEngine.flips, 1);
    expect(find.byKey(const Key('fake.local.false')), findsOneWidget);

    // Bob décroche et allume sa caméra : son image en plein écran.
    deps.calls
      ..peerAnswer(id)
      ..peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b'});
    await _tick(tester);
    deps.callEngine.onState!(CallMediaState.connected);
    deps.callEngine.onPeerCamera!(true);
    await _tick(tester);
    expect(find.byKey(const Key('call.remote')), findsOneWidget);
    expect(deps.callSystem.log, contains('pip:true'));
    await _hangUp(tester);
    expect(deps.callSystem.log.last, isNot('pip:true'));
    expect(deps.callSystem.log, contains('pip:false'));
  });

  testWidgets('appel vidéo reçu : on décroche caméra coupée (décision C)', (tester) async {
    final deps = await _start(tester);
    final c = deps.calls.incoming(kind: 'video');
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x'});
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    expect(find.text('Appel vidéo entrant'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.accept')));
    await _tick(tester);
    expect(deps.calls.calls[c.id]!.status, 'accepted');
    expect(deps.callEngine.log, isNot(contains('camera:true')));
    expect(deps.permissions.cameraRequests, 0, reason: 'caméra demandée seulement si on l’allume');
    expect(deps.callEngine.speaker, isTrue);
    expect(find.byKey(const Key('call.local')), findsNothing);
    deps.callEngine.onState!(CallMediaState.connected);
    deps.callEngine.onPeerCamera!(true);
    await _tick(tester);
    expect(find.byKey(const Key('call.remote')), findsOneWidget);
    // Je l'allume quand je veux.
    await tester.tap(find.byKey(const Key('call.camera')));
    await _tick(tester);
    expect(deps.callEngine.camera, isTrue);
    expect(find.byKey(const Key('call.local')), findsOneWidget);
    await _hangUp(tester);
  });

  testWidgets('appel audio : allumer sa caméra sans demande (décision A)', (tester) async {
    final deps = await _start(tester, openBob: true);
    await _audioCall(tester, deps);
    expect(deps.callEngine.speaker, isFalse);
    expect(deps.callSystem.log, contains('proximity:true'));

    await tester.tap(find.byKey(const Key('call.camera')));
    await _tick(tester);
    expect(deps.callEngine.camera, isTrue);
    expect(deps.callEngine.speaker, isTrue, reason: 'on regarde l’écran');
    expect(deps.callSystem.log, containsAll(['proximity:false', 'pip:true']));

    await tester.tap(find.byKey(const Key('call.camera')));
    await _tick(tester);
    expect(deps.callEngine.camera, isFalse);
    expect(find.byKey(const Key('call.local')), findsNothing);
    expect(deps.callSystem.log.last, 'pip:false');
    await _hangUp(tester);
  });

  testWidgets('caméra refusée : message, l’appel continue', (tester) async {
    final deps = _deps()..permissions.cameraGranted = false;
    await _start(tester, deps: deps, openBob: true);
    await _audioCall(tester, deps);
    await tester.tap(find.byKey(const Key('call.camera')));
    await _tick(tester);
    expect(deps.callEngine.camera, isFalse);
    expect(find.byKey(const Key('call.camera.denied')), findsOneWidget);
    await _tick(tester, 4500);
    expect(find.byKey(const Key('call.camera.denied')), findsNothing);
    await _hangUp(tester);
  });

  testWidgets('image réduite en données mobiles, meilleure en Wi-Fi', (tester) async {
    final deps = await _start(tester, openBob: true);
    await _audioCall(tester, deps);
    expect(deps.callEngine.economy, isTrue, reason: 'données mobiles');
    deps.network.set(NetKind.wifi);
    await _tick(tester, 800);
    expect(deps.callEngine.economy, isFalse);
    deps.network.set(NetKind.mobile);
    await _tick(tester, 800);
    expect(deps.callEngine.economy, isTrue);
    await _hangUp(tester);
  });

  testWidgets('Mode éco (lot 10.3) : image réduite même en Wi-Fi ; données de l’appel comptées', (
    tester,
  ) async {
    final d = _deps()..flags.eco = true;
    final deps = await _start(tester, deps: d, openBob: true);
    await _audioCall(tester, deps);
    deps.network.set(NetKind.wifi);
    await _tick(tester, 800);
    expect(deps.callEngine.economy, isTrue);
    deps.callEngine.traffic = 512 * 1024;
    await _hangUp(tester);
    await _tick(tester, 2500);
    expect(deps.flags.usage.keys.any((k) => k.endsWith(':in:call')), isTrue);
  });

  testWidgets('petite fenêtre (Privio quitté) : l’image seule, même réduit', (tester) async {
    final deps = await _start(tester, openBob: true);
    await _audioCall(tester, deps);
    deps.callEngine.onPeerCamera!(true);
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.minimize')));
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsNothing);

    deps.callSystem.emitPip(true);
    await _tick(tester);
    expect(find.byKey(const Key('call.pip')), findsOneWidget);
    expect(find.byKey(const Key('fake.remote')), findsOneWidget);
    expect(find.byKey(const Key('call.hangup')), findsNothing);

    deps.callSystem.emitPip(false);
    await _tick(tester);
    expect(find.byKey(const Key('call.pip')), findsNothing);
    await tester.tap(find.byKey(const Key('call.bar')));
    await _tick(tester);
    await _hangUp(tester);
  });
}
