import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/contact_labels.dart';
import 'package:privio/ui/features/conversations/verify_in_person.dart';

import '../helpers/fakes.dart';

/// Lot 10.4 — « Vérifié en personne » (QR temporaire, les deux côtés, badge qui tombe avec
/// un avis) et surnom privé (visible partout, « Surnom · vrai nom » dans la fiche).
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

Future<void> _start(
  WidgetTester tester,
  TestDeps deps, {
  Future<String?> Function(BuildContext)? scanner,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...deps.overrides,
        if (scanner != null) verificationScannerProvider.overrideWithValue(scanner),
      ],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _scrollTap(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await _tap(tester, key);
}

/// Remonte en haut de la fiche jusqu'à [key].
Future<void> _up(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    -150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _openBobFiche(WidgetTester tester) async {
  await _tap(tester, 'conversation.conv-bob');
  await _tap(tester, 'chat.contact');
}

void main() {
  testWidgets('surnom privé : liste, en-tête, fiche « Surnom · vrai nom », recherche', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Bonsoir');
    await _start(tester, deps);
    await _openBobFiche(tester);
    await _scrollTap(tester, 'contact.nickname');
    expect(
      find.text('Visible par vous seul, partout dans Privio. Bob ne le saura pas.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('nickname.field')), '  Grand frère ');
    await _tap(tester, 'nickname.save');
    expect(find.text('Surnom enregistré'), findsOneWidget);
    expect(deps.messaging.labels['u2']?.nickname, 'Grand frère', reason: 'gardé sur le serveur');
    await _up(tester, 'contact.name');
    expect(tester.widget<Text>(find.byKey(const Key('contact.name'))).data, 'Grand frère · Bob');

    // En-tête de la discussion, puis la liste.
    await _back(tester);
    await tester.pumpAndSettle();
    expect(find.text('Grand frère'), findsWidgets);
    await _back(tester);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('conversation.conv-bob')),
        matching: find.text('Grand frère'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bob'), findsNothing, reason: 'le surnom remplace le nom partout');

    // Recherche : par le surnom comme par le vrai nom.
    await tester.enterText(find.byKey(const Key('discussions.search')), 'frère');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('discussions.search')), 'bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('discussions.search')), '');
    await tester.pumpAndSettle();

    // Retirer le surnom : le vrai nom revient.
    await _openBobFiche(tester);
    await _scrollTap(tester, 'contact.nickname');
    await _tap(tester, 'nickname.remove');
    expect(find.text('Surnom retiré'), findsOneWidget);
    await _up(tester, 'contact.name');
    expect(tester.widget<Text>(find.byKey(const Key('contact.name'))).data, 'Bob');
    expect(deps.messaging.labels.containsKey('u2'), isFalse);
  });

  testWidgets('surnom gardé sur le serveur : retrouvé après une nouvelle installation', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.labels['u2'] = const ContactLabel(userId: 'u2', nickname: 'Tonton');
    await _start(tester, deps);
    expect(
      find.descendant(
        of: find.byKey(const Key('conversation.conv-bob')),
        matching: find.text('Tonton'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('montrer mon code : QR de 2 minutes, le contact scanne, « Vérifié en personne »', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _start(tester, deps);
    await _openBobFiche(tester);
    await _scrollTap(tester, 'contact.verify');
    expect(find.text('Est-ce bien Bob ?'), findsOneWidget);

    await _tap(tester, 'verify.show');
    expect(find.byKey(const Key('verify.qr')), findsOneWidget);
    expect(find.text('Valable encore 2:00'), findsOneWidget);
    final code = deps.messaging.verifyCodes.keys.single;
    expect(deps.messaging.verifyCodes[code]!.$1, 'u2', reason: 'code créé pour Bob seulement');
    expect(parseVerificationCode(verificationQrData(code)), code);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Valable encore 1:59'), findsOneWidget);
    deps.messaging.peerScans(code);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verify.success')), findsOneWidget);
    expect(find.text('Vous et Bob êtes vérifiés en personne'), findsOneWidget);

    await _tap(tester, 'verify.done');
    await _up(tester, 'contact.verified_badge');
    expect(find.byKey(const Key('contact.verified_badge')), findsOneWidget);
    await _back(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.verified')), findsOneWidget, reason: 'badge dans l’en-tête');
  });

  testWidgets('code expiré : « Nouveau code »', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _start(tester, deps);
    await _openBobFiche(tester);
    await _scrollTap(tester, 'contact.verify');
    await _tap(tester, 'verify.show');
    for (var i = 0; i < 121; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.text('Ce code a expiré.'), findsOneWidget);
    await _tap(tester, 'verify.renew');
    expect(find.byKey(const Key('verify.qr')), findsOneWidget);
    expect(deps.messaging.verifyCodes, hasLength(2));
  });

  testWidgets('scanner son code : vérifié ; code d’une autre personne : message clair', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    var next = 'e' * 32;
    await _start(tester, deps, scanner: (_) async => next);
    await _openBobFiche(tester);
    await _scrollTap(tester, 'contact.verify');

    await _tap(tester, 'verify.scan');
    expect(find.text('Ce code a été créé pour une autre personne.'), findsOneWidget);
    expect(find.byKey(const Key('verify.success')), findsNothing);

    next = '1' * 32;
    await _tap(tester, 'verify.scan');
    expect(deps.messaging.confirmedCodes.last, ('1' * 32, 'u2'));
    expect(find.byKey(const Key('verify.success')), findsOneWidget);
  });

  testWidgets('nouveau téléphone du contact : badge retiré, avis, « Revérifier » ou fermer', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.labels['u2'] = ContactLabel(
      userId: 'u2',
      verification: 'lapsed',
      verifiedAt: DateTime(2026, 11, 1),
      lapse: 'device',
      notice: true,
    );
    await _start(tester, deps);
    await _tap(tester, 'conversation.conv-bob');
    expect(find.byKey(const Key('chat.verified')), findsNothing);
    expect(find.byKey(const Key('chat.verify_notice')), findsOneWidget);
    expect(find.textContaining('Bob utilise maintenant un nouveau téléphone.'), findsOneWidget);

    await _tap(tester, 'chat.verify_again');
    expect(find.text('Est-ce bien Bob ?'), findsOneWidget);
    await _back(tester);
    await tester.pumpAndSettle();

    await _tap(tester, 'chat.verify_notice_close');
    expect(find.byKey(const Key('chat.verify_notice')), findsNothing);
    expect(deps.messaging.dismissedVerifyNotices, ['u2']);

    // La fiche dit pourquoi.
    await _tap(tester, 'chat.contact');
    await tester.scrollUntilVisible(
      find.byKey(const Key('contact.verify')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Vérification à refaire'), findsOneWidget);
  });

  testWidgets('groupes : surnom et badge dans la liste des membres et dans les messages', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.seedGroup('g1', 'Famille', members: const {'u2': 'member', 'u3': 'member'});
    deps.messaging.receiveInGroup('g1', 'u3', 'Coucou la famille');
    deps.messaging.labels['u3'] = ContactLabel(
      userId: 'u3',
      nickname: 'Tantie',
      verification: 'verified',
      verifiedAt: DateTime(2026, 11, 1),
    );
    await _start(tester, deps);
    await _tap(tester, 'conversation.g1');
    expect(find.text('Tantie'), findsWidgets, reason: 'nom de l’expéditrice sous son surnom');
    expect(find.text('Awa'), findsNothing);

    await _tap(tester, 'chat.contact');
    await tester.scrollUntilVisible(
      find.byKey(const Key('member.u3')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('member.u3')), matching: find.text('Tantie')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('member.verified.u3')), findsOneWidget);

    // Carte de la personne : « Surnom · vrai nom », surnom modifiable.
    await _tap(tester, 'member.u3');
    expect(tester.widget<Text>(find.byKey(const Key('card.name'))).data, 'Tantie · Awa');
    expect(find.byKey(const Key('card.verified')), findsOneWidget);
    await _scrollTap(tester, 'card.nickname');
    await tester.enterText(find.byKey(const Key('nickname.field')), 'Tata');
    await _tap(tester, 'nickname.save');
    expect(deps.messaging.labels['u3']?.nickname, 'Tata');
  });
}
