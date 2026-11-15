import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/util/search_text.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/conversations/impersonation.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 8.4c — alerte anti-usurpation (nom proche d'un contact) et « Ce que Privio garde ».
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

ConversationSummary _direct(String id, String peer, String name, String handle) =>
    ConversationSummary(
      id: id,
      peerId: peer,
      peerHandle: handle,
      peerDisplayName: name,
      peerDeleted: false,
      blocked: false,
      unreadCount: 0,
      pinned: false,
      archived: false,
      sortAt: DateTime(2026, 11, 15),
    );

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

void main() {
  test('noms qu’on pourrait confondre', () {
    expect(namesLookAlike('Amina Diallo', 'amina diallo'), isTrue);
    expect(namesLookAlike('Amina Diallo', 'Amina Dialo'), isTrue, reason: 'une lettre');
    expect(namesLookAlike('Issa Ouédraogo', 'Issa Ouedraogo'), isTrue, reason: 'accent');
    expect(namesLookAlike('Issa Ouédraogo', 'IssaOuedraogo'), isTrue, reason: 'espace');
    expect(namesLookAlike('Aminata Diallo', 'Amina Diallo'), isFalse, reason: 'autre prénom');
    expect(namesLookAlike('Bob', 'Bob'), isTrue);
    expect(namesLookAlike('Bob', 'Rob'), isFalse, reason: 'nom court : identique seulement');
    expect(namesLookAlike('Awa Sawadogo', 'Marc Koné'), isFalse);
  });

  test('pas d’alerte pour le contact lui-même', () {
    final list = [_direct('c1', 'u2', 'Amina Diallo', 'amina_d')];
    expect(lookAlikeContact(list, userId: 'u2', name: 'Amina Diallo'), isNull);
    expect(lookAlikeContact(list, userId: 'u9', name: 'Amina Dialo')?.peerId, 'u2');
  });

  testWidgets('demande de connexion d’un compte au nom d’un contact', (tester) async {
    final deps = _deps();
    deps.messaging.extraDirect['c-amina'] = _direct('c-amina', 'u7', 'Amina Diallo', 'amina_d');
    deps.messaging.requests.add(
      ConnectionRequest(
        id: 'req-x',
        incoming: true,
        userId: 'u9',
        handle: 'amina_d2',
        displayName: 'Amina Dialo',
        status: 'pending',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      ),
    );
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.requests')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('impersonation.warning')), findsOneWidget);
    expect(
      find.textContaining('vous avez déjà un contact nommé Amina Diallo (@amina_d)'),
      findsOneWidget,
    );
    expect(find.textContaining('@amina_d2'), findsWidgets);
  });

  testWidgets('recherche : alerte sur le résultat, pas sur un vrai contact', (tester) async {
    final deps = _deps();
    deps.messaging.extraDirect['c-awa'] = _direct('c-awa', 'u8', 'Awa', 'awa_vraie');
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.input')), 'awa_s');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.remote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.result')), findsOneWidget);
    expect(find.byKey(const Key('impersonation.warning')), findsOneWidget);

    // Bob est un vrai contact : aucune alerte sur son résultat.
    await deps.messaging.startDirectConversation('u2');
    await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.remote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('impersonation.warning')), findsNothing);
  });

  testWidgets('groupe : carte d’un membre au nom d’un contact', (tester) async {
    final deps = _deps();
    deps.messaging.extraDirect['c-awa'] = _direct('c-awa', 'u8', 'Awa', 'awa_vraie');
    deps.messaging
      ..seedGroup('g1', 'Famille', members: {'u3': 'member'})
      ..receiveInGroup('g1', 'u3', 'Bonjour de Awa');
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g1')));
    await tester.pumpAndSettle();
    final m = deps.messaging.messages['g1']!.firstWhere((m) => m.body == 'Bonjour de Awa');
    await tester.tap(find.byKey(Key('message.avatar.${m.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person.card')), findsOneWidget);
    expect(find.byKey(const Key('impersonation.warning')), findsOneWidget);
  });

  testWidgets('« Ce que Privio garde » depuis Aide et Confidentialité', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.help');
    await tester.tap(find.byKey(const Key('help.keeps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keeps.screen')), findsOneWidget);
    expect(find.textContaining('72 h au plus'), findsOneWidget);
    expect(find.textContaining('chiffr'), findsNothing, reason: 'décision du 15/11/2026');
    await tester.scrollUntilVisible(
      find.text('Pas de publicité, pas de revente de vos données.'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.privacy');
    await tester.tap(find.byKey(const Key('privacy.keeps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keeps.screen')), findsOneWidget);
  });
}
