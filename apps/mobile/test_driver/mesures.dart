import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Lot 6.1 : pilote de `flutter drive` ; écrit les mesures dans build/mesures.json
/// (reprises dans le résumé de la CI).
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final f = File('build/mesures.json')..createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data ?? {}));
  },
);
