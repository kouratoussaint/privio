import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot 5.5 : ouvre une rubrique de la console par le menu latéral.
Future<void> openConsoleSection(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('console.menu')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key('console.tab.$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('console.tab.$id')));
  await tester.pumpAndSettle();
}
