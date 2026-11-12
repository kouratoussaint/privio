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
  notMember,
  selfConversation,
  userNotFound,
  blocked,
  bodyInvalid,
  messageNotFound,
  messageExpired,
  messageDeleted,
  notSender,
  editWindowExpired,
  deleteWindowExpired,
  reactionInvalid,
  ttlInvalid,
  messageNotEditable,
  reportInvalid,
  confirmationRequired,
  voiceTooLong,
  voiceTooShort,
  mediaInvalid,
  mediaTooLarge,
  mediaNotFound,
  mediaUnavailable,
  microphoneUnavailable,
  microphoneDenied,
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
    FailureCode.notMember => 'Vous ne faites pas partie de cette discussion.',
    FailureCode.selfConversation => 'Vous ne pouvez pas vous écrire à vous-même.',
    FailureCode.userNotFound => 'Ce compte n\'existe pas ou a été supprimé.',
    FailureCode.blocked => 'Vous ne pouvez pas écrire à ce contact.',
    FailureCode.bodyInvalid => 'Le message est vide ou trop long (4 000 caractères au plus).',
    FailureCode.messageNotFound => 'Ce message n\'est plus disponible.',
    FailureCode.messageExpired => 'Ce message a expiré.',
    FailureCode.messageDeleted => 'Ce message a été supprimé.',
    FailureCode.notSender => 'Seul l\'expéditeur peut faire cette action.',
    FailureCode.editWindowExpired => 'Le délai pour modifier ce message est dépassé (60 minutes).',
    FailureCode.deleteWindowExpired => 'Le délai pour supprimer ce message pour tous est dépassé.',
    FailureCode.reactionInvalid => 'Choisissez un emoji.',
    FailureCode.ttlInvalid => 'Cette durée n\'est pas autorisée.',
    FailureCode.messageNotEditable => 'Ce message ne peut pas être modifié.',
    FailureCode.reportInvalid =>
      'Ce signalement n\'a pas pu être enregistré. Vérifiez les informations.',
    FailureCode.confirmationRequired => 'Confirmation requise.',
    FailureCode.voiceTooLong => 'Le message vocal dépasse 30 secondes.',
    FailureCode.voiceTooShort => 'Message vocal trop court. Maintenez le micro pour parler.',
    FailureCode.mediaInvalid => 'Ce message vocal n\'a pas pu être lu. Enregistrez-le à nouveau.',
    FailureCode.mediaTooLarge => 'Ce message vocal est trop volumineux.',
    FailureCode.mediaNotFound => 'Ce message vocal n\'est plus disponible.',
    FailureCode.mediaUnavailable =>
      'Le service des messages vocaux est momentanément indisponible. Réessayez.',
    FailureCode.microphoneUnavailable => 'Le micro n\'est pas disponible.',
    FailureCode.microphoneDenied => 'Privio a besoin du micro pour enregistrer un message vocal.',
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
  'NOT_MEMBER': FailureCode.notMember,
  'SELF_CONVERSATION': FailureCode.selfConversation,
  'USER_NOT_FOUND': FailureCode.userNotFound,
  'BLOCKED': FailureCode.blocked,
  'BODY_INVALID': FailureCode.bodyInvalid,
  'IDEMPOTENCY_CONFLICT': FailureCode.unknown,
  'REPLY_NOT_FOUND': FailureCode.messageNotFound,
  'MESSAGE_NOT_FOUND': FailureCode.messageNotFound,
  'MESSAGE_EXPIRED': FailureCode.messageExpired,
  'MESSAGE_DELETED': FailureCode.messageDeleted,
  'NOT_SENDER': FailureCode.notSender,
  'EDIT_WINDOW_EXPIRED': FailureCode.editWindowExpired,
  'DELETE_WINDOW_EXPIRED': FailureCode.deleteWindowExpired,
  'REACTION_INVALID': FailureCode.reactionInvalid,
  'TTL_INVALID': FailureCode.ttlInvalid,
  'MESSAGE_NOT_EDITABLE': FailureCode.messageNotEditable,
  'REPORT_INVALID': FailureCode.reportInvalid,
  'CONFIRMATION_REQUIRED': FailureCode.confirmationRequired,
  'VOICE_TOO_LONG': FailureCode.voiceTooLong,
  'VOICE_TOO_SHORT': FailureCode.voiceTooShort,
  'MEDIA_INVALID': FailureCode.mediaInvalid,
  'MEDIA_TOO_LARGE': FailureCode.mediaTooLarge,
  'MEDIA_NOT_FOUND': FailureCode.mediaNotFound,
  'STORAGE_UNAVAILABLE': FailureCode.mediaUnavailable,
};

/// Convertit toute erreur en [AppFailure]. Ne journalise rien (pas de donnée sensible).
AppFailure toAppFailure(Object error) {
  if (error is AppFailure) return error;
  if (error is PostgrestException) {
    return AppFailure(_serverCodes[error.message.trim()] ?? FailureCode.unknown);
  }
  if (error is AuthRetryableFetchException) return const AppFailure(FailureCode.network);
  // Fonctions (envoi d'un vocal) : code métier dans le corps JSON { "error": "CODE" }.
  // Requête qui n'a pas abouti (pas de réseau, coupure) : on réessaiera.
  if (error is FunctionsFetchException) return const AppFailure(FailureCode.network);
  if (error is FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    if (code is String && _serverCodes[code] != null) return AppFailure(_serverCodes[code]!);
    if (error.status == 401) return const AppFailure(FailureCode.authRequired);
    if (error.status == 429) return const AppFailure(FailureCode.rateLimited);
    if (error.status >= 500) return const AppFailure(FailureCode.mediaUnavailable);
    return const AppFailure(FailureCode.unknown);
  }
  // Stockage (téléchargement d'un vocal) : 400/404 = expiré, supprimé ou non autorisé.
  if (error is StorageException) {
    return switch (error.statusCode) {
      '400' || '403' || '404' => const AppFailure(FailureCode.mediaNotFound),
      '401' => const AppFailure(FailureCode.authRequired),
      _ => const AppFailure(FailureCode.mediaUnavailable),
    };
  }
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
