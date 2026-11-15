/// Règles de l'identifiant Privio. Miroir de `private.normalize_handle` et
/// `private.handle_is_valid` : le serveur reste l'autorité, ces règles servent
/// seulement à guider la saisie.
enum HandleIssue { empty, tooShort, tooLong, invalidCharacters, invalidEdges, doubleDot, reserved }

abstract final class HandleRules {
  static const minLength = 3;
  static const maxLength = 24;
  static const reserved = {
    'privio',
    'admin',
    'administrateur',
    'administrator',
    'support',
    'aide',
    'help',
    'moderation',
    'moderateur',
    'moderator',
    'securite',
    'security',
    'systeme',
    'system',
    'root',
    'officiel',
    'official',
    'staff',
    'equipe',
    'team',
    'null',
    'undefined',
    'contact',
  };
  static final _allowed = RegExp(r'^[a-z0-9_.]+$');
  static final _edges = RegExp(r'^[a-z0-9].*[a-z0-9]$');

  static String normalize(String input) =>
      input.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  static HandleIssue? validate(String normalized) {
    if (normalized.isEmpty) return HandleIssue.empty;
    if (normalized.length < minLength) return HandleIssue.tooShort;
    if (normalized.length > maxLength) return HandleIssue.tooLong;
    if (!_allowed.hasMatch(normalized)) return HandleIssue.invalidCharacters;
    if (!_edges.hasMatch(normalized)) return HandleIssue.invalidEdges;
    if (normalized.contains('..')) return HandleIssue.doubleDot;
    if (reserved.contains(normalized)) return HandleIssue.reserved;
    return null;
  }

  static String message(HandleIssue issue) => switch (issue) {
    HandleIssue.empty => 'Choisissez un identifiant.',
    HandleIssue.tooShort => 'Au moins $minLength caractères.',
    HandleIssue.tooLong => 'Au maximum $maxLength caractères.',
    HandleIssue.invalidCharacters =>
      'Lettres minuscules sans accent, chiffres, « _ » et « . » uniquement.',
    HandleIssue.invalidEdges => 'Commencez et terminez par une lettre ou un chiffre.',
    HandleIssue.doubleDot => 'Deux points de suite ne sont pas autorisés.',
    HandleIssue.reserved => 'Cet identifiant est réservé.',
  };
}

/// Lot 8.1a : contenu du QR code d'un identifiant (lisible seulement dans Privio).
String profileQrData(String handle) => 'privio:@$handle';

/// Identifiant lu dans un QR code Privio (« privio:@identifiant »), sinon null.
String? parseProfileCode(String? raw) {
  final v = (raw ?? '').trim();
  final m = RegExp(r'^privio:@(\S+)$', caseSensitive: false).firstMatch(v);
  if (m == null) return null;
  final handle = HandleRules.normalize(m.group(1)!);
  return HandleRules.validate(handle) == null ? handle : null;
}
