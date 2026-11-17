import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';

/// Lot 7.2c1 — photo du groupe, recherche / filtres / actions rapides dans Groupes,
/// bouton « descendre », repère « X messages non lus ».
TestDeps _deps() =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true)..groupsTogether = false,
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

Future<void> _groups(WidgetTester tester) async {
  await tester.tap(_tab('Groupes'));
  await tester.pumpAndSettle();
}

void main() {
  group('photo du groupe', () {
    testWidgets('fiche : « Ajouter une photo » visible pour un administrateur', (tester) async {
      final deps = _deps();
      deps.messaging.seedGroup('g-voisins', 'Voisins');
      await _start(tester, deps);
      await _groups(tester);
      await tester.tap(find.byKey(const Key('conversation.g-voisins')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fiche.avatar.badge')), findsOneWidget);
      expect(find.text('Ajouter une photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('group.photo.edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group.photo.gallery')));
      await tester.pumpAndSettle();
      expect(deps.messaging.groups['g-voisins']!.avatarPath, isNotNull);
      expect(find.text('Changer la photo'), findsOneWidget);
    });

    testWidgets('fiche : un simple membre ne voit pas le bouton', (tester) async {
      final deps = _deps();
      deps.messaging.seedGroup('g-voisins', 'Voisins', owner: 'u2', members: {'u1': 'member'});
      await _start(tester, deps);
      await _groups(tester);
      await tester.tap(find.byKey(const Key('conversation.g-voisins')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group.photo.edit')), findsNothing);
      expect(find.byKey(const Key('fiche.avatar.badge')), findsNothing);
    });

    testWidgets('création : photo choisie avant, envoyée avec le groupe', (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await _groups(tester);
      await tester.tap(find.byKey(const Key('groups.new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_group.photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_group.photo.gallery')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('group.title')), 'Famille');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('group.create')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Lot 10.5 : écran plus long (type de groupe) ; le bouton entier à l'écran.
      await tester.ensureVisible(find.byKey(const Key('group.create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group.create')));
      await tester.pumpAndSettle();
      final g = deps.messaging.groups.values.single;
      expect(g.title, 'Famille');
      expect(g.avatarPath, isNotNull);
    });
  });

  group('onglet Groupes', () {
    TestDeps withGroups() {
      final deps = _deps();
      deps.messaging
        ..seedGroup('g-voisins', 'Voisins de Gounghin', members: {'u2': 'member'})
        ..seedGroup('g-foot', 'Foot du jeudi', members: {'u2': 'member'})
        ..seedGroup('g-famille', 'Famille', owner: 'u2', members: {'u1': 'member'})
        ..receiveInGroup('g-foot', 'u2', 'Match à 18 h');
      return deps;
    }

    testWidgets('recherche et filtres comme dans Discussions', (tester) async {
      final deps = withGroups();
      await _start(tester, deps);
      await _groups(tester);
      expect(find.byKey(const Key('groups.search')), findsOneWidget);
      expect(find.byKey(const Key('conversation.g-voisins')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('groups.search')), 'foot');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.g-foot')), findsOneWidget);
      expect(find.byKey(const Key('conversation.g-voisins')), findsNothing);

      await tester.enterText(find.byKey(const Key('groups.search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groups.no_match')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('groups.search')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('groups.filter.unread')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.g-foot')), findsOneWidget);
      expect(find.byKey(const Key('conversation.g-famille')), findsNothing);
    });

    testWidgets('glisser pour archiver ; ligne « Archivés » ; épingler', (tester) async {
      final deps = withGroups();
      await _start(tester, deps);
      await _groups(tester);
      await tester.drag(find.byKey(const Key('conversation.g-voisins')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.g-voisins')), findsNothing);
      expect(find.text('Archivés (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('groups.archived')));
      await tester.pumpAndSettle();
      expect(find.text('Groupes archivés'), findsOneWidget);
      expect(find.byKey(const Key('conversation.g-voisins')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(const Key('conversation.g-foot')), const Offset(300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('groups.filter.pinned')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.g-foot')), findsOneWidget);
      expect(find.byKey(const Key('conversation.g-famille')), findsNothing);
    });

    testWidgets('appui long : quitter (membre) ; supprimer pour tous (administrateur)', (
      tester,
    ) async {
      final deps = withGroups();
      await _start(tester, deps);
      await _groups(tester);
      await tester.longPress(find.byKey(const Key('conversation.g-famille')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conv.delete_group')), findsNothing, reason: 'simple membre');
      await tapMenuItem(tester, const Key('conv.leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group.leave.confirm')));
      await tester.pumpAndSettle();
      expect(deps.messaging.groups['g-famille']!.roles.containsKey('u1'), isFalse);

      await tester.longPress(find.byKey(const Key('conversation.g-voisins')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conv.leave')), findsOneWidget);
      await tapMenuItem(tester, const Key('conv.delete_group'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Voisins de Gounghin'),
        ),
        findsOneWidget,
        reason: 'confirmation de suppression pour tous',
      );
    });

    testWidgets('Discussions : les groupes archivés n’y comptent pas (séparés)', (tester) async {
      final deps = withGroups();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging.receive('conv-bob', 'Bonjour');
      await _start(tester, deps);
      await _groups(tester);
      await tester.drag(find.byKey(const Key('conversation.g-voisins')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Discussions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discussions.archived')), findsNothing);
    });
  });

  group('dans une discussion', () {
    testWidgets('repère « X messages non lus » à l’ouverture', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging
        ..receive('conv-bob', 'Un')
        ..receive('conv-bob', 'Deux')
        ..receive('conv-bob', 'Trois');
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.unread_marker')), findsOneWidget);
      expect(find.text('3 messages non lus'), findsOneWidget);
    });

    testWidgets('tout lu : pas de repère', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging.receive('conv-bob', 'Un');
      await deps.messaging.markConversation('conv-bob', readUpTo: DateTime.now());
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.unread_marker')), findsNothing);
    });

    testWidgets('loin dans la discussion : ouverture sur le premier non lu', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      for (var i = 0; i < 30; i++) {
        deps.messaging.receive('conv-bob', 'Ancien $i');
      }
      await deps.messaging.markConversation('conv-bob', readUpTo: DateTime.now());
      deps.messaging.receive('conv-bob', 'Premier non lu');
      for (var i = 0; i < 25; i++) {
        deps.messaging.receive('conv-bob', 'Nouveau $i');
      }
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      expect(find.text('26 messages non lus'), findsOneWidget);
      expect(find.text('Premier non lu').hitTestable(), findsOneWidget);
    });

    testWidgets('bouton « descendre » : nouveaux messages comptés, retour en bas', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      for (var i = 0; i < 40; i++) {
        deps.messaging.receive('conv-bob', 'Message $i');
      }
      await deps.messaging.markConversation('conv-bob', readUpTo: DateTime.now());
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('chat.scroll_down'));
      expect(button.hitTestable(), findsNothing, reason: 'en bas : pas de bouton');

      await tester.drag(find.text('Message 39'), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);

      deps.messaging.receive('conv-bob', 'Tout neuf');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Tout neuf').hitTestable(), findsOneWidget);
      expect(button.hitTestable(), findsNothing);
    });
  });
}
