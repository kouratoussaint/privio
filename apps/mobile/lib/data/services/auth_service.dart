import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';

/// Authentification PAR TÉLÉPHONE UNIQUEMENT (décision du 11/11/2026).
/// Volontairement, cette interface n'expose aucune méthode e-mail ni mot de passe.
abstract interface class AuthService {
  bool get hasSession;
  Stream<void> get changes;
  Future<void> requestOtp(String phoneE164);
  Future<void> verifyOtp({required String phoneE164, required String code});
  Future<void> signOut();

  /// Lot 8.1c : changer de numéro. Le code part vers le NOUVEAU numéro ; rien ne change
  /// tant qu'il n'est pas saisi. Renvoie vrai si le changement est déjà fait (projet sans
  /// confirmation par SMS).
  Future<bool> requestPhoneChange(String newPhoneE164);
  Future<void> verifyPhoneChange({required String newPhoneE164, required String code});
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final GoTrueClient _auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  Stream<void> get changes => _auth.onAuthStateChange.map((_) {});

  @override
  Future<void> requestOtp(String phoneE164) async {
    try {
      await _auth.signInWithOtp(phone: phoneE164, shouldCreateUser: true);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<void> verifyOtp({required String phoneE164, required String code}) async {
    try {
      final res = await _auth.verifyOTP(phone: phoneE164, token: code, type: OtpType.sms);
      if (res.session == null) throw const AppFailure(FailureCode.otpInvalidOrExpired);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<bool> requestPhoneChange(String newPhoneE164) async {
    try {
      final res = await _auth.updateUser(UserAttributes(phone: newPhoneE164));
      final now = res.user?.phone;
      return now != null && '+${now.replaceFirst('+', '')}' == newPhoneE164;
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<void> verifyPhoneChange({required String newPhoneE164, required String code}) async {
    try {
      await _auth.verifyOTP(phone: newPhoneE164, token: code, type: OtpType.phoneChange);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  /// Révoque la session courante côté serveur et efface la session locale.
  /// Si la session est déjà invalide (appareil remplacé), on nettoie localement.
  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object {
      await _auth.signOut(scope: SignOutScope.local).catchError((_) {});
    }
  }
}
