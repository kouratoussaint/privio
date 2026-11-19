import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show StatsReport;
import 'package:privio/app.dart';
import 'package:privio/data/services/call_audio.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 9.3c (ADR-056) — volume des appels : niveaux du son mesurés et notés au journal
/// technique, mode « appel » et sortie réimposés à la connexion, tonalité d'attente sans
/// quitter le mode « appel », aucun son de Privio pendant un appel.
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

Future<TestDeps> _start(WidgetTester tester) async {
  final d = _deps();
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

StatsReport _r(String type, double energy, double duration) => StatsReport('x', type, 0, {
  'kind': 'audio',
  'totalAudioEnergy': energy,
  'totalSamplesDuration': duration,
});

void main() {
  test('niveaux moyens calculés depuis les statistiques de la liaison', () {
    final l = audioLevelsFromStats([
      _r('inbound-rtp', 0.01, 1), // moyenne 0,01 → −20 dB
      _r('media-source', 0.001, 1), // → −30 dB
      StatsReport('v', 'inbound-rtp', 0, {'kind': 'video', 'totalAudioEnergy': 9}),
    ]);
    expect(l.receivedDb!.round(), -20);
    expect(l.sentDb!.round(), -30);
    expect(audioLevelsFromStats(const []).receivedDb, isNull, reason: 'aucun son : inconnu');
  });

  testWidgets('appel : sortie réimposée à la connexion, sons coupés, son noté au journal', (
    tester,
  ) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(deps.tones.log, contains('ringback'), reason: 'appel audio : tonalité à l’écouteur');
    await _connect(tester, deps);
    expect(
      deps.callSystem.log.where((l) => l.startsWith('route:')),
      contains('route:earpiece'),
      reason: 'mode « appel » et sortie réimposés une fois la voix établie',
    );
    expect(CallAudioGate.active, isTrue, reason: 'aucun son de Privio pendant l’appel');

    await tester.tap(find.byKey(const Key('call.speaker')));
    await _tick(tester, 3500); // relevé de l'état du son 3 s après le changement
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1500);

    expect(CallAudioGate.active, isFalse);
    final line = deps.techLog.entries.lastWhere((e) => e.contains('Son de l’appel'));
    expect(line, contains('sortie choisie haut-parleur'));
    expect(line, contains('son reçu -24 dB, envoyé -30 dB'));
    expect(line, contains('mode communication, sortie réelle haut-parleur'));
    expect(line, contains('volume d’appel 13/15'));
    expect(line, contains('traitement du son : Privio'));
    expect(line, isNot(contains('Bob')), reason: 'aucun nom');
  });

  testWidgets('appel vidéo : tonalité d’attente au haut-parleur, en mode « appel »', (
    tester,
  ) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.video')));
    await _tick(tester);
    expect(deps.tones.log, contains('ringback:speaker'));
  });

  testWidgets('appel jamais établi : rien au journal', (tester) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1500);
    expect(deps.techLog.entries.where((e) => e.contains('Son de l’appel')), isEmpty);
  });
}
