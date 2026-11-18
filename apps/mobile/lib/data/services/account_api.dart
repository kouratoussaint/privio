import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/account.dart';
import '../../domain/models/moderation.dart';

/// Accès au compte via les RPC sécurisées (aucun accès direct aux tables privées).
abstract interface class AccountApi {
  Future<Account> getMyAccount();
  Future<Profile> createProfile({required String handle, required String displayName});
  Future<bool> isHandleAvailable(String handle);
  Future<bool> setPhoneDiscoverable(bool value);

  /// Lot 5.6 : modèle et version d'Android, visibles par l'assistance (console).
  Future<String> registerDevice({required String appVersion, String? model, String? osVersion});
  Future<void> unregisterCurrentDevice();

  /// Lot 5.6 : nouvel identifiant, seulement quand l'équipe Privio a remplacé l'ancien.
  Future<String> chooseNewHandle(String handle);

  /// Jeton de notification de CET appareil (lot 4.1).
  Future<void> registerPushToken(String token);
  Future<void> unregisterPushToken();

  /// Photo de profil : envoyée à avatar-set (vérifiée, métadonnées retirées) ; renvoie son
  /// chemin. L'ancienne photo est effacée par le serveur.
  Future<String> setAvatar(Uint8List jpeg);
  Future<void> removeAvatar();

  /// Lot 7.1a : « À propos » (140 caractères ; vide = retiré). Renvoie le texte enregistré.
  Future<String?> setAbout(String text);

  /// Lot 7.2a : nom affiché (1 à 40 caractères) ; renvoie le nom enregistré.
  Future<String> setDisplayName(String name);

  /// Lot 5.3 : suspension ou avertissement en cours pour ce compte.
  Future<ModerationStatus> moderationStatus();
  Future<void> submitAppeal(String sanctionId, String text);
  Future<void> acknowledgeWarning(String sanctionId);

  /// Lot 8.4a : vérification en deux étapes (code de vérification à 6 chiffres).
  Future<TwoStepState> twoStepState();
  Future<void> enableTwoStep(String pin);
  Future<TwoStepCheck> verifyTwoStep(String pin);
  Future<TwoStepCheck> changeTwoStep(String current, String next);
  Future<TwoStepCheck> disableTwoStep(String pin);
  Future<TwoStepCheck> authorizePhoneChange(String pin);

  /// Code oublié : demande à l'assistance ; renvoie l'heure de la demande.
  Future<DateTime> requestTwoStepReset();

  /// Lot 8.4b : rappel avant effacement (activé par défaut).
  Future<bool> expiryReminder();
  Future<bool> setExpiryReminder(bool on);

  /// Lot 5.9 : inscriptions « Sur liste » : état pour ce numéro (avant le profil), code
  /// d'invitation, langue de ce téléphone (statistiques).
  Future<({String mode, bool allowed})> signupStatus();
  Future<void> redeemSignupCode(String code);
  Future<void> setDeviceLanguage(String language);
}

class SupabaseAccountApi implements AccountApi {
  SupabaseAccountApi(this._client);

  final SupabaseClient _client;

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<Account> getMyAccount() async =>
      Account.fromJson(Map<String, dynamic>.from(await _rpc('get_my_account') as Map));

  @override
  Future<Profile> createProfile({required String handle, required String displayName}) async {
    final rows = await _rpc('create_profile', {
      'p_handle': handle,
      'p_display_name': displayName,
    }) as List<dynamic>;
    return Profile.fromJson(Map<String, dynamic>.from(rows.single as Map));
  }

  @override
  Future<bool> isHandleAvailable(String handle) async =>
      await _rpc('is_handle_available', {'p_handle': handle}) as bool;

  @override
  Future<bool> setPhoneDiscoverable(bool value) async =>
      await _rpc('set_phone_discoverable', {'p_discoverable': value}) as bool;

  @override
  Future<String> registerDevice({
    required String appVersion,
    String? model,
    String? osVersion,
  }) async => await _rpc('register_device', {
    'p_platform': 'android',
    'p_app_version': appVersion,
    'p_model': model,
    'p_os_version': osVersion,
  }) as String;

  @override
  Future<String> chooseNewHandle(String handle) async =>
      await _rpc('choose_new_handle', {'p_handle': handle}) as String;

  @override
  Future<void> unregisterCurrentDevice() async => _rpc('unregister_current_device');

  @override
  Future<void> registerPushToken(String token) async =>
      _rpc('register_push_token', {'p_token': token});

  @override
  Future<void> unregisterPushToken() async => _rpc('unregister_push_token');

  @override
  Future<String> setAvatar(Uint8List jpeg) async {
    try {
      final res = await _client.functions.invoke(
        'avatar-set',
        body: jpeg,
        headers: const {'Content-Type': 'image/jpeg'},
      );
      return (res.data as Map)['avatar_path'] as String;
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  @override
  Future<void> removeAvatar() async => _rpc('remove_avatar');

  @override
  Future<ModerationStatus> moderationStatus() async => ModerationStatus.fromJson(
    Map<String, dynamic>.from(await _rpc('my_moderation_status') as Map),
  );

  @override
  Future<void> submitAppeal(String sanctionId, String text) =>
      _rpc('submit_appeal', {'p_sanction_id': sanctionId, 'p_text': text});

  @override
  Future<void> acknowledgeWarning(String sanctionId) =>
      _rpc('acknowledge_warning', {'p_sanction_id': sanctionId});

  @override
  Future<String?> setAbout(String text) async =>
      await _rpc('set_my_about', {'p_about': text}) as String?;

  @override
  Future<String> setDisplayName(String name) async =>
      await _rpc('set_my_display_name', {'p_display_name': name}) as String;

  Future<TwoStepCheck> _check(String fn, Map<String, dynamic> params) async =>
      TwoStepCheck.fromJson(Map<String, dynamic>.from(await _rpc(fn, params) as Map));

  @override
  Future<TwoStepState> twoStepState() async =>
      TwoStepState.fromJson(Map<String, dynamic>.from(await _rpc('two_step_state') as Map));

  @override
  Future<void> enableTwoStep(String pin) async => _rpc('enable_two_step', {'p_pin': pin});

  @override
  Future<TwoStepCheck> verifyTwoStep(String pin) => _check('verify_two_step', {'p_pin': pin});

  @override
  Future<TwoStepCheck> changeTwoStep(String current, String next) =>
      _check('change_two_step', {'p_current': current, 'p_new': next});

  @override
  Future<TwoStepCheck> disableTwoStep(String pin) => _check('disable_two_step', {'p_pin': pin});

  @override
  Future<TwoStepCheck> authorizePhoneChange(String pin) =>
      _check('authorize_phone_change', {'p_pin': pin});

  @override
  Future<DateTime> requestTwoStepReset() async =>
      DateTime.parse(await _rpc('request_two_step_reset') as String);

  @override
  Future<bool> expiryReminder() async => await _rpc('get_expiry_reminder') as bool;

  @override
  Future<bool> setExpiryReminder(bool on) async =>
      await _rpc('set_expiry_reminder', {'p_on': on}) as bool;

  @override
  Future<({String mode, bool allowed})> signupStatus() async {
    final j = Map<String, dynamic>.from(await _rpc('signup_status', {}) as Map);
    return (mode: j['mode'] as String? ?? 'open', allowed: j['allowed'] as bool? ?? true);
  }

  @override
  Future<void> redeemSignupCode(String code) => _rpc('redeem_signup_code', {'p_code': code});

  @override
  Future<void> setDeviceLanguage(String language) =>
      _rpc('set_device_language', {'p_language': language});
}
