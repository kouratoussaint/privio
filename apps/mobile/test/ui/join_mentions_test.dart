import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/groups/join_group_screen.dart';
import 'package:privio/ui/features/groups/mentions.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 7.1b — rejoindre un groupe par code ou QR code, demandes d'adhésion, @mentions.
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

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Finder get _list => find.byType(Scrollable).first;

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 150, scrollable: _list);
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, TestDeps deps, {List<Override> extra = const []}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...deps.overrides, ...extra],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(_tab('Groupes'));
  await tester.pumpAndSettle();
}

Future<void> _openGroup(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('conversation.$id')));
  await tester.pumpAndSettle();
}

Future<void> _openFiche(WidgetTester tester, String id) async {
  await _openGroup(tester, id);
  await tester.tap(find.byKey(const Key('chat.contact')));
  await tester.pumpAndSettle();
}

void main() {
  group('logique', () {
    test('code lu dans une saisie ou un QR code', () {
      expect(parseInviteCode('PRV-7K3Q9X'), 'PRV-7K3Q9X');
      expect(parseInviteCode(' prv 7k3q9x '), 'PRV-7K3Q9X');
      expect(parseInviteCode('7k3q9x'), 'PRV-7K3Q9X');
      expect(parseInviteCode('PRV-7K3Q9'), isNull, reason: 'incomplet');
      expect(parseInviteCode('PRV-7K3'), isNull, reason: 'incomplet, pas « PRV7K3 »');
      expect(parseInviteCode('PRV-7K3Q0O'), isNull, reason: '0 et O exclus');
      expect(parseInviteCode('https://exemple.com'), isNull);
    });

    test('mention en cours : « @ » en début de mot seulement', () {
      TextEditingValue v(String t) => TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
      expect(activeMention(v('Salut @Aw'))?.query, 'Aw');
      expect(activeMention(v('@'))?.query, '');
      expect(activeMention(v('mail@exemple')), isNull);
      expect(activeMention(v('Salut')), isNull);
    });

    test('membres proposés : sans soi-même, accents ignorés', () {
      const members = [
        GroupMember(userId: 'u1', displayName: 'Toussaint', role: 'owner'),
        GroupMember(userId: 'u3', displayName: 'Awa Traoré', role: 'member'),
        GroupMember(userId: 'u5', displayName: 'Gaël', role: 'member'),
        GroupMember(userId: 'u6', displayName: 'Invité', role: 'member', invited: true),
      ];
      expect(mentionCandidates(members, '', me: 'u1').map((m) => m.userId), ['u3', 'u5']);
      expect(mentionCandidates(members, 'trao', me: 'u1').single.userId, 'u3');
      expect(mentionCandidates(members, 'gael', me: 'u1').single.userId, 'u5');
      expect(mentionedIds('@Awa Traoré tu viens ?', {'u3': 'Awa Traoré', 'u5': 'Gaël'}), [
        'u3',
      ], reason: 'Gaël a été effacé du texte');
    });
  });

  testWidgets('administrateur : code et QR code, changement du code', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g-voisins', 'Voisins', members: {'u2': 'member'});
    await _start(tester, deps);
    await _openFiche(tester, 'g-voisins');
    await _scrollTo(tester, 'group.code');
    await tester.tap(find.byKey(const Key('group.code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('code.qr')), findsOneWidget);
    expect(find.text('PRV-7K3Q2X'), findsOneWidget);
    expect(find.textContaining('vous envoie une demande'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    await tester.tap(find.byKey(const Key('code.copy')));
    await tester.pumpAndSettle();
    expect(copied, 'PRV-7K3Q2X');
    expect(find.text('Code copié.'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('code.copy'))))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await _scrollTo(tester, 'code.reset');
    await tester.tap(find.byKey(const Key('code.reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('code.reset.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('PRV-7K3Q3X'), findsOneWidget, reason: 'nouveau code');
    expect(deps.messaging.codes.keys, ['PRV-7K3Q3X'], reason: 'l’ancien ne marche plus');
  });

  testWidgets('administrateur : approbation et demandes reçues', (tester) async {
    final deps = _deps();
    deps.messaging
      ..seedGroup('g-voisins', 'Voisins', members: {'u2': 'member'})
      ..joinRequests['g-voisins'] = [
        JoinRequest(
          id: 'r1',
          userId: 'u3',
          displayName: 'Awa',
          handle: 'awa',
          createdAt: DateTime.now(),
        ),
        JoinRequest(
          id: 'r2',
          userId: 'u4',
          displayName: 'Issa',
          createdAt: DateTime.now(),
          wasRemoved: true,
        ),
      ];
    await _start(tester, deps);
    await _openFiche(tester, 'g-voisins');

    await _scrollTo(tester, 'group.join_approval');
    await tester.tap(find.byKey(const Key('group.join_approval')));
    await tester.pumpAndSettle();
    expect(deps.messaging.groups['g-voisins']!.joinApproval, isFalse);
    expect(find.text('Avec le code, on entre directement'), findsOneWidget);

    await _scrollTo(tester, 'group.join_requests');
    expect(find.text('DEMANDES POUR REJOINDRE (2)'), findsOneWidget);
    await _scrollTo(tester, 'join_request.r2');
    expect(find.text('déjà retiré du groupe'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('join_request.r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('join_request.r1.approve')));
    await tester.pumpAndSettle();
    expect(find.text('Awa a rejoint le groupe.'), findsOneWidget);
    expect(deps.messaging.groups['g-voisins']!.roles['u3'], 'member');
    await tester.tap(find.byKey(const Key('join_request.r2.decline')));
    await tester.pumpAndSettle();
    expect(deps.messaging.joinResponses, [('r1', true), ('r2', false)]);
    expect(find.byKey(const Key('group.join_requests')), findsNothing);
  });

  testWidgets('un membre ne voit ni code ni demandes', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g-club', 'Club', owner: 'u2', members: {'u1': 'member'});
    await _start(tester, deps);
    await _openFiche(tester, 'g-club');
    await _scrollTo(tester, 'group.leave');
    expect(find.byKey(const Key('group.code')), findsNothing);
    expect(find.byKey(const Key('group.join_approval')), findsNothing);
  });

  testWidgets('rejoindre : code incomplet, faux, puis demande envoyée et annulée', (tester) async {
    final deps = _deps();
    deps.messaging.codePreviews['PRV-7K3Q9X'] = const GroupPreview(
      status: JoinStatus.approval,
      conversationId: 'g-ext',
      title: 'Tontine du quartier',
      memberCount: 12,
    );
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('groups.join')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('join.code')), 'PRV-7K3');
    await tester.tap(find.byKey(const Key('join.preview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Code incomplet'), findsOneWidget);
    expect(deps.messaging.previewedCodes, isEmpty, reason: 'pas d’essai perdu');

    await tester.enterText(find.byKey(const Key('join.code')), 'PRV-7K3Q8X');
    await tester.tap(find.byKey(const Key('join.preview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ne correspond à aucun groupe'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('join.code')), 'prv 7k3q9x');
    await tester.tap(find.byKey(const Key('join.preview')));
    await tester.pumpAndSettle();
    expect(deps.messaging.previewedCodes.last, 'PRV-7K3Q9X');
    expect(find.text('Tontine du quartier'), findsOneWidget);
    expect(find.text('12 membres'), findsOneWidget);
    await tester.tap(find.byKey(const Key('join.submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Votre demande est envoyée'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Demandes envoyées'), findsOneWidget);
    expect(find.byKey(const Key('my_join.g-ext')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my_join.cancel.g-ext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_join.g-ext')), findsNothing);
    expect(deps.messaging.myJoinRequests, isEmpty);
  });

  testWidgets('rejoindre par QR code : entrée directe, le groupe s’ouvre', (tester) async {
    final deps = _deps();
    deps.messaging.codePreviews['PRV-7K3Q9X'] = const GroupPreview(
      status: JoinStatus.open,
      conversationId: 'g-ext',
      title: 'Tontine du quartier',
      memberCount: 3,
    );
    await _start(
      tester,
      deps,
      extra: [qrScannerProvider.overrideWithValue((_) async => 'prv-7k3q9x')],
    );
    await tester.tap(find.byKey(const Key('groups.join')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('join.scan')));
    await tester.pumpAndSettle();
    expect(find.text('Vous pouvez rejoindre ce groupe directement.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('join.submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.members')), findsOneWidget, reason: 'le groupe est ouvert');
    expect(deps.messaging.groups['g-ext']!.roles['u1'], 'member');
  });

  testWidgets('@mention : « @ » propose les membres ; la mention part avec le message', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup(
      'g-voisins',
      'Voisins',
      members: {'u2': 'member', 'u3': 'member', 'u4': 'admin'},
    );
    await _start(tester, deps);
    await _openGroup(tester, 'g-voisins');

    await tester.enterText(find.byKey(const Key('chat.input')), 'Salut @');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention.list')), findsOneWidget);
    expect(find.byKey(const Key('mention.option.u1')), findsNothing, reason: 'pas soi-même');
    expect(find.byKey(const Key('mention.option.u2')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat.input')), 'Salut @aw');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention.option.u2')), findsNothing);
    await tester.tap(find.byKey(const Key('mention.option.u3')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('chat.input')));
    expect(field.controller!.text, 'Salut @Awa ');
    expect(find.byKey(const Key('mention.list')), findsNothing);

    await tester.enterText(find.byKey(const Key('chat.input')), 'Salut @Awa tu viens ?');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.sentMentions.last, ['u3']);
    expect(find.byKey(const Key('bubble.mentions')), findsOneWidget, reason: 'mise en valeur');
  });

  testWidgets('@mention effacée avant l’envoi : personne n’est mentionné', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g-voisins', 'Voisins', members: {'u3': 'member'});
    await _start(tester, deps);
    await _openGroup(tester, 'g-voisins');
    await tester.enterText(find.byKey(const Key('chat.input')), '@');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mention.option.u3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat.input')), 'Finalement non');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.sentMentions.last, isEmpty);
  });

  testWidgets('message reçu qui me mentionne : mention mise en valeur', (tester) async {
    final deps = _deps();
    deps.messaging
      ..seedGroup('g-voisins', 'Voisins', members: {'u3': 'member'})
      ..receiveInGroup('g-voisins', 'u3', '@Toussaint tu viens ?', mentions: ['u1']);
    await _start(tester, deps);
    await _openGroup(tester, 'g-voisins');
    expect(find.byKey(const Key('bubble.mentions')), findsOneWidget);
    final rich = tester.widget<Text>(find.byKey(const Key('bubble.mentions')));
    final mention = (rich.textSpan! as TextSpan).children!.first as TextSpan;
    expect(mention.text, '@Toussaint');
    expect(mention.style?.backgroundColor, isNotNull, reason: 'c’est moi : surligné');
  });

  testWidgets('discussion à deux : pas de liste « @ »', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat.input')), '@');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention.list')), findsNothing);
  });
}
