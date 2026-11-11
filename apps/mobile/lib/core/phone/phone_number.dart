/// Numéros de téléphone au format E.164.
/// Miroir exact de `private.normalize_phone_e164` (migration 1) : 8 chiffres sans
/// indicatif = Burkina Faso (+226) ; préfixe `00` converti en `+`.
abstract final class PhoneNumber {
  static const defaultCountryCode = '+226';
  static final _separators = RegExp(r'[\s\-.()]');
  static final _burkinaLocal = RegExp(r'^[0-9]{8}$');
  static final _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');

  /// Renvoie le numéro E.164, ou `null` s'il est invalide.
  static String? normalize(String input) {
    var v = input.replaceAll(_separators, '');
    if (v.isEmpty) return null;
    if (v.startsWith('00')) {
      v = '+${v.substring(2)}';
    } else if (_burkinaLocal.hasMatch(v)) {
      v = '$defaultCountryCode$v';
    } else if (!v.startsWith('+')) {
      return null;
    }
    return _e164.hasMatch(v) ? v : null;
  }

  /// Affichage lisible : « +226 70 00 00 01 » pour le Burkina, E.164 brut sinon.
  static String format(String e164) {
    if (e164.startsWith(defaultCountryCode) && e164.length == 12) {
      final d = e164.substring(4);
      return '$defaultCountryCode ${d.substring(0, 2)} ${d.substring(2, 4)} '
          '${d.substring(4, 6)} ${d.substring(6, 8)}';
    }
    return e164;
  }
}
