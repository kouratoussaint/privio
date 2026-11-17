import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';

/// Lot 3.3 — groupes, via les écrans réels : création, invitations, rôles, réglages, départ.
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

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openGroup(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('conversation.$id')));
  await tester.pumpAndSettle();
}

Future<void> _openInfo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('chat.contact')));
  await tester.pumpAndSettle();
  expect(find.byType(Scaffold), findsWidgets);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// Fait défiler jusqu'à [f] puis le touche.
Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await _scrollTo(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('créer un groupe\u202F: contacts et identifiant, puis la discussion s’ouvre', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation(FakeMessagingApi.bob.id);
    await _start(tester, deps);

    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun groupe pour l’instant'), findsOneWidget);
    expect(find.textContaining(RegExp('communaut', caseSensitive: false)), findsNothing);

    await tester.tap(find.byKey(const Key('groups.new')));
    await tester.pumpAndSettle();
    // Sans nom : refus clair, rien n'est créé.
    // Lot 10.5 : écran plus long (type de groupe) : on va en bas.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group.create')));
    await tester.pumpAndSettle();
    expect(deps.messaging.groups, isEmpty);
    expect(find.text('Le nom du groupe doit contenir entre 1 et 60 caractères.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // le message s'efface
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('group.title')), 'Famille');
    await tester.tap(find.byKey(const Key('picker.user.u2'))); // Bob, depuis les contacts
    await tester.enterText(find.byKey(const Key('picker.search')), 'awa_s');
    await tester.tap(find.byKey(const Key('picker.submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picker.user.u3')), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('group.create')));
    expect(find.text('Créer et inviter 2 personnes'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('group.create')));

    final g = deps.messaging.groups.values.single;
    expect(g.title, 'Famille');
    expect(g.roles, {FakeMessagingApi.me: 'owner'});
    expect(g.invited, {'u2', 'u3'}, reason: 'invitations, pas d’ajout forcé');
    expect(find.text('Famille'), findsWidgets);
    expect(find.byKey(const Key('chat.members')), findsOneWidget);
    expect(find.text('1 membre'), findsOneWidget);
    expect(find.text('Vous avez créé le groupe «\u202FFamille\u202F»'), findsOneWidget);

    // Envoi d'un message dans le groupe.
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bienvenue');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue'), findsOneWidget);
  });

  testWidgets('invitations\u202F: refuser, puis rejoindre un groupe', (tester) async {
    final deps = _deps();
    deps.messaging.invitations.addAll(const [
      GroupInvitation(
        id: 'i1',
        conversationId: 'g-foot',
        title: 'Foot du jeudi',
        memberCount: 6,
        inviterName: 'Issa',
      ),
      GroupInvitation(
        id: 'i2',
        conversationId: 'g-fam',
        title: 'Famille',
        description: 'Les nouvelles du village',
        memberCount: 3,
        inviterName: 'Bob',
      ),
    ]);
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.text('Issa vous invite · 6 membres'), findsOneWidget);
    expect(find.text('Les nouvelles du village'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invitation.decline.i1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i1')), findsNothing);
    expect(deps.messaging.groups.containsKey('g-foot'), isFalse);

    await tester.tap(find.byKey(const Key('invitation.accept.i2')));
    await tester.pumpAndSettle();
    expect(deps.messaging.groups['g-fam']!.roles[FakeMessagingApi.me], 'member');
    expect(find.text('Vous avez rejoint le groupe'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i2')), findsNothing);
    expect(find.byKey(const Key('conversation.g-fam')), findsOneWidget);
  });

  testWidgets('discussion de groupe\u202F: nom des auteurs, filtre, durée réservée aux admins', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation(FakeMessagingApi.bob.id);
    deps.messaging
      ..seedGroup(
        'g1',
        'Famille',
        owner: 'u2',
        members: {FakeMessagingApi.me: 'member', 'u3': 'member'},
      )
      ..receiveInGroup('g1', 'u3', 'On se voit dimanche\u202F?');
    await _start(tester, deps);

    // Aperçu « Awa : … » et filtre Groupes.
    expect(find.text('Awa\u202F: On se voit dimanche\u202F?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter.groups')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.g1')), findsOneWidget);
    expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);

    await _openGroup(tester, 'g1');
    expect(find.text('3 membres'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('bubble.sender')),
        matching: find.text('Awa'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    // Membre simple, modification réservée aux administrateurs : pas de réglage de durée.
    expect(find.byKey(const Key('chat.ttl')), findsNothing);
    expect(find.byKey(const Key('chat.posting_restricted')), findsNothing);

    // Pas de suppression pour tous du message d'un autre quand on n'est pas admin.
    await tester.longPress(find.text('On se voit dimanche\u202F?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action.delete_all')), findsNothing);
  });

  testWidgets('envoi réservé aux administrateurs\u202F: bandeau à la place de la saisie', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup(
      'g1',
      'Annonces',
      owner: 'u2',
      members: {FakeMessagingApi.me: 'member'},
      posting: 'admins',
    );
    await _start(tester, deps);
    await _openGroup(tester, 'g1');
    expect(find.byKey(const Key('chat.posting_restricted')), findsOneWidget);
    expect(
      find.text('Seuls les administrateurs peuvent envoyer des messages dans ce groupe.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat.input')), findsNothing);
    expect(find.byKey(const Key('composer.photo')), findsNothing);
  });

  testWidgets(
    'administration\u202F: rôles, retrait, réglages, nom\u202F; l’admin supprime un message',
    (tester) async {
      final deps = _deps();
      final g = deps.messaging.seedGroup('g1', 'Famille', members: {'u2': 'member', 'u3': 'admin'});
      deps.messaging.receiveInGroup('g1', 'u2', 'Message de trop');
      await _start(tester, deps);
      await _openGroup(tester, 'g1');

      // Suppression pour tous du message d'un membre (administrateur).
      await tester.longPress(find.text('Message de trop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action.delete_all')));
      await tester.pumpAndSettle();
      expect(find.textContaining('sera supprimé pour tous les membres du groupe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action.delete_all.confirm')));
      await tester.pumpAndSettle();
      expect(deps.messaging.messages['g1']!.last.isDeleted, isTrue);

      await _openInfo(tester);
      expect(find.text('3 membres'), findsOneWidget);
      await _scrollTo(tester, find.byKey(const Key('member.u3')));
      expect(find.text('Toussaint (vous)'), findsOneWidget);

      // Bob devient administrateur.
      // Lot 8.1a : la carte de la personne s'ouvre ; « Gérer ce membre » pour l'admin.
      await tester.tap(find.byKey(const Key('member.u2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person.card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('card.manage')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, const Key('member.make_admin'));
      await tester.pumpAndSettle();
      expect(g.roles['u2'], 'admin');

      // Awa (administratrice) est retirée par le propriétaire, après confirmation.
      await tester.tap(find.byKey(const Key('member.u3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card.manage')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, const Key('member.remove'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer Awa\u202F?'), findsOneWidget);
      await tapMenuItem(tester, const Key('member.confirm'));
      await tester.pumpAndSettle();
      expect(g.roles.containsKey('u3'), isFalse);
      expect(find.byKey(const Key('member.u3')), findsNothing);

      // Réglages (lot 7.2a : carte « Réglages du groupe », au-dessus des membres).
      await tester.scrollUntilVisible(
        find.byKey(const Key('group.posting')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group.posting')));
      await tester.pumpAndSettle();
      expect(g.posting, 'admins');
      await tester.tap(find.byKey(const Key('group.info_editing')));
      await tester.pumpAndSettle();
      expect(g.infoEditing, 'all');
      await tester.scrollUntilVisible(
        find.byKey(const Key('group.edit')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Nom et description.
      await tester.tap(find.byKey(const Key('group.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('group.edit.title')), 'Famille Kouraogo');
      await tester.enterText(find.byKey(const Key('group.edit.description')), 'Nouvelles');
      await tester.tap(find.byKey(const Key('group.edit.save')));
      await tester.pumpAndSettle();
      expect(g.title, 'Famille Kouraogo');
      expect(g.description, 'Nouvelles');
      expect(find.text('Famille Kouraogo', skipOffstage: false), findsOneWidget);

      // Sourdine 8 heures.
      await _scrollTo(tester, find.byKey(const Key('group.mute')));
      await tester.tap(find.byKey(const Key('group.mute')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mute.8')));
      await tester.pumpAndSettle();
      expect(deps.messaging.muted['g1'], isNotNull);

      // Durée des messages du groupe depuis les Infos (lot 4.6).
      await tester.scrollUntilVisible(
        find.byKey(const Key('group.ttl')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group.ttl')));
      await tester.pumpAndSettle();
      expect(find.text('Pour les prochains messages du groupe.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ttl.21600')));
      await tester.pumpAndSettle();
      expect(deps.messaging.lastTtlSet, ('g1', 21600));

      // Retour à la discussion : les événements sont affichés.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Vous avez nommé Bob administrateur'), findsOneWidget);
      expect(find.text('Vous avez retiré Awa du groupe'), findsOneWidget);
      expect(
        find.text('Vous avez renommé le groupe «\u202FFamille Kouraogo\u202F»'),
        findsOneWidget,
      );
      expect(
        find.text('Vous avez réservé l’envoi de messages aux administrateurs'),
        findsOneWidget,
      );
    },
  );

  testWidgets('membre\u202F: pas d’actions d’administration\u202F; signaler et quitter le groupe', (
    tester,
  ) async {
    final deps = _deps();
    final g = deps.messaging.seedGroup(
      'g1',
      'Famille',
      owner: 'u2',
      members: {FakeMessagingApi.me: 'member', 'u3': 'member'},
    );
    await _start(tester, deps);
    await _openGroup(tester, 'g1');
    await _openInfo(tester);

    expect(find.byKey(const Key('group.edit')), findsNothing);
    expect(find.byKey(const Key('group.posting')), findsNothing);
    expect(find.byKey(const Key('group.invite')), findsNothing);
    await _scrollTo(tester, find.byKey(const Key('member.u3')));
    expect(find.text('Propriétaire'), findsOneWidget);

    // Signalement du groupe : pas de case « bloquer » (aucune personne visée).
    await _scrollTo(tester, find.byKey(const Key('group.report')));
    await tester.tap(find.byKey(const Key('group.report')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report.block')), findsNothing);
    await tester.tap(find.byKey(const Key('report.spam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report.submit')));
    await tester.pumpAndSettle();
    expect(deps.messaging.reports.single['user'], isNull);
    expect(deps.messaging.reports.single['conversation'], 'g1');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const Key('group.leave')));
    await tester.tap(find.byKey(const Key('group.leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group.leave.confirm')));
    await tester.pumpAndSettle();
    expect(g.roles.containsKey(FakeMessagingApi.me), isFalse);
    expect(find.byKey(const Key('groups.new')), findsOneWidget, reason: 'retour aux groupes');
    expect(find.byKey(const Key('conversation.g1')), findsNothing);
  });

  testWidgets('retiré d’un groupe\u202F: la discussion n’est plus lisible', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g1', 'Famille', owner: 'u2', members: {'u3': 'member'});
    await _start(tester, deps);
    unawaited(GoRouter.of(tester.element(find.byType(PrivioNavBar))).push('/chat/g1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.not_member')), findsOneWidget);
    expect(find.text('Vous ne faites plus partie de ce groupe.'), findsOneWidget);
    expect(find.byKey(const Key('chat.input')), findsNothing);
  });
}
