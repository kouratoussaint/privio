import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/account.dart';

/// Accès au compte via les RPC sécurisées (aucun accès direct aux tables privées).
abstract interface class AccountApi {
  Future<Account> getMyAccount();
  Future<Profile> createProfile({required String handle, required String displayName});
  Future<bool> isHandleAvailable(String handle);
  Future<bool> setPhoneDiscoverable(bool value);
  Future<String> registerDevice({required String appVersion});
  Future<void> unregisterCurrentDevice();
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
}
