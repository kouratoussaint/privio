import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 2.4 — stockage local, hors connexion, saisie, épinglage, archivage, recherche.
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

Future<void> _launch(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: deps.overrides,
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openBob(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sans réseau au redémarrage : discussions et messages lus depuis le téléphone', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Gardé sur le téléphone');
    await _launch(tester, deps);
    await _openBob(tester);
    expect(find.text('Gardé sur le téléphone'), findsOneWidget);

    // Coupure réseau, puis redémarrage complet de l'application.
    deps.messaging.offline = true;
    await _launch(tester, deps);
    expect(find.byKey(const Key('offline.banner')), findsOneWidget);
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await _openBob(tester);
    expect(find.text('Gardé sur le téléphone'), findsOneWidget);
  });

  testWidgets('envoi hors ligne : en attente, puis part seul au retour du réseau, sans doublon', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _launch(tester, deps);
    await _openBob(tester);

    deps.messaging.offline = true;
    await tester.enterText(find.byKey(const Key('chat.input')), 'Écrit sans réseau');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('En attente du réseau'), findsOneWidget);
    expect(
      deps.store.data.toString(),
      contains('Écrit sans réseau'),
      reason: 'le message en attente survit à la fermeture de l’app',
    );

    deps.messaging.offline = false;
    await tester.pump(const Duration(seconds: 16)); // nouvel essai automatique
    await tester.pumpAndSettle();
    expect(find.textContaining('En attente du réseau'), findsNothing);
    expect(find.text('Écrit sans réseau'), findsOneWidget);
    final ids = deps.messaging.sentClientIds;
    expect(ids.toSet().length, 1, reason: 'toujours le même identifiant client');
    expect(
      deps.messaging.messages['conv-bob']!.where((m) => m.body == 'Écrit sans réseau'),
      hasLength(1),
    );
  });

  testWidgets('« en train d’écrire… » : affiché 5 s ; signal envoyé au plus toutes les 4 s', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Salut');
    await _launch(tester, deps);

    deps.realtime.emit('conv-bob', event: 'typing');
    await tester.pump();
    await tester.pump();
    // ignore: avoid_print
    print(
      'DEBUG typing=${find.textContaining('écrire').evaluate().length} realtime=${deps.realtime.startedFor}',
    );
    expect(find.text('en train d’écrire…'), findsOneWidget, reason: 'aperçu dans la liste');

    await _openBob(tester);
    deps.realtime.emit('conv-bob', event: 'typing');
    await tester.pump();
    expect(find.byKey(const Key('chat.typing')), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const Key('chat.typing')), findsNothing);

    await tester.enterText(find.byKey(const Key('chat.input')), 'B');
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bo');
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bon');
    await tester.pump();
    expect(deps.messaging.typingSignals, 1);
  });

  testWidgets('épingler, archiver puis désarchiver', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Salut');
    await _launch(tester, deps);

    await tester.longPress(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv.pin')));
    await tester.pumpAndSettle();
    expect(deps.messaging.pinned, isTrue);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.longPress(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv.archive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);
    expect(find.text('Archivées (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discussions.archived')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv.archive')));
    await tester.pumpAndSettle();
    expect(deps.messaging.archived, isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
  });

  testWidgets('recherche dans une conversation et dans la liste (texte des messages)', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Bonjour');
    deps.messaging.receive('conv-bob', 'Le dossier est prêt');
    await _launch(tester, deps);
    await _openBob(tester);

    await tester.tap(find.byKey(const Key('chat.search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat.search_input')), 'DOSSIER');
    await tester.pumpAndSettle();
    expect(find.text('Le dossier est prêt'), findsOneWidget);
    expect(find.text('Bonjour'), findsNothing);
    await tester.enterText(find.byKey(const Key('chat.search_input')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun message ne correspond'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat.search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // La recherche de la liste trouve la discussion par le texte d'un ancien message.
    await tester.enterText(find.byKey(const Key('discussions.search')), 'bonjour');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
  });
}
