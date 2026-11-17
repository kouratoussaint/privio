import '../../l10n/l10n.dart';

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
  photoQuotaReached,
  cameraUnavailable,
  notGroup,
  notAdmin,
  pinLimitReached,
  // Lot 8.4a : vérification en deux étapes.
  twoStepPinWeak,
  twoStepAlreadyEnabled,
  twoStepNotEnabled,
  twoStepRequired,
  // Lot 9.1a : appels.
  callsDisabled,
  callAlreadyActive,
  callDirectOnly,
  callNotFound,
  callEnded,
  callKindUnavailable,
  // Lot 5.5 : fonctionnalité coupée dans la console ; inscriptions fermées.
  featureDisabled,
  signupsClosed,
  viewOnceUnavailable,
  phoneTaken,
  gifUnavailable,
  notOwner,
  roleInvalid,
  groupFull,
  groupTitleInvalid,
  groupDescriptionInvalid,
  invitationNotFound,
  postingRestricted,
  clearScopeInvalid,
  clearNotAllowed,
  clearRequestNotFound,
  connectionRequired,
  connectionNotAllowed,
  connectionRetryLater,
  connectionDailyLimit,
  connectionRequestNotFound,
  connectionNoteTooLong,
  privacySettingInvalid,
  adminRequired,
  policyLocked,
  policyNotFound,
  policyOutOfBounds,
  policyTypeInvalid,
  featureNotImplemented,
  accountSuspended,
  groupClosed,
  moderationNoteRequired,
  moderationInvalid,
  reportNotFound,
  adminProtected,
  appealInvalid,
  appealNotAllowed,
  appealNotFound,
  supportReplyInvalid,
  searchPhoneIncomplete,
  searchTooShort,
  accountNotFound,
  // Lot 5.6 : identifiant imposé, @ réservés, photo et appareil (console).
  handleChangeNotAllowed,
  handleAlwaysReserved,
  avatarNotFound,
  deviceNotFound,
  // Lot 10.1
  readEraseInvalid,
  // Lot 10.4 : vérification en personne et surnom privé.
  verifyNotContact,
  verifyWrongPerson,
  verifyCodeInvalid,
  verifyCodeExpired,
  nicknameInvalid,
  nicknameNotAllowed,
  // Lot 10.5 : groupes « Annonces » et sondages.
  pollInvalid,
  pollClosed,
  pollNotFound,
  pollGroupOnly,
  announcementLocked,
  aboutTooLong,
  joinRequestNotFound,
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
    FailureCode.authRequired => L.t.votreSessionExpireReconnectezVous,
    FailureCode.rateLimited => L.t.tropTentativesPeuTempsReessayez,
    FailureCode.handleTaken => L.t.cetIdentifiantEstDejaPris,
    FailureCode.handleInvalid => L.t.cetIdentifiantNEstPas,
    FailureCode.displayNameInvalid => L.t.votreNomDoitContenirEntre,
    FailureCode.phoneNotVerified => L.t.votreNumeroNEstPas,
    FailureCode.profileExists => L.t.votreProfilExisteDeja,
    FailureCode.phoneInvalid => L.t.ceNumeroNEstPas,
    FailureCode.notMember => L.t.vousNeFaitesPasPartie,
    FailureCode.selfConversation => L.t.vousNePouvezPasVous,
    FailureCode.userNotFound => L.t.ceCompteNExistePas,
    FailureCode.blocked => L.t.vousNePouvezPasEcrire,
    FailureCode.bodyInvalid => L.t.messageEstVideOuTrop,
    FailureCode.messageNotFound => L.t.ceMessageNEstPlus,
    FailureCode.messageExpired => L.t.ceMessageEteEfface,
    FailureCode.messageDeleted => L.t.ceMessageEteSupprime,
    FailureCode.notSender => L.t.seulExpediteurPeutFaireCette,
    FailureCode.editWindowExpired => L.t.delaiPourModifierCeMessage,
    FailureCode.deleteWindowExpired => L.t.delaiPourSupprimerCeMessage,
    FailureCode.reactionInvalid => L.t.choisissezEmoji,
    FailureCode.ttlInvalid => L.t.cetteDureeNEstPas,
    FailureCode.messageNotEditable => L.t.ceMessageNePeutPas,
    FailureCode.reportInvalid => L.t.ceSignalementNPasPu,
    FailureCode.confirmationRequired => L.t.confirmationRequise,
    FailureCode.voiceTooLong => L.t.messageVocalDepasse30Secondes,
    FailureCode.voiceTooShort => L.t.messageVocalTropCourtMaintenez,
    FailureCode.mediaInvalid => L.t.ceFichierNPasPu,
    FailureCode.mediaTooLarge => L.t.ceFichierEstTropVolumineux,
    FailureCode.mediaNotFound => L.t.ceContenuNEstPlus,
    FailureCode.mediaUnavailable => L.t.envoiPhotosMessagesVocauxEst,
    FailureCode.microphoneUnavailable => L.t.microNEstPasDisponible,
    FailureCode.microphoneDenied => L.t.privioBesoinMicroPourEnregistrer,
    FailureCode.photoQuotaReached => L.t.vousAvezEnvoyeToutesVos,
    FailureCode.cameraUnavailable => L.t.appareilPhotoOuGalerieN,
    FailureCode.notGroup => L.t.cetteActionNEstPossible,
    FailureCode.notAdmin => L.t.seulsAdministrateursGroupePeuventFaire,
    FailureCode.phoneTaken => L.t.ceNumeroEstDejaUtilise,
    FailureCode.viewOnceUnavailable => L.t.ceMessageVueUniqueDeja,
    FailureCode.gifUnavailable => L.t.gifSontMomentanementIndisponiblesReessayez,
    FailureCode.pinLimitReached => L.t.troisMessagesSontDejaEpingles,
    FailureCode.twoStepPinWeak => L.t.codeTropSimpleSuiteOu,
    FailureCode.twoStepAlreadyEnabled => L.t.twoStepAlreadyEnabled,
    FailureCode.twoStepNotEnabled => L.t.twoStepNotEnabled,
    FailureCode.twoStepRequired => L.t.twoStepRequired,
    FailureCode.callsDisabled => L.t.callsDisabledError,
    FailureCode.callAlreadyActive => L.t.callAlreadyActiveError,
    FailureCode.callDirectOnly => L.t.callDirectOnlyError,
    FailureCode.callNotFound => L.t.callNotFoundError,
    FailureCode.callEnded => L.t.callEndedError,
    FailureCode.callKindUnavailable => L.t.callKindUnavailableError,
    FailureCode.featureDisabled => L.t.featureDisabledError,
    FailureCode.signupsClosed => L.t.signupsClosedError,
    FailureCode.notOwner => L.t.seulProprietaireGroupePeutFaire,
    FailureCode.roleInvalid => L.t.cetteActionNEstPas,
    FailureCode.groupFull => L.t.ceGroupeAtteintSaTaille,
    FailureCode.groupTitleInvalid => L.t.nomGroupeDoitContenirEntre,
    FailureCode.groupDescriptionInvalid => L.t.descriptionNeDoitPasDepasser,
    FailureCode.invitationNotFound => L.t.cetteInvitationNEstPlus,
    FailureCode.postingRestricted => L.t.seulsAdministrateursPeuventEnvoyerMessages,
    FailureCode.clearScopeInvalid => L.t.choixVidageInconnu,
    FailureCode.clearNotAllowed => L.t.impossibleViderPourVousDeux,
    FailureCode.clearRequestNotFound => L.t.cetteDemandeNExistePlus,
    FailureCode.connectionRequired => L.t.envoyezAbordDemandeConnexionCette,
    FailureCode.connectionNotAllowed => L.t.cettePersonneNAcceptePas,
    FailureCode.connectionRetryLater => L.t.votreDemandeEteRefuseeVous,
    FailureCode.connectionDailyLimit => L.t.vousAvezDejaEnvoye3,
    FailureCode.connectionRequestNotFound => L.t.cetteDemandeNEstPlus,
    FailureCode.connectionNoteTooLong => L.t.votreMotEstTropLong,
    FailureCode.privacySettingInvalid => L.t.reglageConfidentialiteInvalide,
    FailureCode.adminRequired => L.t.accesReserveAdministrationPrivio,
    FailureCode.policyLocked => L.t.ceReglageEstFixeNe,
    FailureCode.policyNotFound => L.t.ceReglageNExistePas,
    FailureCode.policyOutOfBounds => L.t.valeurHorsLimitesAutoriseesPour,
    FailureCode.policyTypeInvalid => L.t.valeurInvalidePourCeReglage,
    FailureCode.featureNotImplemented => L.t.cetteFonctionnaliteNEstPas,
    FailureCode.accountSuspended => L.t.votreCompteEstSuspendu,
    FailureCode.groupClosed => L.t.ceGroupeEteFermePar,
    FailureCode.moderationNoteRequired => L.t.indiquezMotif3500Caracteres,
    FailureCode.moderationInvalid => L.t.cetteDecisionNeAppliquePas,
    FailureCode.reportNotFound => L.t.ceSignalementDejaEteTraite,
    FailureCode.adminProtected => L.t.compteAdministrationNePeutPas,
    FailureCode.appealInvalid => L.t.votreContestationDoitContenirEntre,
    FailureCode.appealNotAllowed => L.t.vousAvezDejaContesteCette,
    FailureCode.appealNotFound => L.t.cetteContestationDejaEteExaminee,
    FailureCode.supportReplyInvalid => L.t.reponseDoitContenirEntre2,
    FailureCode.searchPhoneIncomplete => L.t.saisissezAuMoins4Chiffres,
    FailureCode.searchTooShort => L.t.saisissezMoins2Caracteres,
    FailureCode.accountNotFound => L.t.ceCompteNExistePlus,
    FailureCode.handleChangeNotAllowed => L.t.handleChangeNotAllowedError,
    FailureCode.handleAlwaysReserved => L.t.handleAlwaysReservedError,
    FailureCode.avatarNotFound => L.t.avatarNotFoundError,
    FailureCode.deviceNotFound => L.t.deviceNotFoundError,
    FailureCode.readEraseInvalid => L.t.readEraseInvalidError,
    FailureCode.verifyNotContact => L.t.verifyNotContactError,
    FailureCode.verifyWrongPerson => L.t.verifyWrongPersonError,
    FailureCode.verifyCodeInvalid => L.t.verifyCodeInvalidError,
    FailureCode.verifyCodeExpired => L.t.verifyCodeExpiredError,
    FailureCode.nicknameInvalid => L.t.nicknameInvalidError,
    FailureCode.nicknameNotAllowed => L.t.nicknameNotAllowedError,
    FailureCode.pollInvalid => L.t.pollInvalidError,
    FailureCode.pollClosed => L.t.pollClosedError,
    FailureCode.pollNotFound => L.t.pollNotFoundError,
    FailureCode.pollGroupOnly => L.t.pollGroupOnlyError,
    FailureCode.announcementLocked => L.t.announcementLockedError,
    FailureCode.aboutTooLong => L.t.propos140CaracteresPlus,
    FailureCode.joinRequestNotFound => L.t.cetteDemandeDejaEteTraitee,
    FailureCode.otpInvalidOrExpired => L.t.ceCodeNeFonctionnePas,
    FailureCode.smsRateLimited => L.t.tropCodesDemandesPatientezAvant,
    FailureCode.smsSendFailed => L.t.smsNPasPuEtre,
    FailureCode.serviceUnavailable => L.t.serviceConnexionEstMomentanementIndisponible,
    FailureCode.network => L.t.connexionImpossibleVerifiezVotreReseau,
    FailureCode.unknown => L.t.problemeEstSurvenuReessayezSi,
  };

  @override
  String toString() => L.t.appfailureCode(code);
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
  'PHOTO_QUOTA_REACHED': FailureCode.photoQuotaReached,
  'NOT_GROUP': FailureCode.notGroup,
  'NOT_ADMIN': FailureCode.notAdmin,
  'PIN_LIMIT_REACHED': FailureCode.pinLimitReached,
  'TWO_STEP_PIN_WEAK': FailureCode.twoStepPinWeak,
  'TWO_STEP_ALREADY_ENABLED': FailureCode.twoStepAlreadyEnabled,
  'TWO_STEP_NOT_ENABLED': FailureCode.twoStepNotEnabled,
  'TWO_STEP_REQUIRED': FailureCode.twoStepRequired,
  'CALLS_DISABLED': FailureCode.callsDisabled,
  'CALL_ALREADY_ACTIVE': FailureCode.callAlreadyActive,
  'CALL_DIRECT_ONLY': FailureCode.callDirectOnly,
  'CALL_NOT_FOUND': FailureCode.callNotFound,
  'CALL_NOT_RINGING': FailureCode.callEnded,
  'CALL_ENDED': FailureCode.callEnded,
  'CALL_KIND_UNAVAILABLE': FailureCode.callKindUnavailable,
  'FEATURE_DISABLED': FailureCode.featureDisabled,
  'SIGNUPS_CLOSED': FailureCode.signupsClosed,
  'VIEW_ONCE_UNAVAILABLE': FailureCode.viewOnceUnavailable,
  'GIF_UNAVAILABLE': FailureCode.gifUnavailable,
  'GIF_NOT_FOUND': FailureCode.gifUnavailable,
  'NOT_OWNER': FailureCode.notOwner,
  'ROLE_INVALID': FailureCode.roleInvalid,
  'SETTING_INVALID': FailureCode.roleInvalid,
  'GROUP_FULL': FailureCode.groupFull,
  'GROUP_TITLE_INVALID': FailureCode.groupTitleInvalid,
  'GROUP_DESCRIPTION_INVALID': FailureCode.groupDescriptionInvalid,
  'INVITATION_NOT_FOUND': FailureCode.invitationNotFound,
  'POSTING_RESTRICTED': FailureCode.postingRestricted,
  'CLEAR_SCOPE_INVALID': FailureCode.clearScopeInvalid,
  'CLEAR_NOT_ALLOWED': FailureCode.clearNotAllowed,
  'CLEAR_REQUEST_NOT_FOUND': FailureCode.clearRequestNotFound,
  'CONNECTION_REQUIRED': FailureCode.connectionRequired,
  'CONNECTION_NOT_ALLOWED': FailureCode.connectionNotAllowed,
  'CONNECTION_RETRY_LATER': FailureCode.connectionRetryLater,
  'CONNECTION_DAILY_LIMIT': FailureCode.connectionDailyLimit,
  'CONNECTION_REQUEST_NOT_FOUND': FailureCode.connectionRequestNotFound,
  'CONNECTION_NOTE_TOO_LONG': FailureCode.connectionNoteTooLong,
  'PRIVACY_SETTING_INVALID': FailureCode.privacySettingInvalid,
  'ADMIN_REQUIRED': FailureCode.adminRequired,
  'POLICY_LOCKED': FailureCode.policyLocked,
  'POLICY_NOT_FOUND': FailureCode.policyNotFound,
  'POLICY_OUT_OF_BOUNDS': FailureCode.policyOutOfBounds,
  'POLICY_TYPE_INVALID': FailureCode.policyTypeInvalid,
  'FEATURE_NOT_IMPLEMENTED': FailureCode.featureNotImplemented,
  'ACCOUNT_SUSPENDED': FailureCode.accountSuspended,
  'GROUP_CLOSED': FailureCode.groupClosed,
  'MODERATION_NOTE_REQUIRED': FailureCode.moderationNoteRequired,
  'MODERATION_INVALID': FailureCode.moderationInvalid,
  'REPORT_NOT_FOUND': FailureCode.reportNotFound,
  'ADMIN_PROTECTED': FailureCode.adminProtected,
  'APPEAL_INVALID': FailureCode.appealInvalid,
  'APPEAL_NOT_ALLOWED': FailureCode.appealNotAllowed,
  'APPEAL_NOT_FOUND': FailureCode.appealNotFound,
  'SUPPORT_REPLY_INVALID': FailureCode.supportReplyInvalid,
  'SEARCH_PHONE_INCOMPLETE': FailureCode.searchPhoneIncomplete,
  'SEARCH_TOO_SHORT': FailureCode.searchTooShort,
  'ACCOUNT_NOT_FOUND': FailureCode.accountNotFound,
  'HANDLE_CHANGE_NOT_ALLOWED': FailureCode.handleChangeNotAllowed,
  'HANDLE_ALWAYS_RESERVED': FailureCode.handleAlwaysReserved,
  'AVATAR_NOT_FOUND': FailureCode.avatarNotFound,
  'DEVICE_NOT_FOUND': FailureCode.deviceNotFound,
  'READ_ERASE_INVALID': FailureCode.readEraseInvalid,
  'VERIFY_NOT_CONTACT': FailureCode.verifyNotContact,
  'VERIFY_WRONG_PERSON': FailureCode.verifyWrongPerson,
  'VERIFY_CODE_INVALID': FailureCode.verifyCodeInvalid,
  'VERIFY_CODE_EXPIRED': FailureCode.verifyCodeExpired,
  'NICKNAME_INVALID': FailureCode.nicknameInvalid,
  'NICKNAME_NOT_ALLOWED': FailureCode.nicknameNotAllowed,
  'POLL_INVALID': FailureCode.pollInvalid,
  'POLL_CLOSED': FailureCode.pollClosed,
  'POLL_NOT_FOUND': FailureCode.pollNotFound,
  'POLL_GROUP_ONLY': FailureCode.pollGroupOnly,
  'ANNOUNCEMENT_LOCKED': FailureCode.announcementLocked,
  'ABOUT_TOO_LONG': FailureCode.aboutTooLong,
  'JOIN_REQUEST_NOT_FOUND': FailureCode.joinRequestNotFound,
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
      case 'phone_exists':
        return const AppFailure(FailureCode.phoneTaken);
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
