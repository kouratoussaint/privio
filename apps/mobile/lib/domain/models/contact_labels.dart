/// Lot 10.4 — mes étiquettes sur les autres personnes : surnom privé et vérification en
/// personne (ADR-048). Gardées sur le serveur pour mon compte seulement (RPC
/// `my_contact_labels`) et copiées sur ce téléphone pour l'affichage hors connexion.
class ContactLabel {
  const ContactLabel({
    required this.userId,
    this.nickname,
    this.verification,
    this.verifiedAt,
    this.lapse,
    this.notice = false,
  });

  final String userId;

  /// Surnom privé (visible par moi seul), ou null.
  final String? nickname;

  /// « verified », « lapsed » (vérification à refaire) ou null (jamais vérifié).
  final String? verification;
  final DateTime? verifiedAt;

  /// Pourquoi le badge est tombé : « device », « phone » ou « both ».
  final String? lapse;

  /// Avis « vérification à refaire » à montrer (pas encore fermé).
  final bool notice;

  bool get verified => verification == 'verified';
  bool get lapsed => verification == 'lapsed';

  factory ContactLabel.fromJson(Map<String, dynamic> j) => ContactLabel(
    userId: j['user_id'] as String,
    nickname: j['nickname'] as String?,
    verification: j['verification'] as String?,
    verifiedAt: j['verified_at'] == null ? null : DateTime.parse(j['verified_at'] as String),
    lapse: j['lapse'] as String?,
    notice: j['notice'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'nickname': nickname,
    'verification': verification,
    'verified_at': verifiedAt?.toUtc().toIso8601String(),
    'lapse': lapse,
    'notice': notice,
  };

  ContactLabel copyWith({String? nickname, bool clearNickname = false, bool? notice}) =>
      ContactLabel(
        userId: userId,
        nickname: clearNickname ? null : (nickname ?? this.nickname),
        verification: verification,
        verifiedAt: verifiedAt,
        lapse: lapse,
        notice: notice ?? this.notice,
      );
}

/// Code de vérification en personne, montré en QR code (« privio:v:<code> »).
class VerificationCode {
  const VerificationCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  /// Contenu du QR code.
  String get qrData => verificationQrData(code);

  factory VerificationCode.fromJson(Map<String, dynamic> j) => VerificationCode(
    code: j['code'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );
}

String verificationQrData(String code) => 'privio:v:$code';

/// Code lu dans un QR code de vérification Privio, sinon null.
String? parseVerificationCode(String? raw) {
  final m = RegExp(r'^privio:v:([0-9a-f]{32})$').firstMatch((raw ?? '').trim());
  return m?.group(1);
}

/// Étiquettes en cours, lues par les modèles pour afficher un nom (comme `L.t` pour les
/// textes). Tenues à jour par `contactLabelsProvider` ; les écrans qui montrent des noms
/// suivent ce fournisseur pour se redessiner.
abstract final class ContactLabels {
  static Map<String, ContactLabel> _current = const {};

  static Map<String, ContactLabel> get current => _current;

  static set current(Map<String, ContactLabel> labels) => _current = Map.unmodifiable(labels);

  static void reset() => _current = const {};

  static ContactLabel? of(String? userId) => userId == null ? null : _current[userId];

  /// Surnom privé de [userId], ou null.
  static String? nicknameOf(String? userId) => of(userId)?.nickname;

  /// Nom à afficher : le surnom s'il y en a un, sinon [name].
  static String nameOf(String? userId, String name) => nicknameOf(userId) ?? name;

  static bool isVerified(String? userId) => of(userId)?.verified ?? false;
}
