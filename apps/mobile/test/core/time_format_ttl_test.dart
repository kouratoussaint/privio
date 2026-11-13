import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/util/time_format.dart';

/// Lot 4.6 : durées proposées et affichage insécable.
void main() {
  test('8 durées proposées, de 5 min à 48 h', () {
    expect(kTtlChoices, [300, 900, 1800, 3600, 21600, 43200, 86400, 172800]);
  });

  test('formatTtl : minutes, heures, heures et minutes, sans coupure possible', () {
    expect(formatTtl(300), '5 min');
    expect(formatTtl(3600), '1 h');
    expect(formatTtl(4 * 3600 + 30 * 60), '4 h 30');
    expect(formatTtl(2 * 3600 + 5 * 60), '2 h 05');
    expect(formatTtl(259200), '72 h');
    expect(formatTtl(299), '5 min', reason: 'arrondi à la minute');
  });
}
