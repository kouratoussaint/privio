import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/services/call_system.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 9.4 — appels de groupe : lancer, sonner, rejoindre, refuser, bandeau, image, fin.
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

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

Future<TestDeps> _start(WidgetTester tester, {TestDeps? deps, bool open = true}) async {
  final d = deps ?? _deps();
  d.messaging.seedGroup('g1', 'Famille', members: {'u2': 'member', 'u3': 'member'});
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g1')));
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
      find.descendant(of: find.byKey(const Key('group_call.status')), matching: find.byType(Text)),
    )
    .data!;

void main() {
  test('trace d’un appel de groupe dans la discussion', () {
    ChatMessage m(String v, {String sender = 'u1', String k = 'audio'}) => ChatMessage(
      id: 'x',
      senderId: sender,
      kind: 'system',
      body: jsonEncode({'e': 'group_call', 'k': k, 'v': v, 'a': 'Bob'}),
      sentAt: DateTime(2026, 11, 18),
      expiresAt: DateTime(2026, 11, 21),
      updatedAt: DateTime(2026, 11, 18),
    );
    expect(groupEventText(m('ended:183'), me: 'u1'), 'Appel de groupe · 03:03');
    expect(
      groupEventText(m('ended:3725', k: 'video'), me: 'u1'),
      'Appel vidéo de groupe · 1:02:05',
    );
    expect(groupEventText(m('missed'), me: 'u1'), 'Appel de groupe sans réponse');
    expect(groupEventText(m('missed', sender: 'u2'), me: 'u1'), 'Appel de groupe manqué de Bob');
  });

  testWidgets('lancer : relais, arrivée et départ d’une personne, micro, quitter', (tester) async {
    final deps = await _start(tester);
    expect(find.byKey(const Key('chat.group_call')), findsOneWidget);
    expect(find.byKey(const Key('chat.group_video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat.group_call')));
    await _tick(tester);
    expect(find.byKey(const Key('group_call.screen')), findsOneWidget);
    expect(find.text('Famille'), findsWidgets);
    expect(_status(tester), 'Connexion…');
    expect(deps.groupCalls.log, ['start:g1:audio', 'push:audio:fresh']);
    expect(deps.groupEngine.log, ['open', 'publish:audio', 'answer:answer']);
    expect(find.byKey(const Key('group_call.tile.me')), findsOneWidget);

    deps.groupEngine.onState!(CallMediaState.connected);
    await _tick(tester);
    expect(_status(tester), '00:00');

    // Carla (u3) arrive : ses pistes sont demandées au relais, on répond à son offre.
    final id = deps.groupCalls.calls.keys.single;
    deps.groupCalls.peerJoin(id, 'u3', name: 'Carla');
    deps.realtime.emitGroupCall('g1', id);
    await _tick(tester);
    expect(deps.groupCalls.log, containsAll(['pull:audio-u3', 'answer']));
    expect(deps.groupEngine.log, contains('accept:offer'));
    expect(find.byKey(const Key('group_call.tile.u3')), findsOneWidget);
    expect(find.text('Carla'), findsOneWidget);
    expect(find.text('2/8'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_call.mute')));
    await _tick(tester);
    expect(deps.groupEngine.muted, isTrue);
    expect(deps.groupCalls.log, contains('media:-:true'));

    // Carla part : sa piste est arrêtée au relais.
    deps.groupCalls.peerLeave(id, 'u3');
    deps.realtime.emitGroupCall('g1', id);
    await _tick(tester);
    expect(deps.groupCalls.log, contains('close:1'));
    expect(find.byKey(const Key('group_call.tile.u3')), findsNothing);

    // Réduire puis revenir.
    await tester.tap(find.byKey(const Key('group_call.minimize')));
    await _tick(tester);
    expect(find.byKey(const Key('group_call.bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_call.bar')));
    await _tick(tester);

    await tester.tap(find.byKey(const Key('group_call.hangup')));
    await _tick(tester, 200);
    expect(deps.groupCalls.log, contains('leave:$id'));
    expect(_status(tester), startsWith('Appel terminé'));
    expect(deps.groupEngine.log.last, 'close');
    await _tick(tester, 800);
    expect(find.byKey(const Key('group_call.screen')), findsNothing);
  });

  testWidgets('ça sonne : qui a lancé l’appel, rejoindre', (tester) async {
    final deps = await _start(tester, open: false);
    final call = deps.groupCalls.ringMe(conversationId: 'g1');
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    expect(find.byKey(const Key('group_call.screen')), findsOneWidget);
    expect(_status(tester), 'Appel de groupe…');
    expect(find.text('Lancé par Bob'), findsOneWidget);
    expect(find.text('1 personne dans l’appel'), findsOneWidget);
    expect(deps.tones.log, contains('ring'));

    await tester.tap(find.byKey(const Key('group_call.accept')));
    await _tick(tester);
    expect(
      deps.groupCalls.log,
      containsAll(['join:${call.id}', 'push:audio:fresh', 'pull:audio-u2']),
    );
    expect(find.byKey(const Key('group_call.tile.u2')), findsOneWidget);
    expect(deps.tones.log.last, 'stop');
  });

  testWidgets('refuser : la sonnerie s’arrête, bandeau « Rejoindre » dans le groupe', (
    tester,
  ) async {
    final deps = await _start(tester, open: false);
    final call = deps.groupCalls.ringMe(conversationId: 'g1');
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    await tester.tap(find.byKey(const Key('group_call.decline')));
    await _tick(tester);
    expect(deps.groupCalls.log, contains('decline:${call.id}'));
    expect(find.byKey(const Key('group_call.screen')), findsNothing);
    // Un nouveau signal ne fait pas sonner de nouveau.
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    expect(find.byKey(const Key('group_call.screen')), findsNothing);

    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group_call.banner')), findsOneWidget);
    expect(find.text('Appel de groupe en cours · 1 personne'), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_call.banner.join')));
    await _tick(tester);
    expect(deps.groupCalls.log, contains('join:${call.id}'));
    expect(find.byKey(const Key('group_call.screen')), findsOneWidget);
    expect(find.byKey(const Key('group_call.banner')), findsNothing);
  });

  testWidgets('appel terminé pendant la sonnerie : l’écran disparaît', (tester) async {
    final deps = await _start(tester, open: false);
    final call = deps.groupCalls.ringMe(conversationId: 'g1');
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    expect(find.byKey(const Key('group_call.screen')), findsOneWidget);
    deps.groupCalls.endCall(call.id);
    await _tick(tester);
    expect(find.byKey(const Key('group_call.screen')), findsNothing);
    expect(deps.callSystem.log, contains('end:${call.id}'));
  });

  testWidgets('Privio en arrière-plan : l’écran d’appel du téléphone sonne (appel de groupe)', (
    tester,
  ) async {
    final deps = await _start(tester, open: false);
    deps.foreground = false;
    final call = deps.groupCalls.ringMe(conversationId: 'g1', kind: 'video');
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    expect(deps.callSystem.log, contains('group-show-video:${call.id}'));
    expect(deps.tones.log, isNot(contains('ring')));
    // « Décrocher » sur l'écran d'appel du téléphone.
    deps.callSystem.emit(CallSystemAction.accept, call.id, group: true);
    await _tick(tester);
    expect(deps.groupCalls.log, contains('join:${call.id}'));
  });

  testWidgets('appel vidéo : ma caméra dès le début, puis coupée', (tester) async {
    final deps = await _start(tester);
    await tester.tap(find.byKey(const Key('chat.group_video')));
    await _tick(tester);
    expect(deps.groupCalls.log, ['start:g1:video', 'push:audio+video:fresh']);
    expect(find.byKey(const Key('fake.group.local')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_call.camera')));
    await _tick(tester);
    expect(deps.groupEngine.log, contains('camera:false'));
    expect(deps.groupCalls.log, contains('media:false:-'));
    expect(find.byKey(const Key('fake.group.local')), findsNothing);
    await tester.tap(find.byKey(const Key('group_call.camera')));
    await _tick(tester);
    expect(deps.groupEngine.log, contains('camera:true'));
    await tester.tap(find.byKey(const Key('group_call.hangup')));
    await _tick(tester, 1000);
  });

  testWidgets('appel complet : message, et relais indisponible', (tester) async {
    final deps = await _start(tester, open: false);
    final call = deps.groupCalls.ringMe(conversationId: 'g1');
    deps.realtime.emitGroupCall('g1', call.id);
    await _tick(tester);
    deps.groupCalls.full = true;
    await tester.tap(find.byKey(const Key('group_call.accept')));
    await _tick(tester);
    expect(find.text('L’appel est complet (8 personnes au plus).'), findsOneWidget);
    await _tick(tester, 1000);
    expect(find.byKey(const Key('group_call.screen')), findsNothing);

    deps.groupCalls
      ..full = false
      ..failPush = const AppFailure(FailureCode.groupCallUnavailable);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.group_call')));
    await _tick(tester, 200);
    expect(
      find.text('Les appels de groupe sont momentanément indisponibles. Réessayez plus tard.'),
      findsOneWidget,
    );
    expect(deps.groupCalls.log.last, startsWith('leave:'));
  });

  testWidgets('groupe « Annonces » : pas de bouton d’appel pour un simple membre', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup(
      'g2',
      'Infos',
      owner: 'u2',
      members: {'u1': 'member'},
      announcement: true,
    );
    await _start(tester, deps: deps, open: false);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.group_call')), findsNothing);
    expect(find.byKey(const Key('chat.group_video')), findsNothing);
  });
}
