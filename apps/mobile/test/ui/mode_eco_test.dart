import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/media/photo_processing.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 10.3 — Mode éco : un interrupteur (à la main), feuille verte, réception au toucher,
/// GIF et aperçus coupés, envois allégés, consommation détaillée.
TestDeps _deps({bool eco = false}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true)..eco = eco,
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
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

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
  testWidgets('activer à la main : feuille verte, téléchargement automatique suspendu', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    expect(find.byKey(const Key('eco.badge')), findsNothing);
    await _openStorage(tester);
    await tester.tap(find.byKey(const Key('storage.eco')));
    await tester.pumpAndSettle();
    expect(deps.flags.eco, isTrue);
    expect(find.text('Activé\u202F: Privio consomme moins de données.'), findsOneWidget);
    expect(
      tester.widget<RadioListTile<Object>>(find.byKey(const Key('storage.auto.always'))).enabled,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(_tab('Discussions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eco.badge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('eco.badge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storage.eco')), findsOneWidget);
  });

  testWidgets('réception : photo et GIF au toucher ; économie comptée puis retirée', (
    tester,
  ) async {
    final deps = _deps(eco: true);
    final photo = deps.messaging.receivePhoto('conv-bob', caption: 'Marché');
    final now = DateTime.now();
    deps.messaging.messages['conv-bob']!.add(
      ChatMessage(
        id: 'gif-1',
        kind: 'gif',
        senderId: 'u2',
        mediaPath: 'gifs/a.webp',
        width: 200,
        height: 150,
        sentAt: now,
        expiresAt: now.add(const Duration(hours: 72)),
        updatedAt: now,
      ),
    );
    await _start(tester, deps);
    await _openBob(tester);
    final key = 'msg-${photo.id}';
    expect(find.byKey(Key('photo.download.$key')), findsOneWidget);
    expect(deps.messaging.photoDownloads, isEmpty);
    expect(find.byKey(const Key('gif.download.gif-1')), findsOneWidget);
    await tester.pumpAndSettle();
    final saved = deps.flags.usage.entries.where((e) => e.key.endsWith(':saved'));
    await tester.pump(const Duration(seconds: 3));
    expect(
      deps.flags.usage.entries.any((e) => e.key.endsWith(':saved') && e.value > 0),
      isTrue,
      reason: 'téléchargements évités comptés ($saved)',
    );

    await tester.tap(find.byKey(Key('photo.download.$key')));
    await tester.pumpAndSettle();
    expect(deps.messaging.photoDownloads, [photo.mediaPath]);
    await tester.tap(find.byKey(const Key('gif.download.gif-1')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(
      deps.flags.usage.entries.any((e) => e.key.endsWith(':saved')),
      isFalse,
      reason: 'téléchargés finalement : plus comptés comme économisés',
    );
    expect(deps.flags.usage.keys.any((k) => k.endsWith(':in:photo')), isTrue);
  });

  testWidgets('envoi : vocal allégé, onglet GIF masqué, aucun aperçu de lien', (tester) async {
    final deps = _deps(eco: true);
    deps.messaging.nextPreview = const LinkPreview(url: 'https://exemple.bf', title: 'Exemple');
    await _start(tester, deps);
    await _openBob(tester);

    await tester.tap(find.byKey(const Key('composer.emoji')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expression.tab.gifs')), findsNothing);
    await tester.tap(find.byKey(const Key('chat.input')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat.input')), 'Voir https://exemple.bf');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.previewRequests, isEmpty);
    expect(find.byKey(const Key('link.preview')), findsNothing);
  });

  test('photo préparée en Mode éco : 1 024 px au plus, qualité 65', () {
    // Image de 2 000 × 1 500 générée en mémoire.
    final raw = testJpeg(width: 2000, height: 1500);
    final normal = processPhotoSync(raw)!;
    final eco = processPhotoSync(raw, maxSide: kEcoPhotoMaxSide, quality: kEcoPhotoQuality)!;
    expect(normal.width, 1600);
    expect(eco.width, 1024);
    expect(eco.quality, 65);
    expect(eco.bytes.length, lessThan(normal.bytes.length));
  });
}
