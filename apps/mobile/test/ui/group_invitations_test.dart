import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/push_service.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/groups/group_screens.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 4.8 — groupes réactifs : création visible et immédiate, invitations à jour au retour
/// dans l'app, en tirant vers le bas et depuis une notification.
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

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

const _invitation = GroupInvitation(
  id: 'i9',
  conversationId: 'g-voisins',
  title: 'Voisins',
  memberCount: 4,
  inviterName: 'Bob',
);

void main() {
  test('message de confirmation après création', () {
    expect(createdGroupMessage(0), 'Groupe créé');
    expect(createdGroupMessage(1), 'Groupe créé · 1 invitation envoyée');
    expect(createdGroupMessage(3), 'Groupe créé · 3 invitations envoyées');
  });

  testWidgets('création : « Création du groupe… » pendant l’envoi, puis la discussion '
      's’ouvre avec le bon nom sans attendre la liste', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation(FakeMessagingApi.bob.id);
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groups.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group.title')), 'Voisins');
    await tester.tap(find.byKey(const Key('picker.user.u2')));
    await tester.pumpAndSettle();

    // Serveur lent : la création puis la liste des discussions se font attendre.
    deps.messaging
      ..createGate = Completer<void>()
      ..listGate = Completer<void>();
    // Lot 10.5 : écran plus long (type de groupe) : on va en bas.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group.create')));
    await tester.pump();
    expect(find.byKey(const Key('group.creating')), findsOneWidget);
    expect(find.text('Création du groupe…'), findsOneWidget);
    // Un second appui n'envoie rien de plus.
    await tester.tap(find.byKey(const Key('group.create')), warnIfMissed: false);
    await tester.pump();

    deps.messaging.createGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(deps.messaging.groups.length, 1, reason: 'un seul groupe créé');
    // La liste n'est pas encore revenue du serveur : l'en-tête montre déjà le groupe.
    expect(find.text('Voisins'), findsWidgets);
    expect(find.text('Discussion'), findsNothing);
    expect(find.byKey(const Key('chat.members')), findsOneWidget);
    expect(find.text('Groupe créé · 1 invitation envoyée'), findsOneWidget);

    deps.messaging.listGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Voisins'), findsWidgets);
    expect(find.text('Vous avez créé le groupe « Voisins »'), findsOneWidget);
  });

  testWidgets('invitation reçue app en arrière-plan : affichée au retour dans l’app', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i9')), findsNothing);

    // Arrivée pendant que l'app dormait (aucun signal temps réel reçu).
    deps.messaging.invitations.add(_invitation);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i9')), findsNothing);

    deps.realtime.emit('', event: 'resume');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i9')), findsOneWidget);
    expect(find.text('Bob vous invite · 4 membres'), findsOneWidget);
  });

  testWidgets('après une coupure réseau : invitations rechargées', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    deps.messaging.invitations.add(_invitation);
    deps.realtime.emit('', event: 'reconnected');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i9')), findsOneWidget);
  });

  testWidgets('onglet Groupes : tirer vers le bas recharge les invitations', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun groupe pour l’instant'), findsOneWidget);

    deps.messaging.invitations.add(_invitation);
    await tester.fling(find.text('Aucun groupe pour l’instant'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invitation.i9')), findsOneWidget);
  });

  testWidgets('notification d’invitation touchée : l’onglet Groupes, invitation à jour', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    expect(_tab('Discussions'), findsOneWidget);
    deps.messaging.invitations.add(_invitation);

    deps.push.open(kGroupsTarget);
    await tester.pumpAndSettle();
    expect(find.text('Aucun groupe pour l’instant'), findsNothing);
    expect(find.byKey(const Key('invitation.i9')), findsOneWidget);
    expect(find.byKey(const Key('groups.new')), findsOneWidget);
  });
}
