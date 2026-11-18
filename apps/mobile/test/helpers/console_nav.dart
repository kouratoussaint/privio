import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot 5.5 : ouvre une rubrique de la console par le menu latéral (lot 5.8 : le menu,
/// plus long, défile jusqu'à la rubrique).
Future<void> openConsoleSection(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('console.menu')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(Key('console.tab.$id')),
    120,
    scrollable: find.descendant(
      of: find.byKey(const Key('console.drawer')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('console.tab.$id')));
  await tester.pumpAndSettle();
}
