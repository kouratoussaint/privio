import 'package:shared_preferences/shared_preferences.dart';

/// Indicateurs locaux NON sensibles (aucun jeton, aucune donnée personnelle).
abstract interface class LocalFlags {
  Future<bool> onboardingDone();
  Future<void> setOnboardingDone();
  Future<bool> permissionsSeen();
  Future<void> setPermissionsSeen();
  Future<void> clearAccountScoped();

  /// Notifications activées sur ce téléphone (vrai par défaut).
  Future<bool> pushEnabled();
  Future<void> setPushEnabled(bool value);

  /// Réaction envoyée par un double appui sur un message (❤️ par défaut).
  Future<String> quickReaction();
  Future<void> setQuickReaction(String emoji);
}

class SharedPrefsLocalFlags implements LocalFlags {
  SharedPrefsLocalFlags({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _onboarding = 'privio.onboarding_consent_at';
  static const _permissions = 'privio.permissions_seen';
  static const _push = 'privio.push_enabled';
  static const _quick = 'privio.quick_reaction';
  final SharedPreferencesAsync _prefs;

  @override
  Future<bool> onboardingDone() async => (await _prefs.getString(_onboarding)) != null;

  /// Horodatage du consentement aux engagements affichés (AUTH-008).
  @override
  Future<void> setOnboardingDone() =>
      _prefs.setString(_onboarding, DateTime.now().toUtc().toIso8601String());

  @override
  Future<bool> permissionsSeen() async => (await _prefs.getBool(_permissions)) ?? false;

  @override
  Future<void> setPermissionsSeen() => _prefs.setBool(_permissions, true);

  @override
  Future<void> clearAccountScoped() => _prefs.remove(_permissions);

  @override
  Future<bool> pushEnabled() async => (await _prefs.getBool(_push)) ?? true;

  @override
  Future<void> setPushEnabled(bool value) => _prefs.setBool(_push, value);

  @override
  Future<String> quickReaction() async => (await _prefs.getString(_quick)) ?? '❤️';

  @override
  Future<void> setQuickReaction(String emoji) => _prefs.setString(_quick, emoji);
}
