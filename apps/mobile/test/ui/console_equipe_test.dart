import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/domain/models/console_team.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.8 — console : équipe et rôles, deux étapes obligatoires, groupes, réponses types,
/// sites sans aperçu, suivi de la modération.
const _pin = '258014';

TestDeps _deps({ConsoleRole role = ConsoleRole.owner, bool twoStep = true}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = true
      ..admin.role = role
      ..admin.staffTwoStep = twoStep
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

/// Ouvre la console (code Privio), sans choisir de rubrique.
Future<void> _openConsole(WidgetTester tester, TestDeps deps) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.console')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await _type(tester, _pin);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('console.menu')));
  await tester.pumpAndSettle();
}

Finder _menuItem(String id) => find.byKey(Key('console.tab.$id'), skipOffstage: false);

void main() {
  testWidgets('propriétaire : équipe, ajouter, changer le rôle, retirer', (tester) async {
    final deps = _deps();
    deps.admin.staff.add(
      const StaffMember(
        userId: 'm1',
        role: ConsoleRole.moderator,
        name: 'Modo',
        handle: 'modo_bf',
        twoStep: true,
      ),
    );
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'team');
    expect(find.byKey(const Key('team.list')), findsOneWidget);
    expect(find.text('Modo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('team.add')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('team.add.confirm'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('team.add.phone')), '70 00 00 02');
    await tester.tap(find.byKey(const Key('team.add.role.support')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team.add.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.teamLog, ['add:+22670000002:support']);
    expect(find.text('Nouvelle personne'), findsOneWidget);

    await tester.tap(find.byKey(const Key('team.member.m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team.role.support')));
    await tester.pumpAndSettle();
    expect(deps.admin.teamLog.last, 'role:m1:support');

    await tester.tap(find.byKey(const Key('team.member.m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team.remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team.remove.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.teamLog.last, 'remove:m1');
    expect(find.text('Modo'), findsNothing);
  });

  testWidgets('équipe sans deux étapes : la console reste fermée', (tester) async {
    final deps = _deps(role: ConsoleRole.moderator, twoStep: false);
    await _openConsole(tester, deps);
    expect(find.byKey(const Key('console.two_step_required')), findsOneWidget);
    expect(find.byKey(const Key('console.menu')), findsNothing);
    expect(deps.admin.dashboardCalls, 0);
  });

  testWidgets('modérateur : ses rubriques, pas l’assistance ni les réglages', (tester) async {
    final deps = _deps(role: ConsoleRole.moderator);
    deps.admin.reportList.addAll([
      ModerationReport(
        id: 'r1',
        kind: 'account',
        reason: 'spam',
        status: 'open',
        createdAt: DateTime(2026, 11, 18, 9),
        reportedUserId: 'u9',
        reportedHandle: 'arnaqueur',
      ),
      ModerationReport(
        id: 'sup1',
        kind: 'support',
        reason: 'support',
        status: 'open',
        createdAt: DateTime(2026, 11, 18, 9),
        details: 'Aide',
      ),
    ]);
    await _openConsole(tester, deps);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
    expect(find.byKey(const Key('console.tile.policies')), findsNothing);
    expect(find.byKey(const Key('console.tile.groups')), findsOneWidget);
    await _openMenu(tester);
    expect(find.text('Modérateur'), findsOneWidget);
    for (final id in ['reports', 'accounts', 'groups', 'moderation', 'templates', 'sites']) {
      expect(_menuItem(id), findsOneWidget, reason: id);
    }
    for (final id in ['features', 'policies', 'stats', 'health', 'journal', 'team']) {
      expect(_menuItem(id), findsNothing, reason: id);
    }
    await tester.tap(_menuItem('reports'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports.kind.support')), findsNothing);
    expect(find.byKey(const Key('reports.queue.appeals')), findsOneWidget);
    expect(find.textContaining('arnaqueur'), findsWidgets);
    expect(find.text('Aide'), findsNothing);
  });

  testWidgets('assistance : ses demandes seulement, pas de sanction', (tester) async {
    final deps = _deps(role: ConsoleRole.support);
    deps.admin.reportList.add(
      ModerationReport(
        id: 'sup1',
        kind: 'support',
        reason: 'support',
        status: 'open',
        createdAt: DateTime(2026, 11, 18, 9),
        details: 'Les vocaux ne partent plus',
        reporterHandle: 'bob_ouaga',
        techLog: '19/11 10:42 Erreur application · StateError',
      ),
    );
    await _openConsole(tester, deps);
    await _openMenu(tester);
    expect(_menuItem('groups'), findsNothing);
    expect(_menuItem('sites'), findsNothing);
    expect(find.text('Demandes d’assistance'), findsWidgets);
    await tester.tap(_menuItem('reports'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reports.queue.appeals')), findsNothing);
    expect(find.byKey(const Key('reports.kind.account')), findsNothing);
    await tester.tap(find.byKey(const Key('dossier.support:sup1')));
    await tester.pumpAndSettle();
    // Lot 6.1 : le journal technique joint se lit dans le dossier.
    await tester.tap(find.byKey(const Key('report.techlog.sup1')));
    await tester.pumpAndSettle();
    expect(find.text('19/11 10:42 Erreur application · StateError'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('dossier.reply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier.reply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('template.pick.tpl-s1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply.send')));
    await tester.pumpAndSettle();
    expect(deps.admin.replies.single.$2, 'Merci, le problème est corrigé.');
  });

  testWidgets('groupes : signalés, fiche sans messages, fermer avec un motif type, supprimer', (
    tester,
  ) async {
    final deps = _deps(role: ConsoleRole.moderator);
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'groups');
    expect(find.byKey(const Key('group.g1')), findsOneWidget);
    expect(find.byKey(const Key('group.g2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('groups.filter.reported')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group.g2')), findsNothing);
    expect(find.textContaining('2 signalements en attente'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group.g1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('@dani'), findsOneWidget);
    expect(find.textContaining('jamais visibles'), findsOneWidget);
    await tester.tap(find.byKey(const Key('group.close')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('group.action.confirm'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('template.pick.tpl-d1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group.action.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.groupActions.single.$2, 'close');
    expect(deps.admin.groupActions.single.$3, startsWith('Arnaque confirmée'));
    expect(find.byKey(const Key('group.reopen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group.delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group.action.note')), 'Groupe d’arnaque');
    await tester.pump();
    await tester.tap(find.byKey(const Key('group.action.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.groupActions.last.$2, 'delete');
    expect(find.text('Aucun groupe'), findsOneWidget);
    expect(find.byKey(const Key('group.g1')), findsNothing);
  });

  testWidgets('sites sans aperçu, réponses types, suivi de la modération', (tester) async {
    final deps = _deps();
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'sites');
    await tester.enterText(find.byKey(const Key('sites.input')), 'https://www.Arnaque.example/x');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sites.add')));
    await tester.pumpAndSettle();
    expect(deps.admin.sites, ['arnaque.example']);
    expect(find.byKey(const Key('site.arnaque.example')), findsOneWidget);
    await tester.tap(find.byKey(const Key('site.remove.arnaque.example')));
    await tester.pumpAndSettle();
    expect(deps.admin.sites, isEmpty);

    await openConsoleSection(tester, 'templates');
    expect(find.text('Problème corrigé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('templates.add.decision')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('template.title')), 'Menaces');
    await tester.enterText(find.byKey(const Key('template.body')), 'Menaces confirmées.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('template.save')));
    await tester.pumpAndSettle();
    expect(deps.admin.templateList.last.kind, 'decision');
    expect(find.text('Menaces'), findsOneWidget);

    await openConsoleSection(tester, 'moderation');
    expect(find.byKey(const Key('modstats.view')), findsOneWidget);
    expect(find.text('Signalements reçus'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('modstats.days.30')));
    await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('modstats.person.Modo')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Modo · modérateur'), findsOneWidget);
  });

  test('journal : nouveaux types d’action', () {
    expect(journalTypeOf('team_add'), 'team');
    expect(journalTypeOf('group_delete'), 'groups');
    expect(journalTypeOf('site'), 'settings');
  });
}
