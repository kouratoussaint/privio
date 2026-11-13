import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/handle/handle_rules.dart';

void main() {
  test('normalisation identique au serveur', () {
    expect(HandleRules.normalize('  @Alice_BF '), 'alice_bf');
    expect(HandleRules.normalize('@@bob'), 'bob');
  });

  group('validation (miroir de private.handle_is_valid)', () {
    final cases = <String, HandleIssue?>{
      'alice_bf': null,
      'a.b': null,
      'bob2026': null,
      '': HandleIssue.empty,
      'ab': HandleIssue.tooShort,
      'a' * 25: HandleIssue.tooLong,
      'élodie': HandleIssue.invalidCharacters,
      'jean-luc': HandleIssue.invalidCharacters,
      '_alice': HandleIssue.invalidEdges,
      'alice.': HandleIssue.invalidEdges,
      'ali..ce': HandleIssue.doubleDot,
      'admin': HandleIssue.reserved,
      'privio': HandleIssue.reserved,
    };
    cases.forEach((input, expected) {
      test('«\u202F$input\u202F» → $expected', () => expect(HandleRules.validate(input), expected));
    });
  });

  test('chaque problème a un message en français', () {
    for (final issue in HandleIssue.values) {
      expect(HandleRules.message(issue), isNotEmpty);
    }
  });
}
