import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/audio/voice_recorder.dart' show MicPermission;
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 9.1a — appels audio à deux : appeler, recevoir, refuser, raccrocher, réduire, traces.
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

Future<TestDeps> _start(WidgetTester tester, {TestDeps? deps, bool openBob = true}) async {
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

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

/// Laisse passer quelques tours de mise à jour (interrogation toutes les 200 ms).
Future<void> _tick(WidgetTester tester, [int ms = 500]) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

String _status(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(const Key('call.status')), matching: find.byType(Text)),
    )
    .data!;

void main() {
  test('trace d’appel dans la discussion, selon le point de vue', () {
    ChatMessage m(String v, {String sender = 'u1'}) => ChatMessage(
      id: 'x',
      senderId: sender,
      kind: 'system',
      body: jsonEncode({'e': 'call', 'k': 'audio', 'v': v}),
      sentAt: DateTime(2026, 11, 15),
      expiresAt: DateTime(2026, 11, 18),
      updatedAt: DateTime(2026, 11, 15),
    );
    expect(groupEventText(m('ended:183'), me: 'u1'), 'Appel sortant · 03:03');
    expect(groupEventText(m('ended:183', sender: 'u2'), me: 'u1'), 'Appel entrant · 03:03');
    expect(groupEventText(m('missed'), me: 'u1'), 'Appel sans réponse');
    expect(groupEventText(m('missed', sender: 'u2'), me: 'u1'), 'Appel manqué');
    expect(groupEventText(m('cancelled', sender: 'u2'), me: 'u1'), 'Appel manqué');
    expect(groupEventText(m('declined'), me: 'u1'), 'Appel refusé');
  });

  testWidgets('appeler : sonnerie, réponse, liaison, micro, haut-parleur, raccrocher', (
    tester,
  ) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
    expect(_status(tester), 'Ça sonne…');
    expect(deps.tones.log, contains('ringback'));
    expect(deps.callEngine.log, ['open', 'offer']);
    final id = deps.calls.calls.keys.single;
    expect([for (final s in deps.calls.sent) s.$2], containsAll(['offer', 'ice']));

    // Bob décroche et répond.
    deps.calls
      ..peerAnswer(id)
      ..peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b'})
      ..peerSignal(id, 'ice', {'candidate': 'remote-1'});
    await _tick(tester);
    expect(_status(tester), 'Connexion…');
    expect(deps.callEngine.log, containsAll(['answer:b', 'ice:remote-1']));
    deps.callEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    expect(_status(tester), '00:00');

    await tester.tap(find.byKey(const Key('call.mute')));
    await _tick(tester);
    expect(deps.callEngine.muted, isTrue);
    expect(find.text('Micro coupé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.speaker')));
    await _tick(tester);
    expect(deps.callEngine.speaker, isTrue);

    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 200);
    expect(deps.calls.ended, [id]);
    expect(_status(tester), startsWith('Appel terminé'));
    expect(deps.callEngine.log.last, 'close');
    await _tick(tester, 800);
    expect(find.byKey(const Key('call.screen')), findsNothing);
  });

  testWidgets('recevoir : sonnerie, décrocher, réponse envoyée', (tester) async {
    final deps = await _start(tester, openBob: false);
    final c = deps.calls.incoming();
    deps.calls.peerSignal(c.id, 'offer', {'type': 'offer', 'sdp': 'x'});
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    expect(_status(tester), 'Appel entrant');
    expect(deps.tones.log, contains('ring'));
    await tester.tap(find.byKey(const Key('call.accept')));
    await _tick(tester);
    expect(deps.callEngine.log, containsAll(['open', 'accept:x']));
    expect([for (final s in deps.calls.sent) s.$2], contains('answer'));
    expect(deps.calls.calls[c.id]!.status, 'accepted');
    deps.callEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    expect(_status(tester), '00:00');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
    expect(find.byKey(const Key('call.screen')), findsNothing);
  });

  testWidgets('recevoir puis refuser', (tester) async {
    final deps = await _start(tester, openBob: false);
    final c = deps.calls.incoming();
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.decline')));
    await _tick(tester, 200);
    expect(deps.calls.declined, [c.id]);
    expect(_status(tester), 'Appel refusé');
    expect(deps.callEngine.log, isEmpty, reason: 'micro jamais ouvert');
    await _tick(tester, 800);
  });

  testWidgets('appel retrouvé à l’ouverture de Privio', (tester) async {
    final deps = _deps();
    deps.calls.incoming();
    await _start(tester, deps: deps, openBob: false);
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.decline')));
    await _tick(tester, 1000);
  });

  testWidgets('Bob refuse, ne répond pas, ou est déjà en appel', (tester) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    deps.calls.peerEnd(deps.calls.calls.keys.last, 'declined');
    await _tick(tester);
    expect(_status(tester), 'Appel refusé');
    await _tick(tester, 800);

    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    deps.calls.peerEnd(deps.calls.calls.keys.last, 'missed');
    await _tick(tester);
    expect(_status(tester), 'Pas de réponse');
    await _tick(tester, 800);

    deps.calls.peerBusy = true;
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(_status(tester), 'Déjà en appel');
    await _tick(tester, 800);
    expect(find.byKey(const Key('call.screen')), findsNothing);
  });

  testWidgets('micro refusé : pas d’appel, message', (tester) async {
    final deps = _deps()..recorder.permission = MicPermission.denied;
    await _start(tester, deps: deps);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsNothing);
    expect(deps.calls.calls, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('réduire l’appel en bandeau, puis revenir', (tester) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.call')));
    await _tick(tester);
    await tester.tap(find.byKey(const Key('call.minimize')));
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsNothing);
    expect(find.byKey(const Key('call.bar')), findsOneWidget);
    expect(find.byKey(const Key('chat.input')), findsOneWidget, reason: 'Privio reste utilisable');
    await tester.tap(find.byKey(const Key('call.bar')));
    await _tick(tester);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
    expect(deps.calls.ended, hasLength(1));
  });

  testWidgets('Privio verrouillé : décrocher sans le code, nom caché', (tester) async {
    final deps = _deps();
    final salt = List<int>.generate(16, (i) => i);
    deps.lockStore.config = AppLockConfig(
      enabled: true,
      delaySeconds: 60,
      salt: base64Encode(salt),
      hash: await const FastPinHasher().hash('258014', salt, 1),
    );
    await _start(tester, deps: deps, openBob: false);
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);
    final c = deps.calls.incoming();
    deps.realtime.emitCall('conv-bob', c.id);
    await _tick(tester);
    expect(find.text('Appel Privio entrant'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    await tester.tap(find.byKey(const Key('call.accept')));
    await _tick(tester);
    expect(deps.calls.calls[c.id]!.status, 'accepted');
    await tester.tap(find.byKey(const Key('call.hangup')));
    await _tick(tester, 1000);
    expect(
      find.byKey(const Key('lock.screen')),
      findsOneWidget,
      reason: 'le reste reste verrouillé',
    );
  });

  testWidgets('pas de bouton d’appel pour un groupe ; réglage « Recevoir des appels »', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup('g1', 'Famille', members: {'u2': 'member'});
    await _start(tester, deps: deps, openBob: false);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.call')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.privacy');
    await scrollToKey(tester, 'privacy.calls');
    await tester.tap(find.byKey(const Key('privacy.calls')));
    await tester.pumpAndSettle();
    expect(deps.calls.acceptCallsSetting, isFalse);
    expect(find.text('Personne ne peut vous appeler.'), findsOneWidget);
  });
}
