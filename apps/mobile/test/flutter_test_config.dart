import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/ui/core/motion/motion.dart';
import 'package:privio/ui/features/conversations/expression_panel.dart';
import 'package:privio/ui/features/conversations/photo_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lot 7.2b2 : les animations en boucle (illustrations, points d'écriture, chargement) sont
/// figées dans les tests, sinon `pumpAndSettle` attendrait sans fin.
/// Lot 7.3a : sélecteur d'émojis sans canal natif ; retouche photo sans isolat ; émojis
/// récents gardés en mémoire.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Motion.loopsEnabled = false;
  ExpressionPanel.inTests = true;
  PhotoEditorScreen.inline = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
