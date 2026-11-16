import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.6 — comptes dans la console : numéro et photo (console seulement), filtres,
/// fiche repensée, appareils, photo retirée, identifiant imposé, @ réservés.
const _pin = '258014';

TestDeps _deps({bool admin = true}) =>
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

Future<void> _openAccounts(WidgetTester tester, TestDeps deps) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await _start(tester, deps);
  await _type(tester, _pin);
  await tester.tap(
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
  );
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
  await openConsoleSection(tester, 'accounts');
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find
        .descendant(of: find.byKey(const Key('account.view')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _decide(WidgetTester tester, String note) async {
  await tester.enterText(find.byKey(const Key('decision.note')), note);
  await tester.pump();
  await tester.tap(find.byKey(const Key('decision.confirm')));
  await tester.pumpAndSettle();
}

final _now = DateTime.now();

final _bob = ConsoleAccount(
  userId: 'u2',
  handle: 'bob_ouaga',
  displayName: 'Bob Ouédraogo',
  phoneE164: '+22670000002',
  avatarPath: 'u2/photo.jpg',
  createdAt: _now.subtract(const Duration(days: 60)),
  lastSeenAt: _now.subtract(const Duration(days: 1)),
  platform: 'android',
  appVersion: '0.1.0+66',
  directs: 4,
  groups: 2,
  reportsReceived90d: 1,
  devices: [
    ConsoleDevice(
      id: 'd2',
      platform: 'android',
      appVersion: '0.1.0+66',
      model: 'Tecno Spark 10',
      osVersion: '13',
      createdAt: _now.subtract(const Duration(days: 10)),
      lastSeenAt: _now.subtract(const Duration(days: 1)),
      push: true,
    ),
    ConsoleDevice(
      id: 'd1',
      platform: 'android',
      appVersion: '0.1.0+40',
      model: 'Itel A70',
      osVersion: '12',
      createdAt: _now.subtract(const Duration(days: 50)),
      lastSeenAt: _now.subtract(const Duration(days: 10)),
      revokedAt: _now.subtract(const Duration(days: 10)),
      revokedReason: 'new_device',
    ),
  ],
  actions: [
    AccountAction(
      action: 'avatar_remove',
      at: _now.subtract(const Duration(days: 3)),
      detail: const {'user_id': 'u2'},
    ),
  ],
);

final _carla = ConsoleAccount(
  userId: 'u3',
  handle: 'carla',
  displayName: 'Carla',
  phoneE164: '+22670000003',
  createdAt: _now.subtract(const Duration(days: 2)),
  twoStep: true,
);

void main() {
  testWidgets('liste : numéro, filtres avec leur nombre', (tester) async {
    final deps = _deps()
      ..admin.accounts['u2'] = _bob
      ..admin.accounts['u3'] = _carla;
    await _openAccounts(tester, deps);
    expect(find.byKey(const Key('account.phone.u2')), findsOneWidget);
    expect(find.text('+226 70 00 00 02'), findsOneWidget);
    expect(find.text('Nouveaux (7 j) · 1'), findsOneWidget);
    expect(find.text('Tous · 2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('accounts.filter.new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accounts.filter.new')));
    await tester.pumpAndSettle();
    expect(deps.admin.accountFilters.last, 'new');
    expect(find.byKey(const Key('account.u3')), findsOneWidget);
    expect(find.byKey(const Key('account.u2')), findsNothing);

    // Recherche par numéro partiel.
    await tester.enterText(find.byKey(const Key('accounts.query')), '0002');
    await tester.tap(find.byKey(const Key('accounts.search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account.u2')), findsOneWidget);
    expect(find.byKey(const Key('account.u3')), findsNothing);
  });

  testWidgets('fiche : en-tête, chiffres, téléphones, historique', (tester) async {
    final deps = _deps()..admin.accounts['u2'] = _bob;
    await _openAccounts(tester, deps);
    await tester.tap(find.byKey(const Key('account.u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account.header')), findsOneWidget);
    expect(find.text('+226 70 00 00 02'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('account.reports')), matching: find.text('1')),
      findsOneWidget,
    );
    await _scrollTo(tester, 'account.device');
    expect(find.text('Tecno Spark 10'), findsOneWidget);
    expect(find.text('Android 13 · version 0.1.0+66'), findsOneWidget);
    await _scrollTo(tester, 'account.device.d1');
    expect(find.textContaining('remplacé par un autre téléphone'), findsOneWidget);
    await _scrollTo(tester, 'account.history');
    expect(find.text('Photo de profil retirée'), findsOneWidget);
  });

  testWidgets('actions : photo retirée, identifiant imposé, un appareil déconnecté', (
    tester,
  ) async {
    final deps = _deps()..admin.accounts['u2'] = _bob;
    await _openAccounts(tester, deps);
    await tester.tap(find.byKey(const Key('account.u2')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, 'account.device.disconnect.d2');
    await tester.tap(find.byKey(const Key('account.device.disconnect.d2')));
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter cet appareil'), findsWidgets);
    await _decide(tester, 'Téléphone perdu');
    expect(deps.admin.deviceDisconnects.single, ('u2', 'd2', 'Téléphone perdu'));
    expect(find.text('Appareil déconnecté.'), findsOneWidget);

    await _scrollTo(tester, 'account.remove_avatar');
    await tester.tap(find.byKey(const Key('account.remove_avatar')));
    await tester.pumpAndSettle();
    await _decide(tester, 'Photo choquante');
    expect(deps.admin.removedAvatars.single, ('u2', 'Photo choquante'));
    expect(find.text('Photo de profil retirée.'), findsOneWidget);

    await _scrollTo(tester, 'account.reset_handle');
    await tester.tap(find.byKey(const Key('account.reset_handle')));
    await tester.pumpAndSettle();
    expect(find.text('Imposer un nouvel identifiant'), findsOneWidget);
    await _decide(tester, 'Identifiant trompeur');
    expect(deps.admin.handleResets.single, ('u2', 'Identifiant trompeur'));
    expect(find.textContaining('Identifiant remplacé par @compte_'), findsOneWidget);
  });

  testWidgets('identifiants réservés : ajouter, libérer ; mots toujours réservés', (tester) async {
    final deps = _deps();
    await _openAccounts(tester, deps);
    await tester.tap(find.byKey(const Key('accounts.reserved')));
    await tester.pumpAndSettle();
    expect(find.text('@privio'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reserved.input')), 'Orange_BF');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reserved.add')));
    await tester.pumpAndSettle();
    expect(deps.admin.reservedAdded, ['orange_bf']);
    expect(find.byKey(const Key('reserved.orange_bf')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reserved.input')), 'privio');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reserved.add')));
    await tester.pumpAndSettle();
    expect(find.text('Ce mot est toujours réservé.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reserved.release.orange_bf')));
    await tester.pumpAndSettle();
    expect(deps.admin.reservedAdded, isEmpty);

    // Retour du téléphone : revient à la liste des comptes, pas hors de la console.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reserved.view')), findsNothing);
    expect(find.byKey(const Key('accounts.query')), findsOneWidget);
  });

  testWidgets('identifiant imposé : la personne en choisit un nouveau avant de continuer', (
    tester,
  ) async {
    final deps = _deps(admin: false)
      ..api.moderation = const ModerationStatus(handleReset: true)
      ..api.takenHandles.add('bob_pris');
    await _start(tester, deps);
    expect(find.byKey(const Key('moderation.handle')), findsOneWidget);
    expect(find.text('Choisissez un nouvel identifiant'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('moderation.handle.input')), 'bob_pris');
    await tester.pump();
    await tester.tap(find.byKey(const Key('moderation.handle.save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cet identifiant est déjà pris'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('moderation.handle.input')), 'Bob_Ouaga2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('moderation.handle.save')));
    await tester.pumpAndSettle();
    expect(deps.api.chosenHandles, ['bob_ouaga2']);
    expect(find.byKey(const Key('moderation.handle')), findsNothing);
  });

  testWidgets('au lancement : modèle et version d’Android transmis une fois', (tester) async {
    final deps = _deps(admin: false);
    await _start(tester, deps);
    expect(deps.api.registeredDevices, 1);
    expect(deps.api.lastDevice, ('Tecno Spark 10', '13'));
  });
}
