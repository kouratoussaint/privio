import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';
import '../helpers/settings_nav.dart';

/// Lot 8.3a — Paramètres réorganisés, menus ⋮ des listes, favoris de toutes les discussions.
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

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

Future<void> _menu(WidgetTester tester, String menu, [String? item]) async {
  await tester.tap(find.byKey(Key(menu)));
  await tester.pumpAndSettle();
  if (item != null) {
    await tapMenuItem(tester, Key(item));
    await tester.pumpAndSettle();
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Paramètres : page courte, une ligne par écran, sans doublon', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();

    for (final t in ['MON COMPTE', 'PRÉFÉRENCES', 'CE TÉLÉPHONE', 'PRIVIO']) {
      await tester.scrollUntilVisible(find.text(t), 200, scrollable: find.byType(Scrollable).first);
    }
    // Plus de doublons : À propos (Ma fiche), verrouillage et bloqués (sous-écrans).
    for (final k in ['settings.about', 'settings.lock', 'settings.blocked', 'settings.push']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }

    // Mon QR code depuis la carte du profil.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.qr')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('settings.qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my.qr.sheet')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Sécurité : verrouillage, changer de numéro, captures, appareil unique.
    await openSettingsEntry(tester, 'settings.security');
    expect(find.byKey(const Key('security.lock')), findsOneWidget);
    expect(find.byKey(const Key('security.phone')), findsOneWidget);
    expect(find.text('+226 70 00 00 01'), findsOneWidget);
    expect(find.text('Captures d’écran'), findsOneWidget);
    expect(find.text('Seul appareil connecté'), findsOneWidget);
    await tester.tap(find.byKey(const Key('security.phone')));
    await tester.pumpAndSettle();
    expect(find.text('Changer de numéro'), findsWidgets);
    await _back(tester);
    await _back(tester);

    // Notifications et sons.
    await openSettingsEntry(tester, 'settings.notifications');
    expect(find.byKey(const Key('settings.push')), findsOneWidget);
    expect(find.byKey(const Key('settings.sounds')), findsOneWidget);
    await _back(tester);

    // Discussions : fond d'écran, réaction, groupes, archivées.
    await openSettingsEntry(tester, 'settings.chats');
    for (final k in [
      'settings.wallpaper',
      'settings.quick_reaction',
      'settings.groups_together',
      'settings.archived',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    await tester.tap(find.byKey(const Key('settings.quick_reaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick.👍')));
    await tester.pumpAndSettle();
    expect(deps.flags.quick, '👍');
    await _back(tester);

    // Confidentialité : « Qui peut me joindre » (numéro, demandes, invitations, bloqués).
    await openSettingsEntry(tester, 'settings.privacy');
    await scrollToKey(tester, 'settings.discoverable');
    expect(find.text('QUI PEUT ME JOINDRE', skipOffstage: false), findsOneWidget);
    await scrollToKey(tester, 'privacy.requests');
    await scrollToKey(tester, 'privacy.blocked');
    expect(find.byKey(const Key('privacy.lock')), findsNothing, reason: 'déplacé dans Sécurité');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 600));
    await tester.pumpAndSettle();
    await scrollToKey(tester, 'settings.discoverable');
    await tester.tap(find.byKey(const Key('settings.discoverable')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('settings.discoverable'))).value,
      isTrue,
    );
  });

  testWidgets('Discussions ⋮ : tout marquer comme lu (avec confirmation)', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Un');
    deps.messaging.receive('conv-bob', 'Deux');
    await _start(tester, deps);
    expect(tester.widget<PrivioNavBar>(find.byType(PrivioNavBar)).items[0].badge, 1);

    await _menu(tester, 'discussions.menu');
    for (final k in ['new_conversation', 'scan', 'requests', 'archived', 'favorites', 'read_all']) {
      expect(find.byKey(Key('discussions.menu.$k')), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('discussions.menu.lock')), findsNothing, reason: 'pas de code');
    await tapMenuItem(tester, const Key('discussions.menu.read_all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Si vos accusés de lecture sont activés'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu.read_all.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('1 discussion marquée comme lue.'), findsOneWidget);
    expect(deps.messaging.lastRead('conv-bob'), isNotNull);
    expect(tester.widget<PrivioNavBar>(find.byType(PrivioNavBar)).items[0].badge, 0);

    // Plus rien à lire : l'entrée est grisée.
    await _menu(tester, 'discussions.menu');
    final item = tester.widget<InkWell>(find.byKey(const Key('discussions.menu.read_all')));
    expect(item.onTap, isNull);
  });

  testWidgets('Discussions ⋮ : nouvelle discussion, demandes, archivées', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await _menu(tester, 'discussions.menu', 'discussions.menu.new_conversation');
    expect(find.byKey(const Key('search.input')), findsOneWidget);
    await _back(tester);
    await _menu(tester, 'discussions.menu', 'discussions.menu.requests');
    expect(find.text('Demandes de connexion'), findsWidgets);
    await _back(tester);
    await _menu(tester, 'discussions.menu', 'discussions.menu.archived');
    expect(find.text('Aucune discussion archivée'), findsOneWidget);
  });

  testWidgets('favoris de toutes les discussions, avec leur discussion', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    final a = deps.messaging.receive('conv-bob', 'Rendez-vous à 15 h');
    deps.messaging.seedGroup('g1', 'Famille', members: {'u2': 'member'});
    final b = deps.messaging.receiveInGroup('g1', 'u2', 'Gâteau samedi');
    await deps.messaging.setFavorites([a.id, b.id], on: true);
    await _start(tester, deps);

    await _menu(tester, 'discussions.menu', 'discussions.menu.favorites');
    expect(find.text('Rendez-vous à 15 h'), findsOneWidget);
    expect(find.text('Gâteau samedi'), findsOneWidget);
    expect(find.textContaining('Famille · '), findsOneWidget);
    expect(find.textContaining('Bob · Bob · '), findsOneWidget);

    await tester.tap(find.byKey(Key('favorite.remove.${b.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Gâteau samedi'), findsNothing);

    await tester.tap(find.byKey(Key('favorite.${a.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsOneWidget, reason: 'discussion ouverte');
  });

  testWidgets('Groupes ⋮ : icône QR gardée, demandes envoyées annulables', (tester) async {
    final deps = _deps();
    deps.messaging.myJoinRequests.add(
      MyJoinRequest(conversationId: 'g9', title: 'Foot du jeudi', createdAt: DateTime.now()),
    );
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('groups.join')), findsOneWidget);

    await _menu(tester, 'groups.menu');
    expect(find.text('Demandes envoyées (1)'), findsOneWidget);
    expect(find.byKey(const Key('groups.menu.join')), findsOneWidget);
    expect(find.byKey(const Key('groups.menu.archived')), findsOneWidget);
    expect(find.byKey(const Key('groups.menu.read_all')), findsOneWidget);
    await tapMenuItem(tester, const Key('groups.menu.sent'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sent.g9')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sent.cancel.g9')));
    await tester.pumpAndSettle();
    expect(deps.messaging.myJoinRequests, isEmpty);
    expect(find.text('Aucune demande en attente.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await _menu(tester, 'groups.menu', 'groups.menu.join');
    expect(find.text('Rejoindre un groupe'), findsWidgets);
  });

  testWidgets('verrouiller Privio maintenant (code activé)', (tester) async {
    final deps = _deps();
    final salt = List<int>.generate(16, (i) => i);
    deps.lockStore.config = AppLockConfig(
      enabled: true,
      delaySeconds: 60,
      salt: base64Encode(salt),
      hash: await const FastPinHasher().hash('258014', salt, 1),
    );
    await _start(tester, deps);
    for (final d in '258014'.split('')) {
      await tester.tap(find.byKey(Key('pin.$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock.screen')), findsNothing);

    await _menu(tester, 'discussions.menu', 'discussions.menu.lock');
    expect(find.byKey(const Key('lock.screen')), findsOneWidget);
  });
}
