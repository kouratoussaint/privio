import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Erreurs normalisées (dossier 07 + identité). Les codes serveur sont levés par les
/// fonctions SQL avec `raise exception '<CODE>'` et arrivent dans `PostgrestException.message`.
enum FailureCode {
  authRequired,
  rateLimited,
  handleTaken,
  handleInvalid,
  displayNameInvalid,
  phoneNotVerified,
  profileExists,
  phoneInvalid,
  otpInvalidOrExpired,
  smsRateLimited,
  smsSendFailed,
  serviceUnavailable,
  network,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.code);

  final FailureCode code;

  String get message => switch (code) {
    FailureCode.authRequired => 'Votre session a expiré. Reconnectez-vous.',
    FailureCode.rateLimited => 'Trop de tentatives en peu de temps. Réessayez un peu plus tard.',
    FailureCode.handleTaken => 'Cet identifiant est déjà pris. Essayez-en un autre.',
    FailureCode.handleInvalid => 'Cet identifiant n\'est pas valide.',
    FailureCode.displayNameInvalid => 'Votre nom doit contenir entre 1 et 40 caractères.',
    FailureCode.phoneNotVerified =>
      'Votre numéro n\'est pas encore vérifié. Reconnectez-vous avec le code SMS.',
    FailureCode.profileExists => 'Votre profil existe déjà.',
    FailureCode.phoneInvalid => 'Ce numéro n\'est pas valide.',
    FailureCode.otpInvalidOrExpired => 'Code incorrect ou expiré.',
    FailureCode.smsRateLimited =>
      'Trop de codes demandés. Patientez avant de demander un nouveau code.',
    FailureCode.smsSendFailed =>
      'Le SMS n\'a pas pu être envoyé. Vérifiez le numéro puis réessayez.',
    FailureCode.serviceUnavailable => 'Le service de connexion est momentanément indisponible.',
    FailureCode.network => 'Connexion impossible. Vérifiez votre réseau puis réessayez.',
    FailureCode.unknown => 'Une erreur est survenue. Réessayez.',
  };

  @override
  String toString() => 'AppFailure($code)';
}

const _serverCodes = <String, FailureCode>{
  'AUTH_REQUIRED': FailureCode.authRequired,
  'RATE_LIMITED': FailureCode.rateLimited,
  'HANDLE_TAKEN': FailureCode.handleTaken,
  'HANDLE_INVALID': FailureCode.handleInvalid,
  'DISPLAY_NAME_INVALID': FailureCode.displayNameInvalid,
  'PHONE_NOT_VERIFIED': FailureCode.phoneNotVerified,
  'PROFILE_EXISTS': FailureCode.profileExists,
};

/// Convertit toute erreur en [AppFailure]. Ne journalise rien (pas de donnée sensible).
AppFailure toAppFailure(Object error) {
  if (error is AppFailure) return error;
  if (error is PostgrestException) {
    return AppFailure(_serverCodes[error.message.trim()] ?? FailureCode.unknown);
  }
  if (error is AuthRetryableFetchException) return const AppFailure(FailureCode.network);
  if (error is AuthException) {
    switch (error.code) {
      case 'otp_expired':
        return const AppFailure(FailureCode.otpInvalidOrExpired);
      case 'over_sms_send_rate_limit':
        return const AppFailure(FailureCode.smsRateLimited);
      case 'over_request_rate_limit':
        return const AppFailure(FailureCode.rateLimited);
      case 'sms_send_failed':
        return const AppFailure(FailureCode.smsSendFailed);
      case 'phone_provider_disabled':
      case 'otp_disabled':
      case 'signup_disabled':
        return const AppFailure(FailureCode.serviceUnavailable);
      case 'validation_failed':
        return const AppFailure(FailureCode.phoneInvalid);
      case 'session_not_found':
      case 'refresh_token_not_found':
      case 'refresh_token_already_used':
        return const AppFailure(FailureCode.authRequired);
    }
    if (error.statusCode == '429') return const AppFailure(FailureCode.rateLimited);
    return const AppFailure(FailureCode.unknown);
  }
  if (error is SocketException || error is TimeoutException || error is HttpException) {
    return const AppFailure(FailureCode.network);
  }
  return const AppFailure(FailureCode.unknown);
}
