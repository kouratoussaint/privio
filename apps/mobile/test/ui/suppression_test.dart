import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 7.2b1 — « lu » seulement à l'écran, supprimer une discussion ou un groupe,
/// groupes séparés des discussions.
TestDeps _deps({bool together = false}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true)..groupsTogether = together,
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openBob(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Bonjour');
  await _start(tester, deps);
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

void main() {
  group('« lu » seulement quand la discussion est à l’écran', () {
    testWidgets('fiche ouverte par-dessus : message reçu « distribué », pas « lu »', (
      tester,
    ) async {
      final deps = _deps();
      await _openBob(tester, deps);
      expect(deps.messaging.lastRead('conv-bob'), isNotNull, reason: 'à l’écran : lu');
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      final before = deps.messaging.lastRead('conv-bob');

      final m = deps.messaging.receive('conv-bob', 'Tu as vu ?');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(deps.messaging.lastRead('conv-bob'), before, reason: 'sous la fiche : pas lu');
      expect(
        deps.messaging.marks.where((x) => x.$1 == 'conv-bob' && x.$2 == m.sentAt),
        isNotEmpty,
        reason: '« distribué » quand même',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(deps.messaging.lastRead('conv-bob'), m.sentAt, reason: 'de retour : lu');
    });

    testWidgets('application cachée (veille) : pas « lu » ; au retour : lu', (tester) async {
      final deps = _deps();
      await _openBob(tester, deps);
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      final before = deps.messaging.lastRead('conv-bob');

      final m = deps.messaging.receive('conv-bob', 'Réveille-toi');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(deps.messaging.lastRead('conv-bob'), before);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(deps.messaging.lastRead('conv-bob'), m.sentAt);
    });
  });

  group('supprimer', () {
    testWidgets('discussion supprimée chez moi : retour à la liste, elle a disparu', (
      tester,
    ) async {
      final deps = _deps();
      await _openBob(tester, deps);
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'contact.delete');
      await tester.tap(find.byKey(const Key('contact.delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete.everyone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete.me')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Discussion supprimée.'), findsOneWidget);
      expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);
      expect(find.byKey(const Key('discussions.new')), findsOneWidget, reason: 'liste');

      // Bob réécrit : elle revient, sans l'ancien message.
      deps.messaging.receive('conv-bob', 'Coucou');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    });

    testWidgets('pour nous deux : demande, puis Bob accepte une suppression', (tester) async {
      final deps = _deps();
      await _openBob(tester, deps);
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'contact.delete');
      await tester.tap(find.byKey(const Key('contact.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete.everyone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Demande envoyée à Bob.'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('pour supprimer la discussion'), findsOneWidget);
    });

    testWidgets('demande de suppression reçue : « Accepter et supprimer »', (tester) async {
      final deps = _deps();
      deps.messaging
        ..clearRequests['conv-bob'] = 'u2'
        ..deleteRequests.add('conv-bob');
      await _openBob(tester, deps);
      expect(find.textContaining('propose de supprimer la discussion'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear.accept')));
      await tester.pumpAndSettle();
      expect(find.text('Discussion supprimée.'), findsOneWidget);
      expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);
    });

    testWidgets('groupe supprimé pour tous par un administrateur', (tester) async {
      final deps = _deps();
      deps.messaging.seedGroup('g1', 'Voisins', members: {'u2': 'member'});
      await _start(tester, deps);
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'group.delete');
      expect(find.text('Quitter et supprimer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('group.delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('pour tous ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Groupe supprimé.'), findsOneWidget);
      expect(find.byKey(const Key('conversation.g1')), findsNothing);
      expect(find.byKey(const Key('groups.new')), findsOneWidget, reason: 'onglet Groupes');
    });

    testWidgets('un membre ne peut pas supprimer le groupe', (tester) async {
      final deps = _deps();
      deps.messaging.seedGroup('g2', 'Club', owner: 'u2', members: {'u1': 'member'});
      await _start(tester, deps);
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'group.leave');
      expect(find.byKey(const Key('group.delete')), findsNothing);
    });

    testWidgets('avis « Le groupe X a été supprimé » dans l’onglet Groupes, à fermer', (
      tester,
    ) async {
      final deps = _deps();
      deps.messaging.deletionNotices.add(
        GroupDeletionNotice(id: 'n1', title: 'Foot du jeudi', deletedAt: DateTime.now()),
      );
      await _start(tester, deps);
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      expect(find.text('Le groupe « Foot du jeudi » a été supprimé'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notice.dismiss.n1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notice.n1')), findsNothing);
      expect(deps.messaging.dismissedNotices, ['n1']);
    });
  });

  group('groupes et discussions', () {
    testWidgets('séparés par défaut ; réglage pour les mettre ensemble', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging
        ..receive('conv-bob', 'Salut')
        ..seedGroup('g1', 'Voisins', members: {'u2': 'member'})
        ..receiveInGroup('g1', 'u2', 'Réunion samedi');
      await _start(tester, deps);
      expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
      expect(find.byKey(const Key('conversation.g1')), findsNothing, reason: 'séparés');
      expect(find.byKey(const Key('filter.groups')), findsNothing);
      final nav = tester.widget<PrivioNavBar>(find.byType(PrivioNavBar));
      expect(nav.items[0].badge, 1, reason: 'Discussions : Bob seulement');
      expect(nav.items[1].badge, 1, reason: 'Groupes : le groupe non lu');

      await tester.tap(_tab('Paramètres'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, 'settings.groups_together');
      await tester.tap(find.byKey(const Key('settings.groups_together')));
      await tester.pumpAndSettle();
      expect(deps.flags.groupsTogether, isTrue);
      await tester.tap(_tab('Discussions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.g1')), findsOneWidget, reason: 'ensemble');
      expect(find.byKey(const Key('filter.groups')), findsOneWidget);
    });
  });
}
