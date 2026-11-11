/// Profil public minimal (aucune coordonnée privée).
class Profile {
  const Profile({required this.handle, required this.displayName, this.about});

  final String handle;
  final String displayName;
  final String? about;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    handle: json['handle'] as String,
    displayName: json['display_name'] as String,
    about: json['about'] as String?,
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
