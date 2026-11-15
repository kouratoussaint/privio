import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/util/search_text.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';

/// Lot 8.3b — Nouvelle discussion : raccourcis, liste de mes contacts, filtre immédiat,
/// recherche exacte des nouvelles personnes.
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

ConversationSummary _direct(
  String id,
  String peer,
  String name,
  String handle, {
  bool deleted = false,
  bool blocked = false,
}) => ConversationSummary(
  id: id,
  peerId: peer,
  peerHandle: handle,
  peerDisplayName: name,
  peerDeleted: deleted,
  blocked: blocked,
  unreadCount: 0,
  pinned: false,
  archived: false,
  sortAt: DateTime(2026, 11, 15),
);

Future<TestDeps> _open(WidgetTester tester) async {
  final deps = _deps();
  await deps.messaging.startDirectConversation('u2'); // Bob
  deps.messaging.archived = true; // archivée : reste un contact
  deps.messaging.extraDirect.addAll({
    'c-awa': _direct('c-awa', 'u3', 'Awa Kaboré', 'awa_s'),
    'c-issa': _direct('c-issa', 'u4', 'Issa Ouédraogo', 'issa_bf'),
    'c-zoe': _direct('c-zoe', 'u5', 'Zoé', 'zoe', blocked: true),
    'c-old': _direct('c-old', 'u6', 'Compte supprimé', 'ancien', deleted: true),
  });
  deps.messaging.seedGroup('g1', 'Famille', members: {'u2': 'member'});
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('discussions.new')));
  await tester.pumpAndSettle();
  return deps;
}

List<String> _contactOrder(WidgetTester tester) => [
  for (final e in find.byWidgetPredicate((w) {
    final k = w.key;
    return w is ListTile && k is ValueKey<String> && k.value.startsWith('search.contact.');
  }).evaluate())
    ((e.widget.key! as ValueKey<String>).value).replaceFirst('search.contact.', ''),
];

void main() {
  test('recherche locale : sans accents ni majuscules', () {
    expect(foldForSearch('Awa KABORÉ'), 'awa kabore');
    expect(foldForSearch('Ouédraogo'), 'ouedraogo');
    expect(foldForSearch('Kɔnɛ'), 'kone');
  });

  testWidgets('raccourcis et contacts par ordre alphabétique, sans bloqués ni groupes', (
    tester,
  ) async {
    await _open(tester);
    for (final k in ['new_group', 'scan', 'invite_friend', 'requests']) {
      expect(find.byKey(Key('search.$k')), findsOneWidget, reason: k);
    }
    expect(find.text('Mes contacts (3)'), findsOneWidget);
    expect(_contactOrder(tester), ['u3', 'u2', 'u4'], reason: 'Awa, Bob, Issa');
    expect(find.text('Zoé'), findsNothing, reason: 'bloquée');
    expect(find.text('Compte supprimé'), findsNothing);
    expect(find.text('Famille'), findsNothing, reason: 'les groupes ne sont pas des contacts');
    expect(find.text('@awa_s'), findsOneWidget);
  });

  testWidgets('filtre immédiat par nom ou identifiant, puis recherche sur Privio', (tester) async {
    final deps = await _open(tester);
    await tester.enterText(find.byKey(const Key('search.input')), 'kabore');
    await tester.pumpAndSettle();
    expect(_contactOrder(tester), ['u3']);
    expect(find.byKey(const Key('search.new_group')), findsNothing, reason: 'on cherche');

    await tester.enterText(find.byKey(const Key('search.input')), '@issa');
    await tester.pumpAndSettle();
    expect(_contactOrder(tester), ['u4'], reason: 'identifiant, avec ou sans @');

    await tester.enterText(find.byKey(const Key('search.input')), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun contact ne correspond.'), findsOneWidget);
    expect(find.text('Chercher « xyz » sur Privio'), findsOneWidget);
    expect(deps.messaging.handleSearches, isEmpty, reason: 'rien n’est envoyé en tapant');

    // Recherche exacte sur le serveur seulement à la demande.
    await tester.enterText(find.byKey(const Key('search.input')), 'awa_s');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search.remote')));
    await tester.pumpAndSettle();
    expect(deps.messaging.handleSearches, ['awa_s']);
    expect(find.byKey(const Key('search.result')), findsOneWidget);
  });

  testWidgets('toucher un contact ouvre la discussion, même archivée', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('search.contact.u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
  });

  testWidgets('aucun contact : message d’aide', (tester) async {
    final deps = _deps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discussions.new')));
    await tester.pumpAndSettle();
    expect(find.text('Mes contacts (0)'), findsOneWidget);
    expect(find.byKey(const Key('search.no_contact')), findsOneWidget);
  });
}
