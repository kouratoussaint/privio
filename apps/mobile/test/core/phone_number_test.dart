import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/phone/phone_number.dart';

void main() {
  group('PhoneNumber.normalize (miroir de private.normalize_phone_e164)', () {
    final cases = <String, String?>{
      '70000001': '+22670000001',
      '70 00 00 01': '+22670000001',
      '70-00-00-01': '+22670000001',
      '(70) 00.00.01': '+22670000001',
      '+22670000001': '+22670000001',
      '0022670000001': '+22670000001',
      '+33612345678': '+33612345678',
      '': null,
      '7000001': null,
      '700000011': null,
      '+0123456789': null,
      '+2': null,
      'abc': null,
      '+22670000001234567': null,
    };
    cases.forEach((input, expected) {
      test(
        '«\u202F$input\u202F» → $expected',
        () => expect(PhoneNumber.normalize(input), expected),
      );
    });
  });

  test('format lisible pour le Burkina, brut sinon', () {
    expect(PhoneNumber.format('+22670000001'), '+226 70 00 00 01');
    expect(PhoneNumber.format('+33612345678'), '+33612345678');
  });
}
