import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('codes serveur des RPC', () {
    for (final entry in {
      'HANDLE_TAKEN': FailureCode.handleTaken,
      'RATE_LIMITED': FailureCode.rateLimited,
      'AUTH_REQUIRED': FailureCode.authRequired,
      'PHONE_NOT_VERIFIED': FailureCode.phoneNotVerified,
    }.entries) {
      expect(toAppFailure(PostgrestException(message: entry.key, code: 'P0001')).code, entry.value);
    }
    expect(toAppFailure(const PostgrestException(message: 'inattendu')).code, FailureCode.unknown);
  });

  test('erreurs Auth\u202F: code faux ou expiré, limites SMS, session perdue', () {
    expect(
      toAppFailure(const AuthException('x', code: 'otp_expired')).code,
      FailureCode.otpInvalidOrExpired,
    );
    expect(
      toAppFailure(const AuthException('x', code: 'over_sms_send_rate_limit')).code,
      FailureCode.smsRateLimited,
    );
    expect(
      toAppFailure(const AuthException('x', code: 'session_not_found')).code,
      FailureCode.authRequired,
    );
    expect(toAppFailure(const AuthException('x', statusCode: '429')).code, FailureCode.rateLimited);
  });

  test('erreurs réseau', () {
    expect(toAppFailure(const SocketException('hors ligne')).code, FailureCode.network);
  });

  test('chaque code a un message en français non vide', () {
    for (final code in FailureCode.values) {
      expect(AppFailure(code).message, isNotEmpty);
    }
  });
}
