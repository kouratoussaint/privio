import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/services/push_service.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/state/session_controller.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 5.4 — comptes et assistance : recherche, fiche, actions, réponses, « Mes demandes »,
/// téléphone déconnecté par l'assistance.
const _pin = '258014';

TestDeps _deps({bool admin = false}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = admin
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

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openConsoleTab(WidgetTester tester, TestDeps deps, String tab) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await _start(tester, deps);
  await _type(tester, _pin);
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.console')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  // Lot 7.3a : une ligne de plus dans Paramètres : on s'assure qu'elle est bien visible.
  await tester.ensureVisible(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await tester.ensureVisible(find.byKey(Key('console.tab.$tab')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('console.tab.$tab')));
  await tester.pumpAndSettle();
}

final _bob = ConsoleAccount(
  userId: 'u2',
  handle: 'bob_ouaga',
  displayName: 'Bob Ouédraogo',
  createdAt: DateTime(2026, 11, 1),
  lastSeenDay: DateTime(2026, 11, 13),
  platform: 'android',
  appVersion: '0.1.0+30',
  pushEnabled: true,
  directs: 4,
  groups: 2,
  reportsReceived90d: 1,
  support: [SupportRequest(id: 's1', createdAt: DateTime(2026, 11, 13, 9), details: 'Vocaux')],
);

void main() {
  testWidgets('comptes : recherche, fiche sans numéro, avertissement avec motif', (tester) async {
    final deps = _deps(admin: true)..admin.accounts['u2'] = _bob;
    await _openConsoleTab(tester, deps, 'accounts');
    await tester.enterText(find.byKey(const Key('accounts.query')), '7000');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    expect(
      find.text('Saisissez le numéro complet (8 chiffres, ou avec l’indicatif).'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('accounts.query')), '@bob');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    expect(find.text('@bob_ouaga'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account.u2')));
    await tester.pumpAndSettle();
    expect(find.text('Actif'), findsOneWidget);
    expect(find.text('Android · version 0.1.0+30'), findsOneWidget);
    expect(find.text('4 · groupes : 2'), findsOneWidget);
    expect(find.textContaining('+226'), findsNothing);

    await tester.tap(find.byKey(const Key('account.warn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decision.reason.spam')));
    await tester.enterText(find.byKey(const Key('decision.note')), 'Publicité répétée');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.userSanctions.single, ('u2', 'warn', 'spam', 'Publicité répétée', 7));
    expect(find.text('Avertissement envoyé.'), findsOneWidget);
  });

  testWidgets('déconnecter le téléphone (perte ou vol)', (tester) async {
    final deps = _deps(admin: true)..admin.accounts['u2'] = _bob;
    await _openConsoleTab(tester, deps, 'accounts');
    await tester.enterText(find.byKey(const Key('accounts.query')), 'ouédraogo');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.u2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('account.disconnect')));
    await tester.tap(find.byKey(const Key('account.disconnect')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter le téléphone'), findsWidgets);
    await tester.enterText(find.byKey(const Key('decision.note')), 'Téléphone volé');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.disconnected, ['u2']);
    expect(find.text('Téléphone déconnecté.'), findsOneWidget);
  });

  testWidgets('deux étapes : code oublié, réinitialisation avec motif (lot 8.4a)', (tester) async {
    final deps = _deps(admin: true)
      ..admin.accounts['u2'] = _bob
      ..admin.twoStepAccounts['u2'] = DateTime(2026, 11, 15, 10, 30);
    await _openConsoleTab(tester, deps, 'accounts');
    await tester.enterText(find.byKey(const Key('accounts.query')), '@bob');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.u2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('code oublié, demande du'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('account.two_step_reset')));
    await tester.tap(find.byKey(const Key('account.two_step_reset')));
    await tester.pumpAndSettle();
    expect(find.textContaining('vérifié l’identité'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('decision.note')), 'Identité vérifiée par appel');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.twoStepResets, [('u2', 'Identité vérifiée par appel')]);
    expect(find.text('Vérification en deux étapes réinitialisée.'), findsOneWidget);
    expect(find.byKey(const Key('account.two_step_reset')), findsNothing);
  });

  testWidgets('compte de l’administration : aucune action', (tester) async {
    final deps = _deps(admin: true)
      ..admin.accounts['u1'] = ConsoleAccount(
        userId: 'u1',
        handle: 'toussaint_bf',
        displayName: 'Toussaint',
        createdAt: DateTime(2026, 11, 1),
        protected: true,
        platform: 'android',
      );
    await _openConsoleTab(tester, deps, 'accounts');
    await tester.enterText(find.byKey(const Key('accounts.query')), 'toussaint');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account.protected')), findsOneWidget);
    expect(find.byKey(const Key('account.suspend')), findsNothing);
    expect(find.byKey(const Key('account.disconnect')), findsNothing);
  });

  testWidgets('répondre à une demande d’assistance avec un modèle', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.add(
      ModerationReport(
        id: 'sup1',
        kind: 'support',
        reason: 'support',
        status: 'open',
        createdAt: DateTime(2026, 11, 13, 9),
        details: 'Les vocaux ne partent plus',
        reporterHandle: 'bob_ouaga',
      ),
    );
    await _openConsoleTab(tester, deps, 'reports');
    await tester.tap(find.byKey(const Key('dossier.support:sup1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier.reply')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('reply.send'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('reply.template.1')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply.text')),
      'Mettez à jour l’application puis réessayez. Version 0.1.0+30 au moins.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply.send')));
    await tester.pumpAndSettle();
    expect(deps.admin.replies.single.$1, 'sup1');
    expect(deps.admin.replies.single.$2, startsWith('Mettez à jour'));
    expect(find.text('Réponse envoyée.'), findsOneWidget);
  });

  testWidgets('Aide → Mes demandes : demande envoyée puis répondue', (tester) async {
    final deps = _deps();
    deps.messaging.supportRequests.addAll([
      SupportRequest(
        id: 'r2',
        createdAt: DateTime(2026, 11, 13, 10),
        details: 'Comment changer ma photo ?',
      ),
      SupportRequest(
        id: 'r1',
        createdAt: DateTime(2026, 11, 13, 9),
        details: 'Les vocaux ne partent plus',
        reply: 'Mettez à jour l’application puis réessayez.',
        repliedAt: DateTime(2026, 11, 13, 9, 30),
      ),
    ]);
    await _start(tester, deps);
    deps.push.open(kSupportTarget);
    await tester.pumpAndSettle();
    expect(find.text('Mes demandes'), findsOneWidget);
    expect(find.text('Répondue'), findsOneWidget);
    expect(find.text('Envoyée'), findsOneWidget);
    expect(find.text('Mettez à jour l’application puis réessayez.'), findsOneWidget);
    expect(find.text('Réponse de l’équipe Privio'), findsOneWidget);
  });

  testWidgets('réponse reçue pendant l’écran : mise à jour aussitôt', (tester) async {
    final deps = _deps();
    deps.messaging.supportRequests.add(
      SupportRequest(id: 'r1', createdAt: DateTime(2026, 11, 13, 9), details: 'Vocaux'),
    );
    await _start(tester, deps);
    deps.push.open(kSupportTarget);
    await tester.pumpAndSettle();
    expect(find.text('Envoyée'), findsOneWidget);
    deps.messaging.supportRequests[0] = SupportRequest(
      id: 'r1',
      createdAt: DateTime(2026, 11, 13, 9),
      details: 'Vocaux',
      reply: 'Corrigé.',
    );
    deps.realtime.emit('', event: 'support');
    await tester.pumpAndSettle();
    expect(find.text('Répondue'), findsOneWidget);
    expect(find.text('Corrigé.'), findsOneWidget);
  });

  testWidgets('téléphone déconnecté par l’assistance : retour à la connexion, motif affiché', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    expect(find.byType(HomeShell), findsOneWidget);
    // Le serveur coupe la session juste après le signal.
    deps.api.accountFailure = const AppFailure(FailureCode.authRequired);
    deps.realtime.emit('', event: 'disconnected');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text(kSupportDisconnectNotice), findsOneWidget);
  });
}
