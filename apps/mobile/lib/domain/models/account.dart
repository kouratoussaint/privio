/// Profil public minimal (aucune coordonnée privée).
class Profile {
  const Profile({required this.handle, required this.displayName, this.about, this.avatarPath});

  final String handle;
  final String displayName;
  final String? about;

  /// Photo de profil (chemin opaque dans le stockage privé), absente par défaut.
  final String? avatarPath;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    handle: json['handle'] as String,
    displayName: json['display_name'] as String,
    about: json['about'] as String?,
    avatarPath: json['avatar_path'] as String?,
  );
}

/// Compte de l'utilisateur connecté, tel que renvoyé par `get_my_account`.
class Account {
  const Account({
    required this.userId,
    required this.phoneE164,
    required this.phoneDiscoverable,
    this.profile,
  });

  final String userId;
  final String? phoneE164;
  final bool phoneDiscoverable;
  final Profile? profile;

  bool get hasProfile => profile != null;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    userId: json['user_id'] as String,
    phoneE164: json['phone_e164'] as String?,
    phoneDiscoverable: json['phone_discoverable'] as bool? ?? false,
    profile: json['profile'] == null
        ? null
        : Profile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
  );

  Account copyWith({bool? phoneDiscoverable}) => Account(
    userId: userId,
    phoneE164: phoneE164,
    phoneDiscoverable: phoneDiscoverable ?? this.phoneDiscoverable,
    profile: profile,
  );
}

/// Lot 8.4a : vérification en deux étapes de ce compte, vue par CETTE session.
class TwoStepState {
  const TwoStepState({
    required this.enabled,
    required this.verified,
    this.retryAt,
    this.resetRequestedAt,
  });

  final bool enabled;

  /// Ce téléphone a saisi le code (ou l'a activé) ; toujours vrai si désactivée.
  final bool verified;
  final DateTime? retryAt;

  /// Code oublié : demande envoyée à l'assistance.
  final DateTime? resetRequestedAt;

  bool get pending => enabled && !verified;

  factory TwoStepState.fromJson(Map<String, dynamic> j) => TwoStepState(
    enabled: j['enabled'] as bool? ?? false,
    verified: j['verified'] as bool? ?? true,
    retryAt: j['retry_at'] == null ? null : DateTime.parse(j['retry_at'] as String),
    resetRequestedAt: j['reset_requested_at'] == null
        ? null
        : DateTime.parse(j['reset_requested_at'] as String),
  );
}

/// Résultat d'une saisie du code de vérification.
class TwoStepCheck {
  const TwoStepCheck({required this.ok, this.retryAt, this.failures = 0});

  final bool ok;

  /// Trop d'erreurs : nouvel essai possible à partir de cette heure.
  final DateTime? retryAt;
  final int failures;

  factory TwoStepCheck.fromJson(Map<String, dynamic> j) => TwoStepCheck(
    ok: j['ok'] as bool? ?? false,
    retryAt: j['retry_at'] == null ? null : DateTime.parse(j['retry_at'] as String),
    failures: (j['failures'] as num?)?.toInt() ?? 0,
  );
}
