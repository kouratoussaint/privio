import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/conversations/polls.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';

/// Lot 10.5 — groupes « Annonces » (type définitif, seuls les administrateurs écrivent,
/// membres cachés) et sondages éphémères (création, vote, résultats, fermeture).
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

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await _tap(tester, key);
}

/// Dernier vote envoyé : « sondage:choix ».
String _lastVote(TestDeps deps) {
  final (id, options) = deps.messaging.votes.last;
  return '$id:${options.join(',')}';
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _menu(WidgetTester tester, String item) async {
  await _tap(tester, 'chat.menu');
  await tapMenuItem(tester, Key('chat.menu.$item'));
  await tester.pumpAndSettle();
}

void main() {
  test('brouillon de sondage : choix vides retirés, doublons et question vide refusés', () {
    final d = cleanPollDraft('  Quel   jour ? ', ['Samedi', ' ', 'Dimanche  ']);
    expect(d?.question, 'Quel jour ?');
    expect(d?.options, ['Samedi', 'Dimanche']);
    expect(cleanPollDraft('Jour ?', ['Samedi', 'samedi']), isNull);
    expect(cleanPollDraft(' ', ['A', 'B']), isNull);
    expect(cleanPollDraft('Jour ?', ['Samedi']), isNull);
  });

  testWidgets('créer un groupe « Annonces » : type définitif, en-tête « Annonces »', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await _tap(tester, 'groups.new');
    await tester.enterText(find.byKey(const Key('group.title')), 'Infos du quartier');
    await _tapVisible(tester, 'new_group.type.announcement');
    expect(find.textContaining('Ce choix est définitif.'), findsOneWidget);
    await _tapVisible(tester, 'group.create');

    final g = deps.messaging.groups.values.single;
    expect(g.announcement, isTrue);
    expect(g.posting, 'admins');
    expect(find.text('Annonces · 1 membre'), findsOneWidget);
    // L'administrateur écrit normalement et peut créer un sondage.
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
    await _tap(tester, 'chat.menu');
    expect(find.byKey(const Key('chat.menu.poll')), findsOneWidget);
  });

  testWidgets('membre d’un groupe « Annonces » : n’écrit pas, ne voit que les administrateurs', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup(
      'g-ann',
      'Infos du quartier',
      owner: 'u2',
      members: const {'u1': 'member', 'u3': 'member'},
      announcement: true,
    );
    deps.messaging.receiveInGroup('g-ann', 'u2', 'Coupure d’eau demain');
    await _start(tester, deps);
    await _tap(tester, 'conversation.g-ann');
    expect(
      find.textContaining('seuls les administrateurs écrivent. Vous pouvez réagir et voter.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat.input')), findsNothing);
    await _tap(tester, 'chat.menu');
    expect(find.byKey(const Key('chat.menu.poll')), findsNothing, reason: 'pas de sondage');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _tap(tester, 'chat.contact');
    expect(find.text('Annonces · 3 membres'), findsOneWidget);
    expect(find.byKey(const Key('group.posting')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('member.u2')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('group.members_hidden')), findsOneWidget);
    expect(find.byKey(const Key('member.u3')), findsNothing, reason: 'Awa n’est qu’un membre');
  });

  testWidgets('sondage : créer, voter, changer d’avis, retirer, fermer', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g1', 'Famille', members: const {'u2': 'member', 'u3': 'member'});
    await _start(tester, deps);
    await _tap(tester, 'conversation.g1');
    await _menu(tester, 'poll');

    // Brouillon incomplet : refusé.
    await tester.enterText(find.byKey(const Key('poll.question')), 'Quel jour pour la fête ?');
    await tester.enterText(find.byKey(const Key('poll.option.0')), 'Samedi');
    await _tap(tester, 'poll.send');
    expect(find.text('Écrivez une question et au moins deux choix différents.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('poll.option.1')), 'Dimanche');
    await _tap(tester, 'poll.add_option');
    await tester.enterText(find.byKey(const Key('poll.option.2')), 'Lundi');
    await _tap(tester, 'poll.send');

    final id = deps.messaging.polls.keys.single;
    final poll = deps.messaging.polls[id]!;
    expect(poll.options, ['Samedi', 'Dimanche', 'Lundi']);
    expect(poll.anonymous, isTrue, reason: 'vote anonyme par défaut');
    expect(poll.multi, isFalse);
    expect(find.text('Quel jour pour la fête ?'), findsOneWidget);
    expect(find.text('Une seule réponse · Vote anonyme'), findsOneWidget);

    await _tap(tester, 'poll.$id.option.1');
    expect(_lastVote(deps), '$id:1');
    expect(find.text('1 personne a voté'), findsOneWidget);
    deps.messaging.peerVotes(id, 'u2', [1]);
    await _tap(tester, 'poll.$id.option.0');
    expect(_lastVote(deps), '$id:0', reason: 'une seule réponse : le vote change');
    expect(find.text('2 personnes ont voté'), findsOneWidget);
    expect(find.byKey(Key('poll.$id.show_votes')), findsNothing, reason: 'vote anonyme');

    await _tap(tester, 'poll.$id.unvote');
    expect(_lastVote(deps), '$id:');
    expect(find.text('1 personne a voté'), findsOneWidget);

    // Fermer (créateur) : plus de vote.
    await tester.longPress(find.byKey(Key('poll.$id')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('action.reply')),
      findsNothing,
      reason: 'on vote, on ne répond pas',
    );
    await _tap(tester, 'action.close_poll');
    await _tap(tester, 'poll.close.confirm');
    expect(poll.closedAt, isNotNull);
    expect(find.textContaining('Sondage fermé'), findsWidgets);
    final before = deps.messaging.votes.length;
    await _tap(tester, 'poll.$id.option.2');
    expect(deps.messaging.votes.length, before, reason: 'sondage fermé');

    // Aperçu dans la liste : la question.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Vous : 📊 Quel jour pour la fête ?'), findsOneWidget);
  });

  testWidgets('sondage visible à plusieurs réponses : « Voir les votes »', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g1', 'Famille', members: const {'u2': 'member', 'u3': 'member'});
    final m = deps.messaging.receivePoll(
      'g1',
      'u2',
      'Qui apporte quoi ?',
      ['Riz', 'Boissons', 'Dessert'],
      multi: true,
      anonymous: false,
    );
    deps.messaging.peerVotes(m.id, 'u3', [0, 2]);
    await _start(tester, deps);
    await _tap(tester, 'conversation.g1');
    expect(find.text('Plusieurs réponses possibles · Votes visibles'), findsOneWidget);
    await _tap(tester, 'poll.${m.id}.option.1');
    await _tap(tester, 'poll.${m.id}.option.2');
    expect(_lastVote(deps), '${m.id}:1,2');
    await _tap(tester, 'poll.${m.id}.show_votes');
    expect(find.byKey(const Key('poll.votes')), findsOneWidget);
    expect(find.text('Dessert · 2 votes'), findsOneWidget);
    expect(find.text('Awa'), findsNWidgets(2));
    expect(find.text('Vous'), findsNWidgets(2));
  });

  testWidgets('groupe « Annonces » : un membre vote au sondage de l’administrateur', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup(
      'g-ann',
      'Infos',
      owner: 'u2',
      members: const {'u1': 'member', 'u3': 'member'},
      announcement: true,
    );
    final m = deps.messaging.receivePoll('g-ann', 'u2', 'Nettoyage samedi ?', [
      'Oui',
      'Non',
    ], anonymous: false);
    deps.messaging.peerVotes(m.id, 'u3', [0]);
    await _start(tester, deps);
    expect(find.text('Bob : 📊 Nettoyage samedi ?'), findsOneWidget);
    await _tap(tester, 'conversation.g-ann');
    await _tap(tester, 'poll.${m.id}.option.0');
    expect(_lastVote(deps), '${m.id}:0');
    expect(find.text('2 personnes ont voté'), findsOneWidget);
    expect(find.byKey(Key('poll.${m.id}.show_votes')), findsNothing, reason: 'membres cachés');
  });
}
