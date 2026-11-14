import 'dart:async';

import 'package:privio/ui/core/motion/motion.dart';

/// Lot 7.2b2 : les animations en boucle (illustrations, points d'écriture, chargement) sont
/// figées dans les tests, sinon `pumpAndSettle` attendrait sans fin.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Motion.loopsEnabled = false;
  await testMain();
}
