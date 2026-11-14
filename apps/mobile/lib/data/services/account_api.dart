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
  Future<String> registerDevice({required String appVersion});
  Future<void> unregisterCurrentDevice();

  /// Jeton de notification de CET appareil (lot 4.1).
  Future<void> registerPushToken(String token);
  Future<void> unregisterPushToken();

  /// Photo de profil : envoyée à avatar-set (vérifiée, métadonnées retirées) ; renvoie son
  /// chemin. L'ancienne photo est effacée par le serveur.
  Future<String> setAvatar(Uint8List jpeg);
  Future<void> removeAvatar();

  /// Lot 7.1a : « À propos » (140 caractères ; vide = retiré). Renvoie le texte enregistré.
  Future<String?> setAbout(String text);

  /// Lot 5.3 : suspension ou avertissement en cours pour ce compte.
  Future<ModerationStatus> moderationStatus();
  Future<void> submitAppeal(String sanctionId, String text);
  Future<void> acknowledgeWarning(String sanctionId);
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
  Future<String> registerDevice({required String appVersion}) async =>
      await _rpc('register_device', {'p_platform': 'android', 'p_app_version': appVersion})
          as String;

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
}
