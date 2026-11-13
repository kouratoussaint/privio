import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 4.4 (R-09) : sur un écran de 320 dp, les 4 filtres de la liste restent visibles.
/// Fichier séparé : la vraie police Inter y est chargée (les mesures en dépendent).
void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  Future<TestDeps> pumpAt(WidgetTester tester, double width) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = Size(width * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    final deps =
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
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    return deps;
  }

  testWidgets('320 dp avec des non-lus\u202F: « Groupes » reste visible', (tester) async {
    final deps = await pumpAt(tester, 320);
    await deps.messaging.startDirectConversation('u2');
    for (var i = 0; i < 12; i++) {
      deps.messaging.receive('conv-bob', 'Message $i');
    }
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    final groups = tester.getRect(find.byKey(const Key('filter.groups')));
    expect(groups.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('$width dp : « Groupes » entièrement visible et utilisable', (tester) async {
      await pumpAt(tester, width);
      final groups = tester.getRect(find.byKey(const Key('filter.groups')));
      expect(groups.left, greaterThan(0));
      expect(groups.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('filter.groups')));
      await tester.pumpAndSettle();
    });
  }
}
