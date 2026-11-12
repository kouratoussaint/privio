import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 2.2 — parcours complet avec le vrai routeur et une messagerie simulée.
TestDeps _readyUser() =>
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

Future<void> _pumpApp(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chercher Bob, ouvrir la discussion, échanger, bloquer, débloquer', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);

    // 08 — liste vide, temps réel démarré pour le compte connecté
    expect(find.text('Aucune discussion pour l\'instant'), findsOneWidget);
    expect(deps.realtime.startedFor, 'u1');

    // 09 — recherche exacte par identifiant (normalisé : @, majuscules)
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), '@Bob_Ouaga');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    expect(deps.messaging.handleSearches, ['bob_ouaga']);
    expect(find.byKey(const Key('search.result')), findsOneWidget);
    await tester.tap(find.byKey(const Key('search.write')));
    await tester.pumpAndSettle();

    // 10 — conversation : en-tête au nom de Bob
    expect(find.text('Bob'), findsWidgets);
    expect(find.text('Aucun message'), findsOneWidget);

    // Envoi
    await tester.enterText(find.byKey(const Key('chat.input')), '  Bonjour Bob  ');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour Bob'), findsOneWidget);
    // Minuterie discrète « ⏱ 71 h » (TalkBack lit « expire dans 71 h »).
    expect(find.text('71 h'), findsOneWidget);

    // Réception en temps réel ; un message déjà expiré n'est jamais affiché
    deps.messaging.receive('conv-bob', 'Salut Toussaint !');
    deps.messaging.receive(
      'conv-bob',
      'Message expiré',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.text('Salut Toussaint !'), findsOneWidget);
    expect(find.text('Message expiré'), findsNothing);

    // Échec réseau puis nouvel essai avec le MÊME identifiant (pas de doublon)
    deps.messaging.failNextSend = true;
    await tester.enterText(find.byKey(const Key('chat.input')), 'Tu es là ?');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Échec de l\'envoi'), findsOneWidget);
    await tester.tap(find.text('Tu es là ?'));
    await tester.pumpAndSettle();
    final ids = deps.messaging.sentClientIds;
    expect(ids[ids.length - 1], ids[ids.length - 2]);
    expect(find.textContaining('Échec de l\'envoi'), findsNothing);
    expect(find.text('Tu es là ?'), findsOneWidget);

    // Fiche contact → bloquer
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    expect(find.text('@bob_ouaga'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contact.block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact.block.confirm')));
    await tester.pumpAndSettle();
    expect(deps.messaging.blocked, contains('u2'));
    expect(find.text('Débloquer'), findsOneWidget);

    // Retour : plus de zone de saisie, bandeau de blocage
    await tester.tap(find.byType(BackButton)); // pageBack() cherche « Back » (anglais)
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsNothing);
    expect(find.textContaining('(blocage)'), findsOneWidget);

    // Paramètres → Personnes bloquées → Débloquer
    await tester.tap(find.byType(BackButton)); // pageBack() cherche « Back » (anglais)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.blocked')));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blocked.unblock.u2')));
    await tester.pumpAndSettle();
    expect(deps.messaging.blocked, isEmpty);
    expect(find.text('Personne n\'est bloqué'), findsOneWidget);
  });

  testWidgets('recherche par numéro : format +226, message clair si introuvable', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), '70 00 00 09');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    expect(deps.messaging.phoneSearches, ['+22670000009']);
    expect(deps.messaging.handleSearches, isEmpty);
    expect(find.textContaining('Aucun compte trouvé'), findsOneWidget);
    expect(find.textContaining('Me trouver par mon numéro'), findsOneWidget);
  });

  testWidgets('identifiant invalide : aucune requête envoyée', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), 'ab');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    expect(find.text('Au moins 3 caractères.'), findsOneWidget);
    expect(deps.messaging.handleSearches, isEmpty);
  });

  testWidgets('temps réel coupé : le message reçu apparaît quand même en 5 s', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.write')));
    await tester.pumpAndSettle();

    // Aucun signal temps réel émis : seul le rafraîchissement de secours peut l'afficher.
    deps.messaging.receive('conv-bob', 'Arrivé sans temps réel');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Arrivé sans temps réel'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Arrivé sans temps réel'), findsOneWidget);
  });

  testWidgets('Paramètres : état de la réception instantanée visible', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Réception instantanée'), findsOneWidget);
    expect(find.text('Connecté'), findsOneWidget);
  });
}
