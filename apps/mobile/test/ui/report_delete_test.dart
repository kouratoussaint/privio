import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/session_controller.dart';

import '../helpers/fakes.dart';

/// Lot 2.5 — signalement, assistance, suppression de compte.
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

Future<void> _launch(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Message abusif');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Liste paresseuse : l'élément n'existe qu'une fois proche de l'écran.
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signaler un message : motif, copie jointe avec accord, blocage', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Message abusif'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action.report')));
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('report.submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull, reason: 'motif obligatoire');
    await _scrollTap(tester, find.byKey(const Key('report.harassment')));
    await _scrollTap(tester, find.byKey(const Key('report.block')));
    await _scrollTap(tester, submit);

    final r = deps.messaging.reports.single;
    expect(r['reason'], 'harassment');
    expect(r['user'], 'u2');
    expect(r['message'], isNotNull);
    expect(r['include'], isTrue);
    expect(deps.messaging.blocked, contains('u2'));
    expect(find.textContaining('signalement est transmis'), findsOneWidget);
  });

  testWidgets('sans accord : la copie du message n’est pas jointe', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Message abusif'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action.report')));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.byKey(const Key('report.spam')));
    await _scrollTap(tester, find.byKey(const Key('report.include')));
    await _scrollTap(tester, find.byKey(const Key('report.submit')));
    expect(deps.messaging.reports.single['include'], isFalse);
  });

  testWidgets('signaler un contact depuis sa fiche', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact.report')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report.include')), findsNothing, reason: 'pas de message visé');
    await _scrollTap(tester, find.byKey(const Key('report.impersonation')));
    await _scrollTap(tester, find.byKey(const Key('report.submit')));
    expect(deps.messaging.reports.single['message'], isNull);
    expect(deps.messaging.reports.single['reason'], 'impersonation');
  });

  testWidgets('aide : questions fréquentes et contact de l’assistance', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.byKey(const Key('settings.help')));
    expect(find.text('Quand mes messages sont-ils effacés ?'), findsOneWidget);
    await _scrollTap(tester, find.byKey(const Key('help.contact')));
    await tester.enterText(find.byKey(const Key('help.message')), 'Je ne reçois pas les SMS');
    await tester.tap(find.byKey(const Key('help.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.reports.single['reason'], 'support');
    expect(deps.messaging.reports.single['details'], 'Je ne reçois pas les SMS');
  });

  testWidgets('supprimer son compte : confirmation, effacement local, retour à l’accueil', (
    tester,
  ) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(deps.store.data, isNotNull, reason: 'des messages sont enregistrés sur le téléphone');

    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await _scrollTap(tester, find.byKey(const Key('settings.delete')));
    final submit = find.byKey(const Key('delete.submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('delete.confirm')), 'supprimer');
    await tester.pump();
    await _scrollTap(tester, submit);

    expect(deps.messaging.accountDeleted, isTrue);
    expect(deps.store.data, isNull, reason: 'cache local détruit');
    expect(deps.auth.signedIn, isFalse);
    expect(find.text(kAccountDeletedNotice), findsOneWidget);
  });
}
