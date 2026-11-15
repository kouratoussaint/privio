import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/call_background.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/services/call_system.dart';
import 'package:privio/data/services/device_services.dart' show NetKind;
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 9.1b — appel reçu Privio fermé ou en arrière-plan (écran d'appel du téléphone),
/// appel maintenu écran éteint, sortie du son, reconnexion, « Connexion faible ».
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

String _status(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(const Key('call.status')), matching: find.byType(Text)).first,
    )
    .data!;

/// Appel sortant établi (Bob a décroché, liaison prête).
Future<String> _connectedOutgoing(WidgetTester tester, TestDeps deps) async {
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

const _uuid = '0b12aacb-775a-41de-9cbe-46e0a9e99469';

void main() {
  group('message de réveil (Privio fermé)', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    late List<CallKitParams> shown;
    late List<String> ended;
    Future<void> handle(Map<String, dynamic> data) => handleCallPush(
      data,
      show: (p) async => shown.add(p),
      end: (id) async => ended.add(id),
      now: () => now,
    );
    setUp(() {
      shown = [];
      ended = [];
    });

    test('appel entrant : écran d’appel du téléphone, sans nom ni numéro', () async {
      await handle({
        'type': 'call',
        'call_id': _uuid,
        'conversation_id': 'c',
        'created_at': now.subtract(const Duration(seconds: 5)).toIso8601String(),
      });
      final p = shown.single;
      expect(p.id, _uuid);
      expect(p.nameCaller, 'Appel Privio entrant');
      expect(p.handle, isEmpty);
      expect(p.avatar, isNull);
      expect(p.duration, 40000, reason: 'sonne jusqu’à l’expiration côté serveur');
      expect(p.android!.isShowFullLockedScreen, isTrue);
      expect(p.android!.textAccept, 'Décrocher');
      expect(
        p.missedCallNotification!.showNotification,
        isFalse,
        reason: '« Appel manqué » vient du serveur, sans nom',
      );
    });

    test('message trop ancien : rien ne sonne ; fin d’appel : la sonnerie s’arrête', () async {
      await handle({
        'type': 'call',
        'call_id': _uuid,
        'created_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
      });
      expect(shown, isEmpty);
      await handle({'type': 'call_end', 'call_id': _uuid});
      expect(ended, [_uuid]);
      await handle({'type': 'message', 'conversation_id': _uuid});
      await handle({'type': 'call', 'call_id': 'pas-un-identifiant'});
      expect(shown, isEmpty);
      expect(ended, [_uuid]);
    });

    test('actions de l’écran d’appel du téléphone', () {
      const p = CallKitParams(id: _uuid);
      expect(
        callSystemEventOf(const CallEventActionCallAccept(p))!.action,
        CallSystemAction.accept,
      );
      expect(
        callSystemEventOf(const CallEventActionCallDecline(p))!.action,
        CallSystemAction.decline,
      );
      expect(callSystemEventOf(const CallEventActionCallEnded(p))!.action, CallSystemAction.end);
      expect(callSystemEventOf(const CallEventActionCallTimeout(_uuid)), isNull);
      expect(callSystemEventOf(const CallEventActionCallAccept(CallKitParams(id: 'x'))), isNull);
    });
  });

  testWidgets('Privio en arrière-plan : l’écran du téléphone sonne, puis Privio reprend', (
    tester,
  ) async {
    final deps = await _start(tester);
    deps.foreground = false;
    final c = deps.calls.incoming();
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    expect(deps.callSystem.log, contains('show:${c.id}'));
    expect(deps.tones.log, isNot(contains('ring')), reason: 'une seule sonnerie');

    // Retour dans Privio : son propre écran prend le relais.
    deps.foreground = true;
    deps.realtime.emit('', event: 'resume');
    await _tick(tester);
    expect(deps.callSystem.log, contains('hide:${c.id}'));
    expect(deps.tones.log, contains('ring'));
    await tester.tap(find.byKey(const Key('call.decline')));
    await _tick(tester, 1000);
    expect(deps.calls.declined, [c.id]);
    expect(deps.callSystem.log.last, 'end:${c.id}');
  });

  testWidgets('décroché sur l’écran du téléphone, Privio ouvert ensuite', (tester) async {
    final deps = _deps();
    final c = deps.calls.incoming();
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x'});
    deps.callSystem.accepted = c.id;
    await _start(tester, deps: deps);
    await _tick(tester);
    expect(deps.calls.calls[c.id]!.status, 'accepted', reason: 'sans saisir le code Privio');
    expect(deps.callEngine.log, containsAll(['open', 'accept:x']));
    expect(_status(tester), 'Connexion…');
    // Par-dessus l'écran de verrouillage, écran éteint à l'oreille.
    expect(deps.callSystem.log, containsAll(['overLock:true', 'proximity:true']));
    expect(deps.callSystem.log, contains('activate:${c.id}'));
    deps.callEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    expect(deps.callSystem.log, contains('connected:${c.id}'));

    // Raccroché depuis la notification d'appel en cours.
    deps.callSystem.emit(CallSystemAction.end, c.id);
    await _tick(tester, 200);
    expect(deps.calls.ended, [c.id]);
    expect(deps.callSystem.log, containsAll(['overLock:false', 'proximity:false']));
    await _tick(tester, 800);
  });

  testWidgets('actions de l’écran du téléphone, Privio en arrière-plan', (tester) async {
    final deps = await _start(tester);
    deps.foreground = false;
    final c = deps.calls.incoming();
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    deps.callSystem.emit(CallSystemAction.decline, c.id);
    await _tick(tester, 1000);
    expect(deps.calls.declined, [c.id]);

    // Appel dont Privio n'avait pas encore connaissance : décroché depuis le téléphone.
    final c2 = deps.calls.incoming();
    deps.callSystem.emit(CallSystemAction.accept, c2.id);
    await _tick(tester);
    expect(deps.calls.calls[c2.id]!.status, 'accepted');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('réduire l’appel : l’écran de verrouillage revient, pas de capteur', (tester) async {
    final deps = await _start(tester, openBob: true);
    final id = await _connectedOutgoing(tester, deps);
    expect(deps.callSystem.log, containsAll(['activate:$id', 'connected:$id', 'overLock:true']));
    deps.callSystem.log.clear();
    await tester.tap(find.byKey(const Key('call.minimize')));
    await _tick(tester);
    expect(deps.callSystem.log, containsAll(['overLock:false', 'proximity:false']));
    await tester.tap(find.byKey(const Key('call.bar')));
    await _tick(tester);
    expect(deps.callSystem.log, containsAll(['overLock:true', 'proximity:true']));
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('sortie du son : haut-parleur, Bluetooth, casque', (tester) async {
    final deps = await _start(tester, openBob: true);
    await _connectedOutgoing(tester, deps);
    expect(deps.permissions.nearbyRequests, 1);
    // Sans appareil branché : un geste = haut-parleur.
    await tester.tap(find.byKey(const Key('call.speaker')));
    await _tick(tester);
    expect(deps.callEngine.speaker, isTrue);
    expect(deps.callSystem.log.last, 'proximity:false', reason: 'pas à l’oreille');

    // Écouteurs Bluetooth connectés : choix de la sortie.
    deps.callEngine.routes = AudioRoute.values;
    await tester.tap(find.byKey(const Key('call.speaker')));
    await tester.pumpAndSettle();
    expect(find.text('Sortie du son'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.route.bluetooth')));
    await tester.pumpAndSettle();
    expect(deps.callEngine.selected, AudioRoute.bluetooth);
    expect(deps.callEngine.speaker, isFalse);
    expect(find.text('Bluetooth'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.speaker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call.route.earpiece')));
    await tester.pumpAndSettle();
    expect(deps.callEngine.selected, AudioRoute.earpiece);
    expect(deps.callSystem.log.last, 'proximity:true');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('connexion faible, coupure, nouveau réseau : l’appel continue', (tester) async {
    final deps = await _start(tester, openBob: true);
    final id = await _connectedOutgoing(tester, deps);

    deps.callEngine.onQuality!(true);
    await _tick(tester);
    expect(find.byKey(const Key('call.weak')), findsOneWidget);
    expect(find.text('Connexion faible'), findsOneWidget);
    deps.callEngine.onQuality!(false);
    await _tick(tester);
    expect(find.byKey(const Key('call.weak')), findsNothing);

    // Passage du Wi-Fi aux données : l'appelant renégocie la liaison.
    deps.network.set(NetKind.wifi);
    await _tick(tester, 800);
    expect(deps.callEngine.log, contains('restart'));
    expect(deps.calls.sent.where((s) => s.$2 == 'offer').length, 2);
    expect(deps.calls.ended, isEmpty);

    // Coupure : « Connexion faible, reconnexion… », puis retour.
    deps.callEngine.onState!(CallMediaState.failed);
    await _tick(tester);
    expect(_status(tester), 'Connexion faible, reconnexion…');
    expect(deps.calls.ended, isEmpty, reason: 'pas raccroché au premier incident');
    deps.calls.peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b2'});
    deps.callEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    expect(deps.callEngine.log, contains('answer:b2'));
    expect(_status(tester), isNot(contains('reconnexion')));
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('appelé : nouvelle offre en cours d’appel → nouvelle réponse', (tester) async {
    final deps = await _start(tester);
    final c = deps.calls.incoming();
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x'});
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.accept')));
    await _tick(tester);
    deps.callEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x2'});
    await _tick(tester, 800);
    expect(deps.callEngine.log, contains('accept:x2'));
    expect(deps.calls.sent.where((s) => s.$2 == 'answer').length, 2);
    expect(deps.callEngine.log, isNot(contains('restart')), reason: 'seul l’appelant relance');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('coupure trop longue : l’appel s’arrête', (tester) async {
    final deps = _deps();
    await _start(tester, deps: deps, openBob: true);
    await _connectedOutgoing(tester, deps);
    deps.callEngine.onState!(CallMediaState.reconnecting);
    await _tick(tester);
    expect(_status(tester), 'Connexion faible, reconnexion…');
    await _tick(tester, 2500);
    expect(deps.callEngine.log, contains('restart'));
    await tester.pump(const Duration(seconds: 27));
    await _tick(tester, 200);
    expect(deps.calls.ended, hasLength(1));
    expect(_status(tester), 'Appel interrompu');
    await _tick(tester, 1000);
  });

  testWidgets('Android 14 : affichage plein écran des appels proposé une fois', (tester) async {
    final deps = _deps()..callSystem.allowed = false;
    await _start(tester, deps: deps);
    expect(find.byKey(const Key('call.fullscreen')), findsOneWidget);
    expect(find.text('Appels avec le téléphone verrouillé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.fullscreen.allow')));
    await tester.pumpAndSettle();
    expect(deps.callSystem.log, ['settings']);
    expect(deps.flags.fullScreenAsked, isTrue);
  });
}
