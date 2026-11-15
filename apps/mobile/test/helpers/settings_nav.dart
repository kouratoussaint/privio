import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot 8.3a : depuis l'onglet Paramètres (déjà affiché), ouvre l'écran d'une ligne
/// (`settings.privacy`, `settings.security`, `settings.notifications`, `settings.chats`…).
Future<void> openSettingsEntry(WidgetTester tester, String key) async {
  // Repartir du haut de la page, puis descendre jusqu'à la ligne.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Fait défiler l'écran affiché jusqu'à la ligne [key].
Future<void> scrollToKey(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}
