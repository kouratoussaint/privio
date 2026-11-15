import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

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
    expect(find.text('Aucune discussion pour l’instant'), findsOneWidget);
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
    await tester.pump(); // le bouton « Envoyer » remplace le micro
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour Bob'), findsOneWidget);
    // Minuterie discrète « ⏱ 71 h » (TalkBack lit « expire dans 71 h »).
    expect(find.text('71 h'), findsOneWidget);

    // Réception en temps réel ; un message déjà expiré n'est jamais affiché
    deps.messaging.receive('conv-bob', 'Salut Toussaint\u202F!');
    deps.messaging.receive(
      'conv-bob',
      'Message expiré',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.text('Salut Toussaint\u202F!'), findsOneWidget);
    expect(find.text('Message expiré'), findsNothing);

    // Coupure réseau : le message attend (file locale), puis repart avec le MÊME
    // identifiant (pas de doublon)
    deps.messaging.failNextSend = true;
    await tester.enterText(find.byKey(const Key('chat.input')), 'Tu es là\u202F?');
    await tester.pump(); // le bouton « Envoyer » remplace le micro
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    // Lot 7.2a : un échec isolé ne suffit plus à annoncer « hors connexion ».
    expect(find.textContaining('Envoi…'), findsOneWidget);
    expect(find.byKey(const Key('offline.banner')), findsNothing);
    await tester.tap(find.text('Tu es là\u202F?'));
    await tester.pumpAndSettle();
    final ids = deps.messaging.sentClientIds;
    expect(ids[ids.length - 1], ids[ids.length - 2]);
    expect(find.textContaining('En attente de réseau'), findsNothing);
    expect(find.text('Tu es là\u202F?'), findsOneWidget);

    // Fiche contact → bloquer
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    expect(find.text('@bob_ouaga'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('contact.block')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
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
    expect(find.text('Vous avez bloqué Bob.'), findsOneWidget);
    expect(find.byKey(const Key('notice.action')), findsOneWidget); // « Débloquer »

    // Paramètres → Personnes bloquées → Débloquer
    await tester.tap(find.byType(BackButton)); // pageBack() cherche « Back » (anglais)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.privacy');
    await scrollToKey(tester, 'privacy.blocked');
    await tester.tap(find.byKey(const Key('privacy.blocked')));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.byKey(const Key('blocked.unblock.u2')));
    await tester.pumpAndSettle();
    expect(deps.messaging.blocked, isEmpty);
    expect(find.text('Personne n’est bloqué'), findsOneWidget);
  });

  testWidgets('recherche par numéro\u202F: format +226, message clair si introuvable', (
    tester,
  ) async {
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
    expect(find.textContaining('invitez cette personne'), findsOneWidget);
  });

  testWidgets('identifiant invalide\u202F: aucune requête envoyée', (tester) async {
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

  testWidgets('temps réel coupé\u202F: le message reçu apparaît quand même en 5 s', (tester) async {
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

  testWidgets('bandeau de blocage\u202F: « Débloquer » rouvre la saisie (lot 4.4)', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.write')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('contact.block')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact.block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact.block.confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // le message « Bob est bloqué. » se retire
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notice.action')));
    await tester.pumpAndSettle();
    expect(deps.messaging.blocked, isEmpty);
    expect(find.text('Bob est débloqué.'), findsOneWidget);
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
  });

  testWidgets('Aide\u202F: diagnostic de connexion (déplacé des Paramètres)', (tester) async {
    final deps = _readyUser();
    await _pumpApp(tester, deps);
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Réception instantanée'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.help')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('settings.help')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.help')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.realtime')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Diagnostic de connexion'), findsOneWidget);
    expect(find.text('Connecté'), findsOneWidget);
  });
}
