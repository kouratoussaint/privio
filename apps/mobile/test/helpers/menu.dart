import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot 8.5a : touche une action d'un menu ouvert ; si elle est derrière « Voir plus »,
/// déplie d'abord le menu.
Future<void> tapMenuItem(WidgetTester tester, Key item) async {
  if (find.byKey(item).evaluate().isEmpty &&
      find.byKey(const Key('menu.more')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('menu.more')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(item));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(item));
}
