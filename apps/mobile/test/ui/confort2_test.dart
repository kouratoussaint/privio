import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 7.2c2 — épingler, favoris, sélection multiple, infos d'un message,
/// « Mentions seulement ».
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

Future<TestDeps> _openBob(WidgetTester tester, {List<String> bodies = const ['Un', 'Deux']}) async {
  final deps = _deps();
  await deps.messaging.startDirectConversation('u2');
  for (final b in bodies) {
    deps.messaging.receive('conv-bob', b);
  }
  await _start(tester, deps);
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _action(WidgetTester tester, String text, String action) async {
  await tester.longPress(find.text(text));
  await tester.pumpAndSettle();
  final f = find.byKey(Key('action.$action'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat.input')), text);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.send')));
  await tester.pumpAndSettle();
}

void main() {
  group('épingler', () {
    testWidgets('épingler : bandeau, icône sur la bulle ; désépingler', (tester) async {
      final deps = await _openBob(tester);
      expect(find.byKey(const Key('chat.pinned_banner')), findsNothing);
      await _action(tester, 'Un', 'pin');
      expect(deps.messaging.pins['conv-bob'], isNotEmpty);
      expect(find.byKey(const Key('chat.pinned_banner')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('chat.pinned_banner')),
          matching: find.text('Bob : Un'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('bubble.pinned')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat.pinned_banner')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message_ref.sheet')), findsNothing, reason: 'déjà affiché');

      await _action(tester, 'Un', 'pin');
      expect(find.byKey(const Key('chat.pinned_banner')), findsNothing);
      expect(find.byKey(const Key('bubble.pinned')), findsNothing);
    });

    testWidgets('trois au plus : le quatrième est refusé avec une explication', (tester) async {
      await _openBob(tester, bodies: ['A1', 'A2', 'A3', 'A4']);
      for (final b in ['A1', 'A2', 'A3']) {
        await _action(tester, b, 'pin');
      }
      expect(find.text('Message épinglé 1/3'), findsOneWidget);
      await _action(tester, 'A4', 'pin');
      expect(find.textContaining('Trois messages sont déjà épinglés'), findsOneWidget);
    });

    testWidgets('groupe : un membre ne peut pas épingler, un administrateur oui', (tester) async {
      final deps = _deps();
      deps.messaging
        ..seedGroup('g-a', 'Mon groupe', members: {'u2': 'member'})
        ..seedGroup('g-b', 'Groupe de Bob', owner: 'u2', members: {'u1': 'member'})
        ..receiveInGroup('g-a', 'u2', 'Dans mon groupe')
        ..receiveInGroup('g-b', 'u2', 'Chez Bob');
      await _start(tester, deps);
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g-b')));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Chez Bob'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action.pin')), findsNothing);
      expect(find.byKey(const Key('action.favorite')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g-a')));
      await tester.pumpAndSettle();
      await _action(tester, 'Dans mon groupe', 'pin');
      expect(find.byKey(const Key('chat.pinned_banner')), findsOneWidget);
    });
  });

  group('favoris', () {
    testWidgets('ajouter, retrouver dans la fiche, revenir au message, retirer', (tester) async {
      final deps = await _openBob(tester);
      await _action(tester, 'Deux', 'favorite');
      expect(deps.messaging.favorites, hasLength(1));
      expect(find.byKey(const Key('bubble.favorite')), findsOneWidget);
      expect(find.text('Ajouté aux favoris.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('fiche.favorites')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('fiche.favorites')),
          matching: find.textContaining('1 message'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('fiche.favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fiche.favorites')));
      await tester.pumpAndSettle();
      expect(find.text('Messages favoris'), findsWidgets);
      final id = deps.messaging.favorites.single;
      expect(find.byKey(Key('favorite.$id')), findsOneWidget);
      await tester.tap(find.byKey(Key('favorite.$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.input')), findsOneWidget, reason: 'retour à la discussion');
      expect(find.text('Deux').hitTestable(), findsOneWidget);

      await _action(tester, 'Deux', 'favorite');
      expect(deps.messaging.favorites, isEmpty);
      expect(find.byKey(const Key('bubble.favorite')), findsNothing);
    });
  });

  group('sélection multiple', () {
    testWidgets('sélectionner, compter, mettre en favoris, annuler par « retour »', (tester) async {
      final deps = await _openBob(tester, bodies: ['S1', 'S2', 'S3']);
      await _action(tester, 'S1', 'select');
      expect(find.byKey(const Key('select.bar')), findsOneWidget);
      expect(find.text('1 sélectionné'), findsOneWidget);
      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();
      expect(find.text('2 sélectionnés'), findsOneWidget);
      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();
      expect(find.text('1 sélectionné'), findsOneWidget);
      await tester.tap(find.text('S3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select.favorite')));
      await tester.pumpAndSettle();
      expect(deps.messaging.favorites, hasLength(2));
      expect(find.text('2 messages ajoutés aux favoris.'), findsOneWidget);
      expect(find.byKey(const Key('select.bar')), findsNothing);

      await _action(tester, 'S1', 'select');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select.bar')), findsNothing);
      expect(
        find.byKey(const Key('chat.input')),
        findsOneWidget,
        reason: 'toujours dans la discussion',
      );
    });

    testWidgets('supprimer : pour moi ; pour tout le monde seulement si tous sont à moi', (
      tester,
    ) async {
      final deps = await _openBob(tester, bodies: ['De Bob']);
      await _send(tester, 'Le mien 1');
      await _send(tester, 'Le mien 2');

      await _action(tester, 'De Bob', 'select');
      await tester.tap(find.text('Le mien 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select.delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select.delete_all')), findsNothing, reason: 'un message de Bob');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('De Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Le mien 2'));
      await tester.pumpAndSettle();
      expect(find.text('2 sélectionnés'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select.delete_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select.delete_all.confirm')));
      await tester.pumpAndSettle();
      final mine = deps.messaging.messages['conv-bob']!.where(
        (m) => m.senderId == FakeMessagingApi.me && !m.isSystem,
      );
      expect(mine.every((m) => m.isDeleted), isTrue);
      expect(find.byKey(const Key('select.bar')), findsNothing);

      await _action(tester, 'De Bob', 'select');
      await tester.tap(find.byKey(const Key('select.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select.delete_me')));
      await tester.pumpAndSettle();
      expect(deps.messaging.hiddenForMe, hasLength(1));
    });
  });

  group('infos d’un message', () {
    testWidgets('mon message : distribué à quelle heure, pas encore lu', (tester) async {
      final deps = await _openBob(tester);
      await _send(tester, 'Tu as reçu ?');
      await _action(tester, 'Tu as reçu ?', 'info');
      expect(find.byKey(const Key('message_info.sheet')), findsOneWidget);
      expect(find.textContaining('Distribué à'), findsOneWidget);
      expect(find.text('Pas encore lu'), findsOneWidget);
      expect(deps.messaging.messages['conv-bob'], isNotEmpty);
    });

    testWidgets('lecture non partagée ; pas d’« Infos » sur le message des autres', (tester) async {
      final deps = await _openBob(tester);
      await _send(tester, 'Lu ?');
      final mine = deps.messaging.messages['conv-bob']!.last;
      deps.messaging.receipts[mine.id] = [
        const MessageReceipt(
          userId: 'u2',
          name: 'Bob',
          delivered: true,
          read: false,
          receiptsHidden: true,
        ),
      ];
      await _action(tester, 'Lu ?', 'info');
      expect(find.text('Lecture non partagée'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Un'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action.info')), findsNothing);
    });
  });

  testWidgets('groupe : « Mentions seulement »', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g-a', 'Mon groupe', members: {'u2': 'member'});
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('group.mentions_only')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final tile = find.byKey(const Key('group.mentions_only'));
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(deps.messaging.notifyModes['g-a'], 'mentions');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });
}
