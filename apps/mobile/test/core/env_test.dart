import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/config/env.dart';

String _jwt(Map<String, dynamic> payload) =>
    'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

void main() {
  test('une clé secrète Supabase est refusée', () {
    expect(Env.keyLooksSecret('sb_secret_abc123'), isTrue);
    expect(Env.keyLooksSecret(_jwt({'role': 'service_role'})), isTrue);
  });

  test('une clé publique est acceptée', () {
    expect(Env.keyLooksSecret('sb_publishable_abc123'), isFalse);
    expect(Env.keyLooksSecret(_jwt({'role': 'anon'})), isFalse);
  });
}
