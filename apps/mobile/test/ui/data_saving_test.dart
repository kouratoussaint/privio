import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/device_services.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/data_providers.dart';

import '../helpers/fakes.dart';

/// Lot 4.2 — économie de données, stockage, réseau (DATA-001, 003, 006, 007, 008, 009).
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
  await deps.messaging.startDirectConversation('u2');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _openBob(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openStorage(WidgetTester tester) async {
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.storage')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.byKey(const Key('settings.storage')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.storage')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '«\u202Fjamais\u202F»\u202F: photo reçue en attente, téléchargée seulement si on la touche',
    (tester) async {
      final deps = _deps()..flags.autoPhoto = 'never';
      final m = deps.messaging.receivePhoto('conv-bob', caption: 'Marché');
      await _start(tester, deps);
      await _openBob(tester);

      final key = 'msg-${m.id}';
      expect(find.byKey(Key('photo.download.$key')), findsOneWidget);
      expect(find.text('Photo · toucher pour télécharger'), findsOneWidget);
      expect(deps.messaging.photoDownloads, isEmpty);

      await tester.tap(find.byKey(Key('photo.download.$key')));
      await tester.pumpAndSettle();
      expect(deps.messaging.photoDownloads, [m.mediaPath]);
      expect(find.byKey(Key('photo.open.$key')), findsOneWidget);
    },
  );

  testWidgets(
    '«\u202FWi-Fi seulement\u202F»\u202F: attente en données mobiles, téléchargement en Wi-Fi',
    (tester) async {
      final deps = _deps()..flags.autoPhoto = 'wifi';
      deps.network.kind = NetKind.mobile;
      final m = deps.messaging.receivePhoto('conv-bob');
      await _start(tester, deps);
      await _openBob(tester);
      expect(find.byKey(Key('photo.download.msg-${m.id}')), findsOneWidget);
      expect(deps.messaging.photoDownloads, isEmpty);

      deps.network.set(NetKind.wifi);
      await tester.pumpAndSettle();
      expect(deps.messaging.photoDownloads, [m.mediaPath]);
      expect(find.byKey(Key('photo.open.msg-${m.id}')), findsOneWidget);
    },
  );

  testWidgets('écran Stockage\u202F: réglage, données consommées, effacement des médias', (
    tester,
  ) async {
    final deps = _deps();
    final m = deps.messaging.receivePhoto('conv-bob');
    await _start(tester, deps);
    await _openBob(tester);
    expect(deps.messaging.photoDownloads, [
      m.mediaPath,
    ], reason: '«\u202Ftoujours\u202F» par défaut');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await _openStorage(tester);
    final month = monthKey(DateTime.now());
    await tester.tap(find.byKey(const Key('storage.auto.never')));
    await tester.pumpAndSettle();
    expect(deps.flags.autoPhoto, 'never');
    expect(find.textContaining('Reçu ${formatBytes(testJpeg().length)}'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('storage.space')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('1 fichier'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('storage.clear')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('storage.clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storage.clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storage.clear.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('1 fichier effacé.'), findsOneWidget);
    expect(deps.vault.files, isEmpty);
    expect(find.textContaining('0 fichier'), findsOneWidget);

    // Compteurs enregistrés (après le court délai d'écriture), puis remis à zéro.
    await tester.pump(const Duration(seconds: 3));
    expect(deps.flags.usage['$month:in'], testJpeg().length);
    await tester.tap(find.byKey(const Key('storage.usage.reset')));
    await tester.pumpAndSettle();
    expect(deps.flags.usage, isEmpty);
  });

  testWidgets('photo envoyée\u202F: comptée en «\u202Fenvoyé\u202F», jamais retéléchargée', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openBob(tester);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.photoDownloads, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    final month = monthKey(DateTime.now());
    expect(deps.flags.usage['$month:out'], greaterThan(0));
    expect(deps.flags.usage['$month:in'], isNull);
  });

  testWidgets(
    'réseau coupé\u202F: bandeau aussitôt\u202F; retour\u202F: bandeau retiré, envois repartis',
    (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      expect(find.byKey(const Key('offline.banner')), findsNothing);

      deps.network.set(NetKind.none);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline.banner')), findsOneWidget);

      // Le bandeau est aussi dans l'onglet Groupes.
      await tester.tap(_tab('Groupes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline.banner')), findsOneWidget);

      deps.network.set(NetKind.mobile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline.banner')), findsNothing);
    },
  );

  testWidgets('onglet Groupes\u202F: erreur affichée avec «\u202FRéessayer\u202F»', (tester) async {
    final deps = _deps();
    deps.messaging.failList = true;
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    deps.messaging.failList = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun groupe pour l’instant'), findsOneWidget);
  });
}
