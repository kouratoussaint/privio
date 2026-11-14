import 'dart:convert';

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

  /// Lot 7.2b2 : sons et vibrations dans l'application (vrai par défaut).
  Future<bool> soundsEnabled();
  Future<void> setSoundsEnabled(bool value);

  /// Lot 7.3a : fond d'écran des discussions ([conversationId] null : celui par défaut).
  /// Valeurs : `pattern:nom`, `color:nom` ou `photo:chemin local` ; null :
  /// pas de choix (par défaut, ou comme le réglage général pour une discussion).
  Future<String?> wallpaper(String? conversationId);
  Future<void> setWallpaper(String? conversationId, String? value);

  /// Lot 7.2b1 : groupes aussi dans l'onglet Discussions (faux par défaut : séparés).
  Future<bool> groupsInDiscussions();
  Future<void> setGroupsInDiscussions(bool value);

  // Économie de données (lot 4.2).
  /// 'always', 'wifi' ou 'never' (téléchargement automatique des photos).
  Future<String> photoAutoDownload();
  Future<void> setPhotoAutoDownload(String value);

  /// Octets de médias reçus / envoyés, par mois : {'2026-11:in': 1234, '2026-11:out': 56}.
  Future<Map<String, int>> dataUsage();
  Future<void> saveDataUsage(Map<String, int> usage);
}

class SharedPrefsLocalFlags implements LocalFlags {
  SharedPrefsLocalFlags({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _onboarding = 'privio.onboarding_consent_at';
  static const _permissions = 'privio.permissions_seen';
  static const _push = 'privio.push_enabled';
  static const _quick = 'privio.quick_reaction';
  static const _autoPhoto = 'privio.photo_auto_download';
  static const _usage = 'privio.data_usage';
  static const _groupsInDiscussions = 'privio.groups_in_discussions';
  static const _sounds = 'privio.sounds_enabled';
  static const _wallpaper = 'privio.wallpaper';
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

  @override
  Future<String?> wallpaper(String? conversationId) =>
      _prefs.getString(conversationId == null ? _wallpaper : '$_wallpaper.$conversationId');

  @override
  Future<void> setWallpaper(String? conversationId, String? value) {
    final key = conversationId == null ? _wallpaper : '$_wallpaper.$conversationId';
    return value == null ? _prefs.remove(key) : _prefs.setString(key, value);
  }

  @override
  Future<bool> soundsEnabled() async => (await _prefs.getBool(_sounds)) ?? true;

  @override
  Future<void> setSoundsEnabled(bool value) => _prefs.setBool(_sounds, value);

  @override
  Future<bool> groupsInDiscussions() async => (await _prefs.getBool(_groupsInDiscussions)) ?? false;

  @override
  Future<void> setGroupsInDiscussions(bool value) => _prefs.setBool(_groupsInDiscussions, value);

  @override
  Future<String> photoAutoDownload() async => (await _prefs.getString(_autoPhoto)) ?? 'always';

  @override
  Future<void> setPhotoAutoDownload(String value) => _prefs.setString(_autoPhoto, value);

  @override
  Future<Map<String, int>> dataUsage() async {
    final raw = await _prefs.getString(_usage);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: (e.value as num).toInt(),
      };
    } on Object {
      return {};
    }
  }

  @override
  Future<void> saveDataUsage(Map<String, int> usage) => _prefs.setString(_usage, jsonEncode(usage));
}
