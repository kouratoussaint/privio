import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/push_service.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 5.3 — modération : écran « Compte suspendu » et contestation, avertissement, groupe
/// fermé, et côté console la file, le dossier, la copie, les décisions et les contestations.
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

Future<void> _withLock(TestDeps d) async {
  final salt = List<int>.generate(16, (i) => i);
  d.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

ModerationReport _report(
  String id, {
  String reporter = 'carla',
  String reason = 'harassment',
  String kind = 'account',
  String? messageId,
  String? evidenceKind,
  bool protected = false,
  String reportedHandle = 'bob_ouaga',
  String reportedUserId = 'u2',
  String status = 'open',
}) => ModerationReport(
  id: id,
  kind: kind,
  reason: reason,
  status: status,
  createdAt: DateTime(2026, 11, 13, 18),
  details: 'Il m’insulte',
  reporterHandle: reporter,
  reportedUserId: kind == 'group' ? null : reportedUserId,
  reportedHandle: kind == 'group' ? null : reportedHandle,
  reportedName: kind == 'group' ? null : 'Bob',
  reportedSince: DateTime(2026, 11, 1),
  conversationId: kind == 'group' ? 'g-arnaque' : 'conv-bob',
  groupTitle: kind == 'group' ? 'Arnaque' : null,
  messageId: messageId,
  evidenceKind: evidenceKind,
  reports90d: 2,
  reporters90d: 2,
  protected: protected,
);

Future<void> _openReports(WidgetTester tester, TestDeps deps) async {
  await _withLock(deps);
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
  await tester.tap(find.byKey(const Key('console.tab.reports')));
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // Côté personne sanctionnée
  // -------------------------------------------------------------------------
  testWidgets('compte suspendu : écran dédié, motif, contestation une seule fois', (tester) async {
    final deps = _deps()
      ..api.moderation = ModerationStatus(
        suspension: SuspensionInfo(
          id: 's1',
          reason: 'harassment',
          until: DateTime(2026, 11, 20, 21, 58),
        ),
      );
    await _start(tester, deps);
    expect(find.byKey(const Key('moderation.suspended')), findsOneWidget);
    expect(find.text('Compte suspendu'), findsOneWidget);
    expect(find.text('Jusqu’au 20/11/2026 à 21:58'), findsOneWidget);
    expect(find.textContaining('motif : harcèlement'), findsOneWidget);
    // L'application est dessous, inaccessible.
    expect(
      find.ancestor(of: find.byType(HomeShell), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );

    final send = find.byKey(const Key('moderation.appeal.send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('moderation.appeal')), 'Je n’ai insulté personne');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(deps.api.appealText, 'Je n’ai insulté personne');
    expect(find.text('Contestation envoyée : l’équipe Privio l’examine.'), findsOneWidget);
    expect(find.byKey(const Key('moderation.appeal')), findsNothing);
  });

  testWidgets('suspension sans limite, contestation maintenue', (tester) async {
    final deps = _deps()
      ..api.moderation = const ModerationStatus(
        suspension: SuspensionInfo(
          id: 's1',
          reason: 'spam',
          appealed: true,
          appealDecision: 'upheld',
        ),
      );
    await _start(tester, deps);
    expect(find.text('Sans limite de durée'), findsOneWidget);
    expect(find.text('Contestation examinée : la suspension est maintenue.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moderation.signout')));
    await tester.pumpAndSettle();
    expect(deps.auth.hasSession, isFalse);
  });

  testWidgets('décision de la console : l’écran bascule aussitôt (signal temps réel)', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    expect(find.byKey(const Key('moderation.suspended')), findsNothing);
    deps.api.moderation = const ModerationStatus(
      suspension: SuspensionInfo(id: 's1', reason: 'spam'),
    );
    deps.realtime.emit('', event: 'moderation');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moderation.suspended')), findsOneWidget);
    // Réactivation.
    deps.api.moderation = ModerationStatus.none;
    deps.realtime.emit('', event: 'moderation');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moderation.suspended')), findsNothing);
  });

  testWidgets('avertissement : message de l’équipe Privio, une seule fois', (tester) async {
    final deps = _deps()
      ..api.moderation = const ModerationStatus(
        warning: WarningInfo(id: 'w1', reason: 'spam'),
      );
    await _start(tester, deps);
    expect(find.byKey(const Key('moderation.warning')), findsOneWidget);
    expect(find.text('Message de l’équipe Privio'), findsOneWidget);
    expect(find.textContaining('motif : spam'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moderation.warning.ack')));
    await tester.pumpAndSettle();
    expect(deps.api.warningsAcknowledged, 1);
    expect(find.byKey(const Key('moderation.warning')), findsNothing);
  });

  testWidgets('groupe fermé par Privio : bandeau, plus de saisie ni d’invitation', (tester) async {
    final deps = _deps();
    deps.messaging.seedGroup('g-arnaque', 'Arnaque', posting: 'closed');
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g-arnaque')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.group_closed')), findsOneWidget);
    expect(find.byKey(const Key('chat.input')), findsNothing);
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group.invite')), findsNothing);
    expect(find.byKey(const Key('group.posting')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Console
  // -------------------------------------------------------------------------
  testWidgets('file : un dossier par compte, @identifiants, filtres', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.addAll([
      _report('r1', messageId: 'm1', kind: 'message', evidenceKind: 'text'),
      _report('r2', reporter: 'dani'),
      _report('rg', kind: 'group', reason: 'spam', reporter: 'carla'),
    ]);
    await _openReports(tester, deps);
    expect(find.text('@bob_ouaga · Bob'), findsOneWidget);
    expect(find.textContaining('2 signalements · 2 personnes'), findsOneWidget);
    expect(find.text('Groupe « Arnaque »'), findsOneWidget);
    expect(find.textContaining('+226'), findsNothing);

    await tester.tap(find.byKey(const Key('reports.kind.group')));
    await tester.pumpAndSettle();
    expect(find.text('@bob_ouaga · Bob'), findsNothing);
    expect(find.text('Groupe « Arnaque »'), findsOneWidget);
  });

  testWidgets('dossier : copie jointe, suspension 7 jours avec motif', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.addAll([
      _report('r1', messageId: 'm1', kind: 'message', evidenceKind: 'text'),
      _report('r2', reporter: 'dani'),
    ]);
    deps.admin.evidenceById['r1'] = const ReportEvidence(kind: 'text', body: 'Message insultant');
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('dossier.user:u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier.counts')), findsOneWidget);
    expect(find.textContaining('par @carla'), findsOneWidget);
    expect(find.textContaining('par @dani'), findsOneWidget);
    expect(find.text('Message insultant'), findsNothing, reason: 'copie cachée par défaut');

    await tester.tap(find.byKey(const Key('report.evidence.r1')));
    await tester.pumpAndSettle();
    expect(find.text('Message insultant'), findsOneWidget);
    expect(deps.admin.evidenceReads, 1);

    final list = find.byKey(const Key('dossier.view'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('dossier.suspend')),
      200,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(find.byKey(const Key('dossier.suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier.suspend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('decision.suspend')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('decision.confirm'))).onPressed,
      isNull,
      reason: 'motif obligatoire',
    );
    await tester.tap(find.byKey(const Key('decision.days.7')));
    await tester.enterText(find.byKey(const Key('decision.note')), 'Harcèlement répété');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.moderations.single.$2, 'suspend');
    expect(deps.admin.moderations.single.$1, ['r1', 'r2'], reason: 'tout le dossier');
    expect(deps.admin.moderations.single.$4, 7);
    expect(find.text('Compte suspendu.'), findsOneWidget);
    expect(find.byKey(const Key('dossier.user:u2')), findsNothing, reason: 'plus à traiter');
  });

  testWidgets('suspension sans limite et autres décisions', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.add(_report('r1'));
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('dossier.user:u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier.suspend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decision.days.0')));
    await tester.enterText(find.byKey(const Key('decision.note')), 'Menaces graves');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.moderations.single.$4, isNull, reason: 'sans limite');

    // Traités : la décision et le motif.
    await tester.tap(find.byKey(const Key('reports.queue.closed')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Suspension'), findsWidgets);
  });

  testWidgets('compte de l’administration : aucune sanction possible', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.add(_report('ra', protected: true, reportedHandle: 'toussaint_bf'));
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('dossier.user:u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier.protected')), findsOneWidget);
    expect(find.byKey(const Key('dossier.suspend')), findsNothing);
    expect(find.byKey(const Key('dossier.warn')), findsNothing);
    expect(find.byKey(const Key('dossier.dismiss')), findsOneWidget);
  });

  testWidgets('groupe signalé : fermer le groupe', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.add(_report('rg', kind: 'group', reason: 'spam'));
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('dossier.group:g-arnaque')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier.suspend')), findsNothing);
    await tester.tap(find.byKey(const Key('dossier.close_group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('decision.note')), 'Groupe d’arnaque');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.moderations.single.$2, 'close_group');
  });

  testWidgets('prendre en charge : le dossier passe « En cours »', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.reportList.add(_report('r1'));
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('dossier.user:u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier.take')));
    await tester.pumpAndSettle();
    expect(deps.admin.reportList.single.status, 'reviewing');
    await tester.tap(find.byKey(const Key('reports.queue.reviewing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier.user:u2')), findsOneWidget);
  });

  testWidgets('contestations : lever la suspension', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.appealList.add(
      Sanction(
        id: 's1',
        kind: 'suspension',
        reason: 'spam',
        createdAt: DateTime(2026, 11, 13, 18),
        note: 'Spam répété',
        handle: 'bob_ouaga',
        displayName: 'Bob',
        appealText: 'Je ne fais pas de publicité',
        appealAt: DateTime(2026, 11, 13, 19),
      ),
    );
    await _openReports(tester, deps);
    await tester.tap(find.byKey(const Key('reports.queue.appeals')));
    await tester.pumpAndSettle();
    expect(find.text('« Je ne fais pas de publicité »'), findsOneWidget);
    await tester.tap(find.byKey(const Key('appeal.lift.s1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('decision.note')), 'Erreur de notre part');
    await tester.pump();
    await tester.tap(find.byKey(const Key('decision.confirm')));
    await tester.pumpAndSettle();
    expect(deps.admin.appealAnswers.single, ('s1', true));
    expect(find.text('Suspension levée.'), findsOneWidget);
  });

  testWidgets('notification de signalement touchée : la console (code demandé)', (tester) async {
    final deps = _deps(admin: true);
    await _withLock(deps);
    await _start(tester, deps);
    await _type(tester, _pin);
    deps.push.open(kConsoleTarget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.pin')), findsOneWidget);
    unawaited(Future<void>.value());
  });
}
