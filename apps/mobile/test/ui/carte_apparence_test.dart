import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/handle/handle_rules.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/groups/join_group_screen.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 8.1a — carte d'une personne, apparence (thème, taille du texte), QR code.
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

Future<void> _start(WidgetTester tester, TestDeps deps, {List<Override> extra = const []}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...deps.overrides, ...extra],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

/// Groupe « Famille » avec Bob (contact) et Awa (pas un contact), un message de chacun.
Future<TestDeps> _openFamily(WidgetTester tester, {bool bobIsContact = true}) async {
  final deps = _deps();
  if (bobIsContact) await deps.messaging.startDirectConversation('u2');
  deps.messaging
    ..seedGroup('g1', 'Famille', members: {'u2': 'member', 'u3': 'member'})
    ..receiveInGroup('g1', 'u2', 'Salut de Bob')
    ..receiveInGroup('g1', 'u3', 'Bonjour de Awa');
  await _start(tester, deps);
  await tester.tap(_tab('Groupes'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.g1')));
  await tester.pumpAndSettle();
  return deps;
}

Finder _avatarOf(TestDeps deps, String body) {
  final m = deps.messaging.messages['g1']!.firstWhere((m) => m.body == body);
  return find.byKey(Key('message.avatar.${m.id}'));
}

void main() {
  group('carte d’une personne', () {
    testWidgets('photo d’un membre qui n’est pas un contact : sa carte', (tester) async {
      final deps = await _openFamily(tester);
      await tester.tap(_avatarOf(deps, 'Bonjour de Awa'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person.card')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('card.name'))).data, 'Awa');
      expect(find.text('@awa_s'), findsOneWidget);
      expect(find.byKey(const Key('card.manage')), findsNothing);
      expect(
        find.byKey(const Key('card.request')).evaluate().isNotEmpty ||
            find.byKey(const Key('card.write')).evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.byKey(const Key('card.block')), findsOneWidget);
      expect(find.byKey(const Key('card.report')), findsOneWidget);
    });

    testWidgets('nom de l’auteur d’un contact : sa fiche', (tester) async {
      await _openFamily(tester);
      final sender = find.byWidgetPredicate(
        (w) => w is Text && w.key == const Key('bubble.sender') && w.data == 'Bob',
      );
      expect(sender, findsOneWidget);
      await tester.tap(sender);
      await tester.pumpAndSettle();
      expect(sender, findsNothing, reason: 'la discussion a laissé place à la fiche');
      expect(find.byKey(const Key('contact.ttl')), findsOneWidget);
      expect(find.byKey(const Key('person.card')), findsNothing);
    });

    testWidgets('bloquer depuis la carte', (tester) async {
      final deps = await _openFamily(tester);
      await tester.tap(_avatarOf(deps, 'Bonjour de Awa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card.block')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card.block.confirm')));
      await tester.pumpAndSettle();
      expect(deps.messaging.blocked, contains('u3'));
      expect(find.byKey(const Key('person.card')), findsNothing);
      expect(find.text('Awa est bloqué.'), findsOneWidget);
    });

    testWidgets('liste des membres : simple membre, carte sans « Gérer » ; moi : Ma fiche', (
      tester,
    ) async {
      final deps = _deps();
      deps.messaging.seedGroup(
        'g1',
        'Famille',
        owner: 'u2',
        members: {'u1': 'member', 'u3': 'member'},
      );
      await _start(tester, deps);
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      final awa = find.byKey(const Key('member.u3'));
      await tester.scrollUntilVisible(awa, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(awa);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person.card')), findsOneWidget);
      expect(find.byKey(const Key('card.manage')), findsNothing);
      await tester.tapAt(const Offset(20, 20)); // fermer la feuille
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member.u1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my.name')), findsOneWidget, reason: 'Ma fiche');
    });

    testWidgets('liste des discussions : toucher la photo ouvre la fiche', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.avatar.conv-bob')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contact.ttl')), findsOneWidget);
    });
  });

  group('QR code de l’identifiant', () {
    test('lecture du QR code', () {
      expect(profileQrData('awa_s'), 'privio:@awa_s');
      expect(parseProfileCode('privio:@awa_s'), 'awa_s');
      expect(parseProfileCode('PRIVIO:@Awa_S'), 'awa_s');
      expect(parseProfileCode('@awa_s'), isNull);
      expect(parseProfileCode('https://exemple.bf'), isNull);
      expect(parseProfileCode('privio:@a'), isNull, reason: 'identifiant invalide');
      expect(parseProfileCode('PRV-7K3Q9X'), isNull, reason: 'code de groupe');
    });

    testWidgets('Ma fiche → Mon QR code', (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await tester.tap(_tab('Paramètres'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.profile')));
      await tester.pumpAndSettle();
      final qr = find.byKey(const Key('my.qr'));
      await tester.scrollUntilVisible(qr, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(qr);
      await tester.pumpAndSettle();
      await tester.tap(qr);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my.qr.code')), findsOneWidget);
      expect(find.text('@toussaint_bf'), findsWidgets);
    });

    testWidgets('scanner le QR code d’Awa : sa carte', (tester) async {
      final deps = _deps();
      await _start(
        tester,
        deps,
        extra: [profileQrScannerProvider.overrideWithValue((_) async => 'awa_s')],
      );
      await tester.tap(find.byKey(const Key('discussions.new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search.scan')));
      await tester.pumpAndSettle();
      expect(deps.messaging.handleSearches, ['awa_s']);
      expect(find.byKey(const Key('person.card')), findsOneWidget);
      expect(find.text('@awa_s'), findsOneWidget);
    });
  });

  group('apparence', () {
    testWidgets('thème sombre et très grand texte, gardés sur le téléphone', (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await tester.tap(_tab('Paramètres'));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('settings.appearance'));
      await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appearance.theme.dark')));
      await tester.pumpAndSettle();
      expect(deps.flags.theme, 'dark');
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byKey(const Key('appearance.screen')))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.byKey(const Key('appearance.size.xlarge')));
      await tester.pumpAndSettle();
      expect(deps.flags.size, 'xlarge');
      final scaler = MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('appearance.preview'))),
      );
      expect(scaler.scale(10), closeTo(13, 0.01));
    });

    testWidgets('réglage relu au démarrage', (tester) async {
      final deps = _deps();
      deps.flags
        ..theme = 'light'
        ..size = 'small';
      await _start(tester, deps);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);
      final scaler = MediaQuery.textScalerOf(tester.element(find.byType(PrivioNavBar)));
      expect(scaler.scale(10), closeTo(9, 0.01));
    });
  });
}
