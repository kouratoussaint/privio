import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// Lot 8.2a : textes de l'application dans la langue choisie, accessibles partout (même
/// hors des widgets : erreurs, notifications, messages système). Mis à jour par
/// [PrivioApp] quand la langue change ; toute l'application est alors reconstruite.
abstract final class L {
  static AppLocalizations t = lookupAppLocalizations(const Locale('fr'));

  static void use(Locale locale) => t = lookupAppLocalizations(locale);
}

/// Langues proposées dans Paramètres → Langue et sur l'écran de bienvenue. Une langue n'y
/// entre qu'une fois tous ses textes P1 traduits et relus (décision D du 15/11/2026) ;
/// avant, elle reste cachée et les textes non traduits s'affichent en français.
const kReleasedLanguages = ['fr'];

/// Toutes les langues prévues (code, nom dans la langue elle-même).
const kLanguages = {'fr': 'Français', 'mos': 'Mooré', 'dyu': 'Dioula'};

/// Langues réellement proposées (remplaçable dans les tests).
final releasedLanguagesProvider = Provider<List<String>>((ref) => kReleasedLanguages);

/// Android ne connaît ni le mooré ni le dioula : les textes standard (boutons « OK »,
/// sélecteurs…) restent alors en français au lieu de faire échouer l'application.
class FallbackLocalizationsDelegate<T> extends LocalizationsDelegate<T> {
  const FallbackLocalizationsDelegate(this.inner);

  final LocalizationsDelegate<T> inner;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) =>
      inner.load(inner.isSupported(locale) ? locale : const Locale('fr'));

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;

  @override
  Type get type => T;
}
