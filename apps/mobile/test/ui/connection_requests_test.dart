import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';

/// Lot 4.7 — demande de connexion avant le premier message.
TestDeps _deps() {
  final deps =
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
  deps.messaging.requestsRequired = true;
  return deps;
}

Future<void> _pump(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _searchBob(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('discussions.new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
  await tester.tap(find.byKey(const Key('search.submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('inconnu : « Envoyer une demande » avec un mot, puis annuler', (tester) async {
    final deps = _deps();
    await _pump(tester, deps);
    await _searchBob(tester);
    expect(find.byKey(const Key('search.write')), findsNothing, reason: 'pas d’écriture directe');
    await tester.tap(find.byKey(const Key('search.request')));
    await tester.pumpAndSettle();
    expect(find.text('Demande à Bob'), findsOneWidget);
    expect(find.text('Effacé 5 min après l’acceptation.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('request.note')), 'Bonjour Bob, c’est Toussaint');
    await tester.tap(find.byKey(const Key('request.send')));
    await tester.pumpAndSettle();

    final sent = deps.messaging.requests.single;
    expect(sent.incoming, isFalse);
    expect(sent.note, 'Bonjour Bob, c’est Toussaint');
    expect(find.text('Demande envoyée à Bob.'), findsOneWidget);
    expect(find.byKey(const Key('search.pending')), findsOneWidget);
    expect(deps.messaging.conversations, isEmpty, reason: 'aucune discussion avant acceptation');

    await tester.tap(find.byKey(const Key('search.cancel')));
    await tester.pumpAndSettle();
    expect(deps.messaging.requests, isEmpty);
    expect(find.byKey(const Key('search.request')), findsOneWidget);
  });

  testWidgets('demande reçue : encart, pastille, puis « Accepter » ouvre la discussion', (
    tester,
  ) async {
    final deps = _deps();
    final r = deps.messaging.receiveConnectionRequest(note: 'Salut, c’est Bob');
    await _pump(tester, deps);
    expect(find.text('1 demande de connexion'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('nav.Discussions')), matching: find.text('1')),
      findsOneWidget,
      reason: 'la demande compte dans la pastille Discussions',
    );

    await tester.tap(find.byKey(const Key('requests.banner')));
    await tester.pumpAndSettle();
    expect(find.text('Demandes de connexion'), findsOneWidget);
    expect(find.text('Salut, c’est Bob'), findsOneWidget);
    expect(find.textContaining('@bob_ouaga'), findsOneWidget);

    await tester.tap(find.byKey(Key('request.${r.id}.accept')));
    await tester.pumpAndSettle();
    expect(deps.messaging.responses.single, (r.id, ConnectionAction.accept));
    expect(find.byKey(const Key('chat.input')), findsOneWidget, reason: 'discussion ouverte');
    expect(find.text('Salut, c’est Bob'), findsOneWidget, reason: 'le mot est le 1er message');
  });

  testWidgets('demande reçue : refuser', (tester) async {
    final deps = _deps();
    final r = deps.messaging.receiveConnectionRequest();
    await _pump(tester, deps);
    await tester.tap(find.byKey(const Key('requests.banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('request.${r.id}.refuse')));
    await tester.pumpAndSettle();
    expect(deps.messaging.responses.single, (r.id, ConnectionAction.refuse));
    expect(find.text('Demande refusée.'), findsOneWidget);
    expect(find.text('Aucune demande'), findsOneWidget);
    expect(deps.messaging.conversations, isEmpty);
  });

  testWidgets('demande reçue : bloquer (avec confirmation)', (tester) async {
    final deps = _deps();
    final r = deps.messaging.receiveConnectionRequest();
    await _pump(tester, deps);
    await tester.tap(find.byKey(const Key('requests.banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('request.${r.id}.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request.block')));
    await tester.pumpAndSettle();
    expect(find.text('Bloquer Bob ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('request.block.confirm')));
    await tester.pumpAndSettle();
    expect(deps.messaging.blocked, contains('u2'));
    expect(find.text('Bob est bloqué.'), findsOneWidget);
  });

  testWidgets('recherche : sa demande attend → « Accepter sa demande »', (tester) async {
    final deps = _deps();
    deps.messaging.receiveConnectionRequest();
    await _pump(tester, deps);
    await _searchBob(tester);
    await tester.tap(find.byKey(const Key('search.accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
  });

  testWidgets('recherche : refus récent, demande impossible ou déjà connectés', (tester) async {
    final deps = _deps();
    deps.messaging.retryAt = DateTime.now().add(const Duration(minutes: 4));
    await _pump(tester, deps);
    await _searchBob(tester);
    expect(find.byKey(const Key('search.refused')), findsOneWidget);
    expect(find.textContaining('Bob a refusé votre demande'), findsOneWidget);

    deps.messaging
      ..retryAt = null
      ..peerAcceptsRequests = false;
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.request')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request.send')));
    await tester.pumpAndSettle();
    expect(find.text('Cette personne n’accepte pas de demandes.'), findsOneWidget);

    await deps.messaging.startDirectConversation('u2');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.write')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('chat.input')),
      findsOneWidget,
      reason: 'déjà connectés : on écrit',
    );
  });

  testWidgets('demandes envoyées : en attente, puis refus visible', (tester) async {
    final deps = _deps();
    await _pump(tester, deps);
    await _searchBob(tester);
    await tester.tap(find.byKey(const Key('search.request')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request.send')));
    await tester.pumpAndSettle();
    // Lot 8.3b : les raccourcis réapparaissent quand le champ est vide.
    await tester.enterText(find.byKey(const Key('search.input')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.requests')));
    await tester.pumpAndSettle();
    final id = deps.messaging.requests.single.id;
    expect(find.textContaining('En attente · expire dans'), findsOneWidget);

    // Bob refuse : la liste se met à jour au signal temps réel.
    final r = deps.messaging.requests.removeAt(0);
    deps.messaging.requests.add(
      ConnectionRequest(
        id: r.id,
        incoming: false,
        userId: r.userId,
        handle: r.handle,
        displayName: r.displayName,
        status: 'refused',
        createdAt: r.createdAt,
        expiresAt: r.expiresAt,
        answeredAt: DateTime.now(),
        retryAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    deps.realtime.emit('', event: 'request');
    await tester.pumpAndSettle();
    expect(find.byKey(Key('request.$id.status')), findsOneWidget);
    expect(find.textContaining('A refusé votre demande · nouvel essai à'), findsOneWidget);
  });

  testWidgets('Confidentialité : « Demandes de connexion » activable', (tester) async {
    final deps = _deps();
    await _pump(tester, deps);
    await tester.tap(find.byKey(const Key('nav.Paramètres')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.privacy')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('settings.privacy')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy.requests')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('privacy.requests')));
    await tester.pumpAndSettle();
    expect(find.text('Tout le monde peut vous envoyer une demande.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacy.requests')));
    await tester.pumpAndSettle();
    expect(deps.messaging.acceptRequests, isFalse);
    expect(find.text('Personne ne peut vous envoyer de demande.'), findsOneWidget);
  });
}
