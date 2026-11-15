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

  /// Lot 8.1a : thème (« system », « light », « dark ») et taille du texte
  /// (« small », « normal », « large », « xlarge »).
  Future<String> themeChoice();
  Future<void> setThemeChoice(String value);
  Future<String> textSize();

  /// Lot 8.2a : langue de l'application (« fr » par défaut, « mos », « dyu »).
  Future<String> language();
  Future<void> setLanguage(String value);
  Future<void> setTextSize(String value);

  /// Lot 7.3b : contenu des GIF : « g » (tout public, par défaut) ou « pg13 » (modéré).
  Future<String> gifFilter();
  Future<void> setGifFilter(String value);

  /// Lot 7.3b : aperçus des liens que j'envoie (activés par défaut).
  Future<bool> linkPreviews();
  Future<void> setLinkPreviews(bool value);

  /// Lot 7.3a : fond d'écran des discussions ([conversationId] null : celui par défaut).
  /// Valeurs : `pattern:nom`, `color:nom` ou `photo:chemin local` ; null :
  /// pas de choix (par défaut, ou comme le réglage général pour une discussion).
  Future<String?> wallpaper(String? conversationId);
  Future<void> setWallpaper(String? conversationId, String? value);

  /// Lot 7.2b1 : groupes aussi dans l'onglet Discussions (faux par défaut : séparés).
  Future<bool> groupsInDiscussions();
  Future<void> setGroupsInDiscussions(bool value);

  /// Lot 8.4a : invitation « Protégez votre compte » fermée (« Plus tard »).
  Future<bool> twoStepPromptDismissed();
  Future<void> setTwoStepPromptDismissed();

  /// Lot 9.1b : affichage des appels en plein écran déjà proposé (une seule fois).
  Future<bool> fullScreenCallsAsked();
  Future<void> setFullScreenCallsAsked();

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
  static const _gifFilter = 'privio.gif_filter';
  static const _theme = 'privio.theme';
  static const _textSize = 'privio.text_size';
  static const _language = 'privio.language';
  static const _linkPreviews = 'privio.link_previews';
  static const _twoStepPrompt = 'privio.two_step_prompt_dismissed';
  static const _fullScreenCalls = 'privio.full_screen_calls_asked';
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
  Future<String> themeChoice() async {
    final v = await _prefs.getString(_theme);
    return v == 'light' || v == 'dark' ? v! : 'system';
  }

  @override
  Future<void> setThemeChoice(String value) => _prefs.setString(_theme, value);

  @override
  Future<String> textSize() async {
    final v = await _prefs.getString(_textSize);
    return const {'small', 'large', 'xlarge'}.contains(v) ? v! : 'normal';
  }

  @override
  Future<void> setTextSize(String value) => _prefs.setString(_textSize, value);

  @override
  Future<String> language() async {
    final v = await _prefs.getString(_language);
    return v == 'mos' || v == 'dyu' ? v! : 'fr';
  }

  @override
  Future<void> setLanguage(String value) => _prefs.setString(_language, value);

  @override
  Future<String> gifFilter() async => (await _prefs.getString(_gifFilter)) == 'pg13' ? 'pg13' : 'g';

  @override
  Future<void> setGifFilter(String value) =>
      _prefs.setString(_gifFilter, value == 'pg13' ? 'pg13' : 'g');

  @override
  Future<bool> linkPreviews() async => (await _prefs.getBool(_linkPreviews)) ?? true;

  @override
  Future<void> setLinkPreviews(bool value) => _prefs.setBool(_linkPreviews, value);

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
  Future<bool> twoStepPromptDismissed() async => (await _prefs.getBool(_twoStepPrompt)) ?? false;

  @override
  Future<void> setTwoStepPromptDismissed() => _prefs.setBool(_twoStepPrompt, true);

  @override
  Future<bool> fullScreenCallsAsked() async => (await _prefs.getBool(_fullScreenCalls)) ?? false;

  @override
  Future<void> setFullScreenCallsAsked() => _prefs.setBool(_fullScreenCalls, true);

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
