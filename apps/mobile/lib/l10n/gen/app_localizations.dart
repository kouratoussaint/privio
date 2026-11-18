import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_dyu.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_mos.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('dyu'), Locale('fr'), Locale('mos')];

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre session a expiré. Reconnectez-vous.'**
  String get votreSessionExpireReconnectezVous;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives en peu de temps. Réessayez un peu plus tard.'**
  String get tropTentativesPeuTempsReessayez;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cet identifiant est déjà pris. Essayez-en un autre.'**
  String get cetIdentifiantEstDejaPris;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cet identifiant n’est pas valide.'**
  String get cetIdentifiantNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre nom doit contenir entre 1 et 40 caractères.'**
  String get votreNomDoitContenirEntre;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre numéro n’est pas encore vérifié. Reconnectez-vous avec le code SMS.'**
  String get votreNumeroNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre profil existe déjà.'**
  String get votreProfilExisteDeja;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce numéro n’est pas valide.'**
  String get ceNumeroNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne faites pas partie de cette discussion.'**
  String get vousNeFaitesPasPartie;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez pas vous écrire à vous-même.'**
  String get vousNePouvezPasVous;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce compte n’existe pas ou a été supprimé.'**
  String get ceCompteNExistePas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez pas écrire à ce contact.'**
  String get vousNePouvezPasEcrire;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le message est vide ou trop long (4 000 caractères au plus).'**
  String get messageEstVideOuTrop;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message n’est plus disponible.'**
  String get ceMessageNEstPlus;

  /// Écran : core/errors/app_failure.dart, ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message a été effacé.'**
  String get ceMessageEteEfface;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message a été supprimé.'**
  String get ceMessageEteSupprime;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Seul l’expéditeur peut faire cette action.'**
  String get seulExpediteurPeutFaireCette;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le délai pour modifier ce message est dépassé (60 minutes).'**
  String get delaiPourModifierCeMessage;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le délai pour supprimer ce message pour tous est dépassé.'**
  String get delaiPourSupprimerCeMessage;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un emoji.'**
  String get choisissezEmoji;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette durée n’est pas autorisée.'**
  String get cetteDureeNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message ne peut pas être modifié.'**
  String get ceMessageNePeutPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce signalement n’a pas pu être enregistré. Vérifiez les informations.'**
  String get ceSignalementNPasPu;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Confirmation requise.'**
  String get confirmationRequise;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le message vocal dépasse 30 secondes.'**
  String get messageVocalDepasse30Secondes;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Message vocal trop court. Maintenez le micro pour parler.'**
  String get messageVocalTropCourtMaintenez;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce fichier n’a pas pu être lu. Choisissez-en un autre.'**
  String get ceFichierNPasPu;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce fichier est trop volumineux.'**
  String get ceFichierEstTropVolumineux;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce contenu n’est plus disponible.'**
  String get ceContenuNEstPlus;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'L’envoi des photos et messages vocaux est momentanément indisponible. Réessayez.'**
  String get envoiPhotosMessagesVocauxEst;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le micro n’est pas disponible.'**
  String get microNEstPasDisponible;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Privio a besoin du micro pour enregistrer un message vocal.'**
  String get privioBesoinMicroPourEnregistrer;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez envoyé toutes vos photos du jour. Prochaines photos demain, dès minuit.'**
  String get vousAvezEnvoyeToutesVos;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'L’appareil photo ou la galerie n’est pas disponible.'**
  String get appareilPhotoOuGalerieN;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette action n’est possible que dans un groupe.'**
  String get cetteActionNEstPossible;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs du groupe peuvent faire cela.'**
  String get seulsAdministrateursGroupePeuventFaire;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce numéro est déjà utilisé par un autre compte Privio.'**
  String get ceNumeroEstDejaUtilise;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message en vue unique a déjà été ouvert.'**
  String get ceMessageVueUniqueDeja;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Les GIF sont momentanément indisponibles. Réessayez dans un instant.'**
  String get gifSontMomentanementIndisponiblesReessayez;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Trois messages sont déjà épinglés. Désépinglez-en un pour en épingler un autre.'**
  String get troisMessagesSontDejaEpingles;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Seul le propriétaire du groupe peut faire cela.'**
  String get seulProprietaireGroupePeutFaire;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette action n’est pas possible pour ce membre.'**
  String get cetteActionNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce groupe a atteint sa taille maximale.'**
  String get ceGroupeAtteintSaTaille;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le nom du groupe doit contenir entre 1 et 60 caractères.'**
  String get nomGroupeDoitContenirEntre;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'La description ne doit pas dépasser 300 caractères.'**
  String get descriptionNeDoitPasDepasser;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette invitation n’est plus valable.'**
  String get cetteInvitationNEstPlus;

  /// Écran : core/errors/app_failure.dart, ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs peuvent envoyer des messages dans ce groupe.'**
  String get seulsAdministrateursPeuventEnvoyerMessages;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Choix de vidage inconnu.'**
  String get choixVidageInconnu;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Impossible de vider pour vous deux : la personne est bloquée ou son compte supprimé. Vous pouvez vider la discussion chez vous.'**
  String get impossibleViderPourVousDeux;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette demande n’existe plus (annulée, refusée ou expirée).'**
  String get cetteDemandeNExistePlus;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyez d’abord une demande de connexion à cette personne.'**
  String get envoyezAbordDemandeConnexionCette;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette personne n’accepte pas de demandes.'**
  String get cettePersonneNAcceptePas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre demande a été refusée. Vous pourrez réessayer dans quelques minutes.'**
  String get votreDemandeEteRefuseeVous;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez déjà envoyé 3 demandes à cette personne aujourd’hui. Réessayez demain.'**
  String get vousAvezDejaEnvoye3;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette demande n’est plus valable.'**
  String get cetteDemandeNEstPlus;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre mot est trop long (140 caractères au plus).'**
  String get votreMotEstTropLong;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Réglage de confidentialité invalide.'**
  String get reglageConfidentialiteInvalide;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Accès réservé à l’administration de Privio.'**
  String get accesReserveAdministrationPrivio;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce réglage est fixé et ne peut pas être modifié.'**
  String get ceReglageEstFixeNe;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce réglage n’existe pas.'**
  String get ceReglageNExistePas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Valeur hors des limites autorisées pour ce réglage.'**
  String get valeurHorsLimitesAutoriseesPour;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Valeur invalide pour ce réglage.'**
  String get valeurInvalidePourCeReglage;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette fonctionnalité n’est pas encore développée.'**
  String get cetteFonctionnaliteNEstPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre compte est suspendu.'**
  String get votreCompteEstSuspendu;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce groupe a été fermé par Privio.'**
  String get ceGroupeEteFermePar;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Indiquez un motif (3 à 500 caractères).'**
  String get indiquezMotif3500Caracteres;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette décision ne s’applique pas à ce dossier.'**
  String get cetteDecisionNeAppliquePas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce signalement a déjà été traité ou n’existe plus.'**
  String get ceSignalementDejaEteTraite;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le compte de l’administration ne peut pas être sanctionné.'**
  String get compteAdministrationNePeutPas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre contestation doit contenir entre 3 et 500 caractères.'**
  String get votreContestationDoitContenirEntre;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez déjà contesté cette sanction.'**
  String get vousAvezDejaContesteCette;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette contestation a déjà été examinée.'**
  String get cetteContestationDejaEteExaminee;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'La réponse doit contenir entre 2 et 1 000 caractères.'**
  String get reponseDoitContenirEntre2;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le numéro complet (8 chiffres, ou avec l’indicatif).'**
  String get saisissezNumeroComplet8Chiffres;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Saisissez au moins 2 caractères.'**
  String get saisissezMoins2Caracteres;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce compte n’existe plus.'**
  String get ceCompteNExistePlus;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'« À propos » : 140 caractères au plus.'**
  String get propos140CaracteresPlus;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette demande a déjà été traitée ou a été annulée.'**
  String get cetteDemandeDejaEteTraitee;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce code ne fonctionne pas. Vérifiez-le ou demandez-en un nouveau.'**
  String get ceCodeNeFonctionnePas;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Trop de codes demandés. Patientez avant de demander un nouveau code.'**
  String get tropCodesDemandesPatientezAvant;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le SMS n’a pas pu être envoyé. Vérifiez le numéro puis réessayez.'**
  String get smsNPasPuEtre;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Le service de connexion est momentanément indisponible.'**
  String get serviceConnexionEstMomentanementIndisponible;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Connexion impossible. Vérifiez votre réseau puis réessayez.'**
  String get connexionImpossibleVerifiezVotreReseau;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'Un problème est survenu. Réessayez ; si cela continue, écrivez à l’assistance (Paramètres > Aide et assistance).'**
  String get problemeEstSurvenuReessayezSi;

  /// Écran : core/errors/app_failure.dart
  ///
  /// In fr, this message translates to:
  /// **'AppFailure({code})'**
  String appfailureCode(Object code);

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un identifiant.'**
  String get choisissezIdentifiant;

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Au moins {minLength} caractères.'**
  String moinsMinlengthCaracteres(Object minLength);

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Au maximum {maxLength} caractères.'**
  String maximumMaxlengthCaracteres(Object maxLength);

  /// Écran : core/handle/handle_rules.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Lettres minuscules sans accent, chiffres, « _ » et « . » uniquement.'**
  String get lettresMinusculesSansAccentChiffres;

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Commencez et terminez par une lettre ou un chiffre.'**
  String get commencezTerminezParLettreOu;

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Deux points de suite ne sont pas autorisés.'**
  String get deuxPointsSuiteNeSont;

  /// Écran : core/handle/handle_rules.dart
  ///
  /// In fr, this message translates to:
  /// **'Cet identifiant est réservé.'**
  String get cetIdentifiantEstReserve;

  /// Écran : core/util/time_format.dart
  ///
  /// In fr, this message translates to:
  /// **'< 1 min'**
  String get n1Min;

  /// Écran : data/services/realtime_service.dart
  ///
  /// In fr, this message translates to:
  /// **'Connecté'**
  String get connecte;

  /// Écran : data/services/realtime_service.dart
  ///
  /// In fr, this message translates to:
  /// **'Connexion…'**
  String get connexion;

  /// Écran : data/services/realtime_service.dart
  ///
  /// In fr, this message translates to:
  /// **'Arrêté'**
  String get arrete;

  /// Écran : data/services/realtime_service.dart
  ///
  /// In fr, this message translates to:
  /// **'fermé'**
  String get ferme;

  /// Écran : data/services/share_service.dart
  ///
  /// In fr, this message translates to:
  /// **' Mon identifiant : @{handle}'**
  String monIdentifiantHandle(Object handle);

  /// Écran : data/services/share_service.dart
  ///
  /// In fr, this message translates to:
  /// **'Je suis sur Privio, la messagerie privée où les messages s’effacent tout seuls.{me}'**
  String jeSuisSurPrivioMessagerie(Object me);

  /// Écran : data/services/share_service.dart
  ///
  /// In fr, this message translates to:
  /// **'Rejoins-moi sur Privio'**
  String get rejoinsMoiSurPrivio;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe'**
  String get groupe;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Compte supprimé'**
  String get compteSupprime;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Inconnu'**
  String get inconnu;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Propriétaire'**
  String get proprietaire;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Administrateur'**
  String get administrateur;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Invitation envoyée'**
  String get invitationEnvoyee;

  /// Écran : domain/models/messaging.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Membre'**
  String get membre;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Quelqu’un'**
  String get quelqu;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'un membre'**
  String get membre2;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez rejoint le groupe'**
  String get vousAvezRejointGroupe;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'{a} a rejoint le groupe'**
  String rejointGroupe(Object a);

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez quitté le groupe'**
  String get vousAvezQuitteGroupe;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'{a} a quitté le groupe'**
  String quitteGroupe(Object a);

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'{t} est maintenant propriétaire du groupe'**
  String tEstMaintenantProprietaireGroupe(Object t);

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce groupe a été fermé par Privio'**
  String get ceGroupeEteFermePar2;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Tout le monde'**
  String get toutMonde;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Mes contacts'**
  String get mesContacts;

  /// Écran : domain/models/messaging.dart
  ///
  /// In fr, this message translates to:
  /// **'Personne'**
  String get personne;

  /// Écran : domain/models/messaging.dart, ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ancien membre'**
  String get ancienMembre;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Spam'**
  String get spam;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Harcèlement'**
  String get harcelement;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Contenu inapproprié'**
  String get contenuInapproprie;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Menace'**
  String get menace;

  /// Écran : domain/models/moderation.dart, ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Usurpation d’identité'**
  String get usurpationIdentite;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Autre'**
  String get autre;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande d’assistance'**
  String get demandeAssistance;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Classé sans suite'**
  String get classeSansSuite;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Avertissement'**
  String get avertissement;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Suspension'**
  String get suspension;

  /// Écran : domain/models/moderation.dart, ui/features/conversations/chat_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Message supprimé'**
  String get messageSupprime;

  /// Écran : domain/models/moderation.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe fermé'**
  String get groupeFerme;

  /// Écran : domain/models/moderation.dart, ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Répondue'**
  String get repondue;

  /// Écran : main.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Configuration absente : compilez avec --dart-define=SUPABASE_URL=… et --dart-define=SUPABASE_PUBLISHABLE_KEY=… (voir README).'**
  String get configurationAbsenteCompilezAvecDart;

  /// Écran : main.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Clé refusée : une clé SECRÈTE Supabase ne doit jamais être intégrée à l\'application. Utilisez la clé publique (publishable).'**
  String get cleRefuseeCleSecreteSupabase;

  /// Écran : state/app_lock_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller Privio'**
  String get deverrouillerPrivio;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Petit'**
  String get petit;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Normal'**
  String get normal;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Grand'**
  String get grand;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Très grand'**
  String get tresGrand;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Automatique (comme le téléphone)'**
  String get automatiqueCommeTelephone;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get clair;

  /// Écran : state/appearance_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get sombre;

  /// Écran : state/data_providers.dart, ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Toujours'**
  String get toujours;

  /// Écran : state/data_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'En Wi-Fi seulement'**
  String get wiFiSeulement;

  /// Écran : state/data_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'Jamais (toucher pour télécharger)'**
  String get jamaisToucherPourTelecharger;

  /// Écran : state/data_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'{bytes} Ko'**
  String bytesKo(Object bytes);

  /// Écran : state/privacy_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'en ligne'**
  String get ligne;

  /// Écran : state/privacy_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'vu aujourd’hui à {time}'**
  String vuAujourdHuiTime(Object time);

  /// Écran : state/privacy_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'vu hier à {time}'**
  String vuHierTime(Object time);

  /// Écran : state/privacy_providers.dart
  ///
  /// In fr, this message translates to:
  /// **'vu le {day}/{month} à {time}'**
  String vuDayMonthTime(Object day, Object month, Object time);

  /// Écran : state/session_controller.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre compte Privio a été supprimé, ainsi que vos messages envoyés. Vous pouvez créer un nouveau compte à tout moment.'**
  String get votreComptePrivioEteSupprime;

  /// Écran : state/session_controller.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce téléphone a été déconnecté par l’assistance Privio. Reconnectez-vous avec votre numéro pour continuer.'**
  String get ceTelephoneEteDeconnectePar;

  /// Écran : state/session_controller.dart
  ///
  /// In fr, this message translates to:
  /// **'Privio est maintenant ouvert sur un autre téléphone (un seul à la fois). Reconnectez-vous pour l’utiliser ici.'**
  String get privioEstMaintenantOuvertSur;

  /// Écran : ui/core/motion/illustrations.dart, ui/core/widgets/state_views.dart
  ///
  /// In fr, this message translates to:
  /// **'Chargement…'**
  String get chargement;

  /// Écran : ui/core/widgets/brand_scaffold.dart, ui/core/widgets/privio_brand.dart
  ///
  /// In fr, this message translates to:
  /// **'Privio'**
  String get privio;

  /// Écran : ui/core/widgets/privio_brand.dart
  ///
  /// In fr, this message translates to:
  /// **'Logo Privio'**
  String get logoPrivio;

  /// Écran : ui/core/widgets/state_views.dart, ui/features/conversations/gif_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get reessayer;

  /// Écran : ui/core/widgets/state_views.dart, ui/features/conversations/photo_widgets.dart, ui/features/conversations/rich_messages.dart, ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get fermer;

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Au moins {min}.'**
  String moinsMin(Object min);

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Au plus {max}.'**
  String plusMax(Object max);

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Durée personnalisée'**
  String get dureePersonnalisee;

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Personnalisé'**
  String get personnalise;

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Personnalisé · {current}'**
  String personnaliseCurrent(Object current);

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Actuellement : {current}'**
  String actuellementCurrent(Object current);

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Heures'**
  String get heures;

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Entre {min} et {max}.'**
  String entreMinMax(Object min, Object max);

  /// Écran : ui/core/widgets/ttl_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get retour;

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Un nouveau code vous a été envoyé.'**
  String get nouveauCodeVousEteEnvoye;

  /// Écran : ui/features/auth/otp_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Code de vérification'**
  String get codeVerification;

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vérification…'**
  String get verification;

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get valider;

  /// Écran : ui/features/auth/otp_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code à 6 chiffres envoyé par SMS au {phoneE164}.'**
  String saisissezCode6ChiffresEnvoye(Object phoneE164);

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Code reçu par SMS'**
  String get codeRecuParSms;

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Renvoyer le code'**
  String get renvoyerCode;

  /// Écran : ui/features/auth/otp_screen.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Renvoyer le code dans {secondsLeft} s'**
  String renvoyerCodeDansSecondsleft(Object secondsLeft);

  /// Écran : ui/features/auth/otp_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Modifier le numéro'**
  String get modifierNumero;

  /// Écran : ui/features/auth/otp_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Toujours rien ? Vérifiez le numéro ou votre réseau, puis renvoyez le code.'**
  String get toujoursRienVerifiezNumeroOu;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro incomplet : 8 chiffres pour le Burkina Faso (ex. 70 12 34 56). Autre pays : commencez par +.'**
  String get numeroIncomplet8ChiffresPour;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre numéro'**
  String get votreNumero;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoi du code…'**
  String get envoiCode;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Recevoir le code'**
  String get recevoirCode;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Quel est votre numéro ? Vous recevrez un code par SMS.'**
  String get quelEstVotreNumeroVous;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro de téléphone'**
  String get numeroTelephone;

  /// Écran : ui/features/auth/phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Burkina Faso (+226) par défaut.'**
  String get burkinaFaso226ParDefaut;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec mon numéro'**
  String get continuerAvecMonNumero;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Un code de vérification vous sera envoyé par SMS.'**
  String get codeVerificationVousSeraEnvoye;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Messagerie privée et éphémère'**
  String get messageriePriveeEphemere;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les messages s’effacent'**
  String get messagesEffacent;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Transport protégé'**
  String get transportProtege;

  /// Écran : ui/features/auth/welcome_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupes privés'**
  String get groupesPrives;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Message épinglé'**
  String get messageEpingle;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Message désépinglé.'**
  String get messageDesepingle;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Message épinglé.'**
  String get messageEpingle2;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{n} messages ajoutés aux favoris.'**
  String nMessagesAjoutesFavoris(Object n);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouté aux favoris.'**
  String get ajouteFavoris;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{n} messages retirés des favoris.'**
  String nMessagesRetiresFavoris(Object n);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Retiré des favoris.'**
  String get retireFavoris;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer les {n} messages pour moi'**
  String supprimerNMessagesPourMoi(Object n);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer pour moi'**
  String get supprimerPourMoi;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer les {n} messages pour tout le monde'**
  String supprimerNMessagesPourTout(Object n);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer pour tout le monde'**
  String get supprimerPourToutMonde;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer {n} messages pour tout le monde ?'**
  String supprimerNMessagesPourTout2(Object n);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer pour tout le monde ?'**
  String get supprimerPourToutMonde2;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ils seront remplacés par « Message supprimé » chez tous.'**
  String get ilsSerontRemplacesParMessage;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/conversations/new_conversation_screen.dart, ui/features/conversations/person_card.dart, ui/features/conversations/photo_editor.dart, ui/features/conversations/photo_widgets.dart, ui/features/conversations/rich_messages.dart, ui/features/groups/group_code_screen.dart, ui/features/groups/group_screens.dart, ui/features/home/discussions_tab.dart, ui/features/home/groups_tab.dart, ui/features/lock/app_lock_screens.dart, ui/features/settings/help_screen.dart, ui/features/settings/my_profile_screen.dart, ui/features/settings/settings_tab.dart, ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get annuler;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get supprimer;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler la sélection'**
  String get annulerSelection;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer des favoris'**
  String get retirerFavoris;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter aux favoris'**
  String get ajouterFavoris;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous'**
  String get vous;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Durée des messages'**
  String get dureeMessages;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour les prochains messages du groupe.'**
  String get pourProchainsMessagesGroupe;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour les prochains messages, chez vous deux.'**
  String get pourProchainsMessagesChezVous;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Durée de ce message'**
  String get dureeCeMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour ce message seulement, au plus {cap}.'**
  String pourCeMessageSeulementPlus(Object cap);

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/conversations/photo_widgets.dart, ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo'**
  String get photo;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Autoriser le micro'**
  String get autoriserMicro;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le micro est désactivé pour Privio. Activez-le dans les réglages du téléphone pour enregistrer des messages vocaux. Le reste de l’application fonctionne sans.'**
  String get microEstDesactivePourPrivio;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/permissions/permissions_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Plus tard'**
  String get plusTard;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir les réglages'**
  String get ouvrirReglages;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Arrêter et écouter'**
  String get arreterEcouter;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer la modification'**
  String get enregistrerModification;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get envoyer;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce message ?'**
  String get supprimerCeMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour vous seulement, ou pour tout le monde dans cette discussion.'**
  String get pourVousSeulementOuPour;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le message ne sera plus affiché sur votre téléphone.'**
  String get messageNeSeraPlusAffiche;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour moi'**
  String get pourMoi;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour tout le monde'**
  String get pourToutMonde;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Infos du groupe'**
  String get infosGroupe;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Voir la fiche'**
  String get voirFiche;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/new_conversation_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get rechercher;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Médias'**
  String get medias;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Messages favoris'**
  String get messagesFavoris;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Réactiver les notifications'**
  String get reactiverNotifications;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Sourdine'**
  String get sourdine;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/groups/group_screens.dart, ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Fond d’écran'**
  String get fondEcran;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Inviter'**
  String get inviter;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Vider la discussion'**
  String get viderDiscussion;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Quitter le groupe'**
  String get quitterGroupe;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Bloquer'**
  String get bloquer;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Signaler'**
  String get signaler;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Sourdine activée'**
  String get sourdineActivee;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mettre en sourdine'**
  String get mettreSourdine;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Bloquer {title} ?'**
  String bloquerTitle(Object title);

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pourrez plus vous écrire, dans un sens comme dans l’autre, et cette personne ne pourra plus vous trouver. Vous pourrez la débloquer à tout moment.'**
  String get vousNePourrezPlusVous;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{title} est bloqué.'**
  String titleEstBloque(Object title);

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart, ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande annulée.'**
  String get demandeAnnulee;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussion supprimée.'**
  String get discussionSupprimee;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussion vidée.'**
  String get discussionVidee;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande refusée.'**
  String get demandeRefusee;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer {e}'**
  String retirerE(Object e);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Réagir {e}'**
  String reagirE(Object e);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Autres émojis'**
  String get autresEmojis;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Répondre'**
  String get repondre;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get modifier;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Désépingler'**
  String get desepingler;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Épingler'**
  String get epingler;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Infos'**
  String get infos;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Sélectionner'**
  String get selectionner;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'ce contact'**
  String get ceContact;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le message sera supprimé pour tous les membres du groupe.'**
  String get messageSeraSupprimePourTous;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le message sera supprimé pour vous deux.'**
  String get messageSeraSupprimePourVous;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussion'**
  String get discussion;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Fermer la recherche'**
  String get fermerRecherche;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans la discussion'**
  String get rechercherDansDiscussion;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Plus d’options'**
  String get plusOptions;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans les messages'**
  String get rechercherDansMessages;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'quelqu’un écrit…'**
  String get quelquEcrit;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'en train d’écrire…'**
  String get trainEcrire;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre contact'**
  String get votreContact;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne faites plus partie de ce groupe.'**
  String get vousNeFaitesPlusPartie;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce groupe a été fermé par Privio. Plus personne ne peut y écrire.'**
  String get ceGroupeEteFermePar3;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Modifier le message'**
  String get modifierMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Répondre à'**
  String get repondre2;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Message vocal ({durationMs})'**
  String messageVocalDurationms(Object durationMs);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce message'**
  String get ceMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Message vocal'**
  String get messageVocal;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'📷 Photo'**
  String get photo2;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aujourd’hui'**
  String get aujourdHui;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Hier'**
  String get hier;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun message ne correspond'**
  String get aucunMessageNeCorrespond;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'La recherche porte sur les messages encore présents sur ce téléphone.'**
  String get recherchePorteSurMessagesEncore;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun message'**
  String get aucunMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos messages s’effaceront {ttlSeconds} après leur envoi.'**
  String vosMessagesEffacerontTtlsecondsApres(Object ttlSeconds);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez'**
  String get vousAvez;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{who} réglé la durée des messages sur {ttl}.'**
  String whoRegleDureeMessagesSur(Object who, Object ttl);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Voir {name}'**
  String voirName(Object name);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Non envoyé · Toucher pour réessayer'**
  String get nonEnvoyeToucherPourReessayer;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'En attente de réseau'**
  String get attenteReseau;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/report_sheet.dart, ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoi…'**
  String get envoi;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Messages effacés après {ttlSeconds}'**
  String messagesEffacesApresTtlseconds(Object ttlSeconds);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Durée des messages : {label}'**
  String dureeMessagesLabel(Object label);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'épinglé'**
  String get epingle;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'expire dans {remaining}'**
  String expireDansRemaining(Object remaining);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Réaction {key}, voir qui a réagi'**
  String reactionKeyVoirQuiReagi(Object key);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'voir qui a réagi'**
  String get voirQuiReagi;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer ma réaction'**
  String get retirerMaReaction;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Réagir {key}'**
  String reagirKey(Object key);

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyé'**
  String get envoye;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Reçu'**
  String get recu;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/message_extras.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Lu'**
  String get lu;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Écrire un message'**
  String get ecrireMessage;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Clavier'**
  String get clavier;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Émojis et autocollants'**
  String get emojisAutocollants;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Plus de photos aujourd’hui'**
  String get plusPhotosAujourdHui;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer une photo'**
  String get envoyerPhoto;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{title} propose de supprimer la discussion pour vous deux. Tout disparaîtra, sans trace.'**
  String titleProposeSupprimerDiscussionPour(Object title);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{title} propose de vider toute la discussion pour vous deux. Tout disparaîtra, sans trace.'**
  String titleProposeViderTouteDiscussion(Object title);

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler la demande'**
  String get annulerDemande;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/connection_requests_screen.dart, ui/features/groups/group_screens.dart, ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get refuser;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Accepter et supprimer'**
  String get accepterSupprimer;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Accepter et vider'**
  String get accepterVider;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{name} est débloqué.'**
  String nameEstDebloque(Object name);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez bloqué {name}.'**
  String vousAvezBloqueName(Object name);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez plus vous écrire.'**
  String get vousNePouvezPlusVous;

  /// Écran : ui/features/conversations/chat_screen.dart, ui/features/conversations/contact_screen.dart, ui/features/settings/blocked_users_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Débloquer'**
  String get debloquer;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{count} messages non lus'**
  String countMessagesNonLus(Object count);

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'1 message non lu'**
  String get n1MessageNonLu;

  /// Écran : ui/features/conversations/chat_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Descendre aux derniers messages'**
  String get descendreDerniersMessages;

  /// Écran : ui/features/conversations/connection_requests_screen.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demandes de connexion'**
  String get demandesConnexion;

  /// Écran : ui/features/conversations/connection_requests_screen.dart, ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune demande'**
  String get aucuneDemande;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour écrire à quelqu’un pour la première fois, envoyez-lui une demande depuis « Nouvelle discussion ».'**
  String get pourEcrireQuelquPourPremiere;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Reçues'**
  String get recues;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyées'**
  String get envoyees;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'expire bientôt'**
  String get expireBientot;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'expire dans {inMinutes} min'**
  String expireDansInminutesMin(Object inMinutes);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'expire dans {inHours} h'**
  String expireDansInhoursH(Object inHours);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Bloquer {displayName} ?'**
  String bloquerDisplayname(Object displayName);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'La demande est refusée et cette personne ne pourra plus vous en envoyer, ni vous écrire. Vous pourrez la débloquer dans Paramètres.'**
  String get demandeEstRefuseeCettePersonne;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous êtes connecté avec {displayName}.'**
  String vousEtesConnecteAvecDisplayname(Object displayName);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{displayName} est bloqué.'**
  String displaynameEstBloque(Object displayName);

  /// Écran : ui/features/conversations/connection_requests_screen.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Accepter'**
  String get accepter;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'A refusé votre demande · nouvel essai à {retryAt}'**
  String refuseVotreDemandeNouvelEssai(Object retryAt);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'A refusé votre demande'**
  String get refuseVotreDemande;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande expirée, sans réponse'**
  String get demandeExpireeSansReponse;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'En attente · {expiresAt}'**
  String attenteExpiresat(Object expiresAt);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'1 demande de connexion'**
  String get n1DemandeConnexion;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{incoming} demandes de connexion'**
  String incomingDemandesConnexion(Object incoming);

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'1 demande refusée'**
  String get n1DemandeRefusee;

  /// Écran : ui/features/conversations/connection_requests_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{refused} demandes refusées'**
  String refusedDemandesRefusees(Object refused);

  /// Écran : ui/features/conversations/contact_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Bloquer {name} ?'**
  String bloquerName(Object name);

  /// Écran : ui/features/conversations/contact_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'{name} est bloqué.'**
  String nameEstBloque(Object name);

  /// Écran : ui/features/conversations/contact_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/settings/my_profile_screen.dart, ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get propos;

  /// Écran : ui/features/conversations/contact_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Confidentialité de cette discussion'**
  String get confidentialiteCetteDiscussion;

  /// Écran : ui/features/conversations/contact_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ces choix ne valent que pour cette discussion ; ailleurs, vos réglages de Confidentialité s’appliquent.'**
  String get cesChoixNeValentQue;

  /// Écran : ui/features/conversations/contact_screen.dart, ui/features/conversations/conversation_details.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la discussion'**
  String get supprimerDiscussion;

  /// Écran : ui/features/conversations/contact_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Signaler ce contact'**
  String get signalerCeContact;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer la photo'**
  String get changerPhoto;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo indisponible.'**
  String get photoIndisponible;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Voir la photo en grand'**
  String get voirPhotoGrand;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune photo ni vocal pour l’instant'**
  String get aucunePhotoNiVocalPour;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun média'**
  String get aucunMedia;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Les photos et vocaux s’effacent avec leurs messages.'**
  String get photosVocauxEffacentAvecLeurs;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Ils s’effacent avec leurs messages et ne peuvent pas être enregistrés.'**
  String get ilsEffacentAvecLeursMessages;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Photos'**
  String get photos;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Vocaux'**
  String get vocaux;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'8 heures'**
  String get n8Heures;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'1 semaine'**
  String get n1Semaine;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Activées'**
  String get activees;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivées'**
  String get desactivees;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivées jusqu’au {day}/{month} à {hour}:{minute}'**
  String desactiveesJusquDayMonthHour(Object day, Object month, Object hour, Object minute);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour tous les membres'**
  String get pourTousMembres;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour nous deux'**
  String get pourNousDeux;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Tous les messages, vocaux et photos disparaissent pour tout le monde, sans laisser de trace.'**
  String get tousMessagesVocauxPhotosDisparaissent;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'{title} doit accepter. Ensuite tout disparaît des deux côtés, sans laisser de trace.'**
  String titleDoitAccepterEnsuiteTout(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Seulement chez moi'**
  String get seulementChezMoi;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre copie est vidée ; les autres membres gardent leurs messages.'**
  String get votreCopieEstVideeAutres;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre copie est vidée ; {title} garde ses messages.'**
  String votreCopieEstVideeTitle(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Vider le groupe pour tous ?'**
  String get viderGroupePourTous;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Demander à {title} de tout vider ?'**
  String demanderTitleToutVider(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Vider la discussion chez vous ?'**
  String get viderDiscussionChezVous;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Si {title} accepte, tous les messages disparaissent définitivement des deux côtés. La demande expire au bout de 24 heures.'**
  String siTitleAccepteTousMessages(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Les messages actuels disparaissent définitivement de votre écran. Cette action ne peut pas être annulée.'**
  String get messagesActuelsDisparaissentDefinitivementVotre;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer la demande'**
  String get envoyerDemande;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Vider'**
  String get vider;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée à {title}.'**
  String demandeEnvoyeeTitle(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Accusés de lecture'**
  String get accusesLecture;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'« En train d’écrire »'**
  String get trainEcrire2;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'En ligne et « vu à »'**
  String get ligneVu;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo de profil'**
  String get photoProfil;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'activés'**
  String get actives;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'désactivés'**
  String get desactives;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'activé'**
  String get active;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'désactivé'**
  String get desactive;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Activés'**
  String get actives2;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivés'**
  String get desactives2;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Activé'**
  String get active2;

  /// Écran : ui/features/conversations/conversation_details.dart, ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivé'**
  String get desactive2;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Montré à {title}'**
  String montreTitle(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Caché à {title}'**
  String cacheTitle(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Comme dans mes réglages'**
  String get commeDansMesReglages;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Comme dans mes réglages ({g})'**
  String commeDansMesReglagesG(Object g);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'{title} doit accepter. Ensuite la discussion disparaît des deux côtés, sans laisser de trace.'**
  String titleDoitAccepterEnsuiteDiscussion(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Elle disparaît de votre liste et votre copie est effacée. Si {title} vous écrit à nouveau, elle revient, vide.'**
  String elleDisparaitVotreListeVotre(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer « {title} » pour tous ?'**
  String supprimerTitlePourTous(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Demander à {title} de supprimer la discussion ?'**
  String demanderTitleSupprimerDiscussion(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la discussion chez vous ?'**
  String get supprimerDiscussionChezVous;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Tous les messages, photos et vocaux sont effacés et tous les membres sont retirés. Chacun verra « Le groupe a été supprimé ». Cette action ne peut pas être annulée.'**
  String get tousMessagesPhotosVocauxSont;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Si {title} accepte, tous les messages disparaissent définitivement et la discussion est retirée des deux côtés. La demande expire au bout de 24 heures.'**
  String siTitleAccepteTousMessages2(Object title);

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Les messages disparaissent définitivement de votre téléphone. Cette action ne peut pas être annulée.'**
  String get messagesDisparaissentDefinitivementVotreTelephone;

  /// Écran : ui/features/conversations/conversation_details.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe supprimé.'**
  String get groupeSupprime;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Merci !'**
  String get merci;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Bravo !'**
  String get bravo;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Courage !'**
  String get courage;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Désolé'**
  String get desole;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonne arrivée'**
  String get bonneArrivee;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'On dit quoi ?'**
  String get onDitQuoi;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Ça va aller'**
  String get caVaAller;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonne fête !'**
  String get bonneFete;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Je t’appelle'**
  String get jeTAppelle;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'À tout’ !'**
  String get tout;

  /// Écran : ui/features/conversations/expression_panel.dart, ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonjour !'**
  String get bonjour;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonne nuit'**
  String get bonneNuit;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Mdr'**
  String get mdr;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Je t’aime'**
  String get jeTAime;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'D’accord'**
  String get accord;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Non !'**
  String get non;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Oups'**
  String get oups;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Waouh !'**
  String get waouh;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'J’arrive !'**
  String get jArrive;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Attends…'**
  String get attends;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Félicitations !'**
  String get felicitations;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Bon appétit !'**
  String get bonAppetit;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Fatigué'**
  String get fatigue;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Fâché !'**
  String get fache;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Autocollant indisponible\nMettez Privio à jour'**
  String get autocollantIndisponibleMettezPrivioJour;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Autocollant « {label} »'**
  String autocollantLabel(Object label);

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos émojis récents s’afficheront ici'**
  String get vosEmojisRecentsAfficherontIci;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un émoji'**
  String get rechercherEmoji;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Émojis'**
  String get emojis;

  /// Écran : ui/features/conversations/expression_panel.dart
  ///
  /// In fr, this message translates to:
  /// **'Autocollants'**
  String get autocollants;

  /// Écran : ui/features/conversations/gif_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un GIF'**
  String get rechercherGif;

  /// Écran : ui/features/conversations/gif_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'GIF fournis par KLIPY'**
  String get gifFournisParKlipy;

  /// Écran : ui/features/conversations/gif_picker.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun GIF trouvé.'**
  String get aucunGifTrouve;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'🎤 Message vocal'**
  String get messageVocal2;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Message épinglé {i}/{pinsCount}'**
  String messageEpingleIPinscount(Object i, Object pinsCount);

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Pas encore distribué'**
  String get pasEncoreDistribue;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Distribué'**
  String get distribue;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Distribué à {deliveredAt}'**
  String distribueDeliveredat(Object deliveredAt);

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Lecture non partagée'**
  String get lectureNonPartagee;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Pas encore lu'**
  String get pasEncoreLu;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Lu à {readAt}'**
  String luReadat(Object readAt);

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Infos du message'**
  String get infosMessage;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun destinataire pour l’instant.'**
  String get aucunDestinatairePourInstant;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun pour l’instant'**
  String get aucunPourInstant;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun message favori'**
  String get aucunMessageFavori;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Appui long sur un message, puis « Ajouter aux favoris ». Un favori s’efface en même temps que le message.'**
  String get appuiLongSurMessagePuis;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Mentions seulement'**
  String get mentionsSeulement;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Notifié seulement quand quelqu’un vous @mentionne'**
  String get notifieSeulementQuandQuelquVous;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Toucher pour retirer'**
  String get toucherPourRetirer;

  /// Écran : ui/features/conversations/message_extras.dart
  ///
  /// In fr, this message translates to:
  /// **'Toutes {reactionsCount}'**
  String toutesReactionscount(Object reactionsCount);

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun compte trouvé. Vérifiez l’orthographe, ou invitez cette personne sur Privio.'**
  String get aucunCompteTrouveVerifiezOrthographe;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun compte trouvé pour @{handle}.'**
  String aucunCompteTrouvePourHandle(Object handle);

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée à {displayName}.'**
  String demandeEnvoyeeDisplayname(Object displayName);

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Écrire'**
  String get ecrire;

  /// Écran : ui/features/conversations/new_conversation_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer une demande'**
  String get envoyerDemande2;

  /// Écran : ui/features/conversations/new_conversation_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Accepter sa demande'**
  String get accepterSaDemande;

  /// Écran : ui/features/conversations/new_conversation_screen.dart, ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée, en attente de réponse.'**
  String get demandeEnvoyeeAttenteReponse;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{displayName} a refusé votre demande. Nouvel essai possible{clock}.'**
  String displaynameRefuseVotreDemandeNouvel(Object displayName, Object clock);

  /// Écran : ui/features/conversations/new_conversation_screen.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle discussion'**
  String get nouvelleDiscussion;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Scanner un QR code'**
  String get scannerQrCode;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Identifiant ou numéro'**
  String get identifiantOuNumero;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'@identifiant ou 70 00 00 00'**
  String get identifiantOu700000;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Identifiant exact (ex. @awa_s) ou numéro'**
  String get identifiantExactExAwaOu;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Inviter cette personne sur Privio'**
  String get inviterCettePersonneSurPrivio;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mes demandes de connexion'**
  String get mesDemandesConnexion;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande à {displayName}'**
  String demandeDisplayname(Object displayName);

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous pourrez vous écrire quand {displayName} aura accepté. Sans réponse, la demande expire après 24 h.'**
  String vousPourrezVousEcrireQuand(Object displayName);

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Petit mot (facultatif)'**
  String get petitMotFacultatif;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonjour, c’est…'**
  String get bonjourCEst;

  /// Écran : ui/features/conversations/new_conversation_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Effacé 5 min après l’acceptation.'**
  String get efface5MinApresAcceptation;

  /// Écran : ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée à {name}.'**
  String demandeEnvoyeeName(Object name);

  /// Écran : ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer un message'**
  String get envoyerMessage;

  /// Écran : ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'{name} a refusé votre demande. Nouvel essai possible{clock}.'**
  String nameRefuseVotreDemandeNouvel(Object name, Object clock);

  /// Écran : ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Gérer ce membre'**
  String get gererCeMembre;

  /// Écran : ui/features/conversations/person_card.dart
  ///
  /// In fr, this message translates to:
  /// **'Administrateur, retrait du groupe'**
  String get administrateurRetraitGroupe;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'La retouche n’a pas pu être appliquée. Réessayez.'**
  String get retoucheNPasPuEtre;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler la retouche'**
  String get annulerRetouche;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Retoucher'**
  String get retoucher;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler le dernier trait'**
  String get annulerDernierTrait;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Terminé'**
  String get termine;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo à retoucher'**
  String get photoRetoucher;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Recadrer'**
  String get recadrer;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Pivoter'**
  String get pivoter;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Dessiner'**
  String get dessiner;

  /// Écran : ui/features/conversations/photo_editor.dart
  ///
  /// In fr, this message translates to:
  /// **'Dessinez sur la photo avec le doigt.'**
  String get dessinezSurPhotoAvecDoigt;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous avez envoyé vos {limit} photos du jour. Prochaines photos demain, dès minuit.'**
  String vousAvezEnvoyeVosLimit(Object limit);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Il vous reste 1 photo aujourd’hui ({limit} par jour).'**
  String ilVousReste1Photo(Object limit);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Il vous reste {n} photos aujourd’hui ({limit} par jour).'**
  String ilVousResteNPhotos(Object n, Object limit);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo · toucher pour télécharger'**
  String get photoToucherPourTelecharger;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Hors connexion · toucher pour réessayer'**
  String get horsConnexionToucherPourReessayer;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo indisponible'**
  String get photoIndisponible2;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo non téléchargée'**
  String get photoNonTelechargee;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'télécharger'**
  String get telecharger;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Photos limitées chaque jour. Elles s’effacent comme les messages.'**
  String get photosLimiteesChaqueJourElles;

  /// Écran : ui/features/conversations/photo_widgets.dart, ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Prendre une photo'**
  String get prendrePhoto;

  /// Écran : ui/features/conversations/photo_widgets.dart, ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisir dans la galerie'**
  String get choisirDansGalerie;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'C’est votre dernière photo du jour ({limit} par jour).'**
  String cEstVotreDernierePhoto(Object limit);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce sont vos dernières photos du jour ({limit} par jour).'**
  String ceSontVosDernieresPhotos(Object limit);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Retoucher cette photo'**
  String get retoucherCettePhoto;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer cette photo'**
  String get retirerCettePhoto;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo {i} à envoyer'**
  String photoIEnvoyer(Object i);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Vue unique : sans légende'**
  String get vueUniqueSansLegende;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Légende de cette photo'**
  String get legendeCettePhoto;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une légende'**
  String get ajouterLegende;

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer les {photosCount} photos'**
  String envoyerPhotoscountPhotos(Object photosCount);

  /// Écran : ui/features/conversations/photo_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer la photo'**
  String get envoyerPhoto2;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Harcèlement ou insultes'**
  String get harcelementOuInsultes;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Menaces ou violence'**
  String get menacesOuViolence;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Spam ou arnaque'**
  String get spamOuArnaque;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Contenu choquant'**
  String get contenuChoquant;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Autre raison'**
  String get autreRaison;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Merci. Votre signalement est transmis et {reportedName} est bloqué.'**
  String merciVotreSignalementEstTransmis(Object reportedName);

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Merci. Votre signalement est transmis à l’équipe de modération.'**
  String get merciVotreSignalementEstTransmis2;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Signaler ce message'**
  String get signalerCeMessage;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Signaler {reportedName}'**
  String signalerReportedname(Object reportedName);

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre signalement est confidentiel : la personne n’est pas prévenue.'**
  String get votreSignalementEstConfidentielPersonne;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Précisions (facultatif)'**
  String get precisionsFacultatif;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Joindre une copie de ce message'**
  String get joindreCopieCeMessage;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Lue uniquement par l’équipe de modération, effacée après 90 jours.'**
  String get lueUniquementParEquipeModeration;

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Bloquer aussi {reportedName}'**
  String bloquerAussiReportedname(Object reportedName);

  /// Écran : ui/features/conversations/report_sheet.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le signalement'**
  String get envoyerSignalement;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Vocal'**
  String get vocal;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Écouté'**
  String get ecoute;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouverte'**
  String get ouverte;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Toucher pour ouvrir'**
  String get toucherPourOuvrir;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'{what} · vue unique'**
  String whatVueUnique(Object what);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'{what} en vue unique, {status}'**
  String whatVueUniqueStatus(Object what, Object status);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Pas encore écouté'**
  String get pasEncoreEcoute;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Pas encore ouverte'**
  String get pasEncoreOuverte;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Écouté par {n}'**
  String ecouteParN(Object n);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouverte par {n}'**
  String ouverteParN(Object n);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Vue unique · disparaît à la fermeture'**
  String get vueUniqueDisparaitFermeture;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Vocal en vue unique'**
  String get vocalVueUnique;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Il disparaît dès que vous fermez ce panneau.'**
  String get ilDisparaitQueVousFermez;

  /// Écran : ui/features/conversations/rich_messages.dart, ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Écouter'**
  String get ecouter;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Aperçu du lien {site}'**
  String apercuLienSite(Object site);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir ce lien ?'**
  String get ouvrirCeLien;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Le site {host} s’ouvrira dans votre navigateur.'**
  String siteHostOuvriraDansVotre(Object host);

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get ouvrir;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Vue unique'**
  String get vueUnique;

  /// Écran : ui/features/conversations/rich_messages.dart
  ///
  /// In fr, this message translates to:
  /// **'Vue unique activée'**
  String get vueUniqueActivee;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Message vocal, {total}'**
  String messageVocalTotal(Object total);

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Écouter le message vocal'**
  String get ecouterMessageVocal;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Vitesse de lecture {speed}'**
  String vitesseLectureSpeed(Object speed);

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Message vocal · {durationMs}'**
  String messageVocalDurationms2(Object durationMs);

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Annuler l’enregistrement'**
  String get annulerEnregistrement;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'En pause'**
  String get pause2;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Arrêt dans {inSeconds} s'**
  String arretDansInseconds(Object inSeconds);

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'{inSeconds} s max.'**
  String insecondsMax(Object inSeconds);

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Glisser pour annuler'**
  String get glisserPourAnnuler;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Reprendre l’enregistrement'**
  String get reprendreEnregistrement;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Mettre en pause'**
  String get mettrePause;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer l’enregistrement'**
  String get supprimerEnregistrement;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Écouter avant d’envoyer'**
  String get ecouterAvantEnvoyer;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le message vocal'**
  String get envoyerMessageVocal;

  /// Écran : ui/features/conversations/voice_widgets.dart
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer un message vocal'**
  String get enregistrerMessageVocal;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Code copié.'**
  String get codeCopie;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer le code ?'**
  String get changerCode;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'L’ancien code et l’ancien QR code ne fonctionneront plus. Les demandes déjà envoyées restent à traiter.'**
  String get ancienCodeAncienQrCode;

  /// Écran : ui/features/groups/group_code_screen.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer'**
  String get changer;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Nouveau code créé.'**
  String get nouveauCodeCree;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Inviter avec un code'**
  String get inviterAvecCode;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'QR code du groupe'**
  String get qrCodeGroupe;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Une personne qui entre ce code (Groupes → Rejoindre un groupe) ou scanne ce QR code vous envoie une demande ; un administrateur l’accepte ou la refuse.'**
  String get personneQuiEntreCeCode;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Une personne qui entre ce code (Groupes → Rejoindre un groupe) ou scanne ce QR code rejoint le groupe directement.'**
  String get personneQuiEntreCeCode2;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Donnez-le seulement aux personnes que vous voulez inviter. Les captures d’écran sont bloquées : montrez le QR code ou recopiez le code dans un message.'**
  String get donnezSeulementPersonnesQueVous;

  /// Écran : ui/features/groups/group_code_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Copier le code'**
  String get copierCode;

  /// Écran : ui/features/groups/group_code_screen.dart, ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer le code'**
  String get changerCode2;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun compte ne correspond.'**
  String get aucunCompteNeCorrespond;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'{displayName} fait déjà partie du groupe.'**
  String displaynameFaitDejaPartieGroupe(Object displayName);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Identifiant Privio (ex. awa_s) ou numéro'**
  String get identifiantPrivioExAwaOu;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get ajouter;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos contacts'**
  String get vosContacts;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Chaque personne reçoit une invitation et choisit de rejoindre le groupe ou non.'**
  String get chaquePersonneRecoitInvitationChoisit;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe créé'**
  String get groupeCree;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe créé · 1 invitation envoyée'**
  String get groupeCree1InvitationEnvoyee;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe créé · {invited} invitations envoyées'**
  String groupeCreeInvitedInvitationsEnvoyees(Object invited);

  /// Écran : ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer la photo'**
  String get retirerPhoto;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupe créé. La photo n’a pas pu être ajoutée : réessayez depuis la fiche.'**
  String get groupeCreePhotoNPas;

  /// Écran : ui/features/groups/group_screens.dart, ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Nouveau groupe'**
  String get nouveauGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une photo du groupe'**
  String get ajouterPhotoGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer la photo du groupe'**
  String get changerPhotoGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Nom du groupe'**
  String get nomGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Description (facultative)'**
  String get descriptionFacultative;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Création du groupe…'**
  String get creationGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Créer le groupe'**
  String get creerGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune invitation envoyée (déjà membres ou invités).'**
  String get aucuneInvitationEnvoyeeDejaMembres;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Modifier le groupe'**
  String get modifierGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Description'**
  String get description;

  /// Écran : ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get enregistrer;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Nommer administrateur'**
  String get nommerAdministrateur;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer le rôle d’administrateur'**
  String get retirerRoleAdministrateur;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Nommer propriétaire'**
  String get nommerProprietaire;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer du groupe'**
  String get retirerGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Retirer {displayName} ?'**
  String retirerDisplayname(Object displayName);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Confier le groupe à {displayName} ?'**
  String confierGroupeDisplayname(Object displayName);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'{displayName} ne verra plus les messages du groupe.'**
  String displaynameNeVerraPlusMessages(Object displayName);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous resterez administrateur.'**
  String get vousResterezAdministrateur;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get confirmer;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'{displayName} a rejoint le groupe.'**
  String displaynameRejointGroupe(Object displayName);

  /// Écran : ui/features/groups/group_screens.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une photo'**
  String get ajouterPhoto;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Modifier le nom ou la description'**
  String get modifierNomOuDescription;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Notifications coupées'**
  String get notificationsCoupees;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Notifications actives'**
  String get notificationsActives;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Confidentialité dans ce groupe'**
  String get confidentialiteDansCeGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Réglages du groupe'**
  String get reglagesGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs écrivent'**
  String get seulsAdministrateursEcrivent;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs modifient le groupe'**
  String get seulsAdministrateursModifientGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Nom, description, photo et durée des messages'**
  String get nomDescriptionPhotoDureeMessages;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Approuver les nouveaux membres'**
  String get approuverNouveauxMembres;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Avec le code, on envoie une demande à accepter'**
  String get avecCodeOnEnvoieDemande;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Avec le code, on entre directement'**
  String get avecCodeOnEntreDirectement;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Demandes pour rejoindre ({requestsCount})'**
  String demandesPourRejoindreRequestscount(Object requestsCount);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'déjà retiré du groupe'**
  String get dejaRetireGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'MEMBRES'**
  String get membres;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Inviter avec un code ou un QR code'**
  String get inviterAvecCodeOuQr;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour les personnes qui ne sont pas dans vos contacts'**
  String get pourPersonnesQuiNeSont;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Signaler le groupe'**
  String get signalerGroupe;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'le groupe « {title} »'**
  String groupeTitle(Object title);

  /// Écran : ui/features/groups/group_screens.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Quitter et supprimer'**
  String get quitterSupprimer;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Le groupe disparaît de votre liste'**
  String get groupeDisparaitVotreListe;

  /// Écran : ui/features/groups/group_screens.dart, ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le groupe pour tous'**
  String get supprimerGroupePourTous;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Quitter « {title} » ?'**
  String quitterTitle(Object title);

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Le groupe sera confié à l’administrateur (ou au membre) le plus ancien. Vous ne verrez plus ses messages.'**
  String get groupeSeraConfieAdministrateurOu;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous ne verrez plus les messages de ce groupe.'**
  String get vousNeVerrezPlusMessages;

  /// Écran : ui/features/groups/group_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get quitter;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Code incomplet : « PRV- » suivi de 6 lettres ou chiffres.'**
  String get codeIncompletPrvSuivi6;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée. Vous serez prévenu quand elle sera acceptée.'**
  String get demandeEnvoyeeVousSerezPrevenu;

  /// Écran : ui/features/groups/join_group_screen.dart, ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre un groupe'**
  String get rejoindreGroupe;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Entrez le code reçu d’un administrateur du groupe, ou scannez le QR code qu’il vous montre sur son téléphone.'**
  String get entrezCodeRecuAdministrateurGroupe;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Code d’invitation'**
  String get codeInvitation;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Scanner'**
  String get scanner;

  /// Écran : ui/features/groups/join_group_screen.dart, ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get continuer;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce code ne correspond à aucun groupe. Vérifiez-le auprès de la personne qui vous l’a donné : il a peut-être été changé.'**
  String get ceCodeNeCorrespondAucun;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous faites déjà partie de ce groupe.'**
  String get vousFaitesDejaPartieCe;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le groupe'**
  String get ouvrirGroupe;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre demande est envoyée. Un administrateur du groupe doit l’accepter ; vous serez prévenu.'**
  String get votreDemandeEstEnvoyeeAdministrateur;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre demande a été refusée. Vous pourrez en faire une nouvelle dans 24 h.'**
  String get votreDemandeEteRefuseeVous2;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce groupe est complet.'**
  String get ceGroupeEstComplet;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous pouvez rejoindre ce groupe directement.'**
  String get vousPouvezRejoindreCeGroupe;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre le groupe'**
  String get rejoindreGroupe2;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Un administrateur du groupe doit accepter votre demande.'**
  String get administrateurGroupeDoitAccepterVotre;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Demander à rejoindre'**
  String get demanderRejoindre;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Placez le QR code de la personne dans le cadre.'**
  String get placezQrCodePersonneDans;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce QR code n’est pas un identifiant Privio.'**
  String get ceQrCodeNEst;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Placez le QR code du groupe dans le cadre.'**
  String get placezQrCodeGroupeDans;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce QR code n’est pas un code de groupe Privio.'**
  String get ceQrCodeNEst2;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Scanner le QR code'**
  String get scannerQrCode2;

  /// Écran : ui/features/groups/join_group_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Caméra indisponible. Autorisez l’appareil photo pour Privio dans les réglages du téléphone, ou revenez en arrière et tapez le code.'**
  String get cameraIndisponibleAutorisezAppareilPhoto;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupes archivés'**
  String get groupesArchives;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Archivées'**
  String get archivees;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe archivé'**
  String get aucunGroupeArchive;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune discussion archivée'**
  String get aucuneDiscussionArchivee;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Glissez un groupe vers la gauche pour l’archiver.'**
  String get glissezGroupeVersGauchePour;

  /// Écran : ui/features/home/archived_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Glissez une discussion vers la gauche pour l’archiver.'**
  String get glissezDiscussionVersGauchePour;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Toutes'**
  String get toutes;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Non lues'**
  String get nonLues;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Épinglées'**
  String get epinglees;

  /// Écran : ui/features/home/discussions_tab.dart, ui/features/home/groups_tab.dart, ui/features/home/home_shell.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupes'**
  String get groupes;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Archivées ({archivedCount})'**
  String archiveesArchivedcount(Object archivedCount);

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune discussion pour l’instant'**
  String get aucuneDiscussionPourInstant;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Touchez le crayon pour écrire à quelqu’un. Vos messages s’effacent seuls au bout de 72 h.'**
  String get touchezCrayonPourEcrireQuelqu;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get aucunResultat;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucune discussion ne correspond à ce filtre.'**
  String get aucuneDiscussionNeCorrespondCe;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Hors connexion. Vos messages partiront dès le retour du réseau.'**
  String get horsConnexionVosMessagesPartiront;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussion archivée.'**
  String get discussionArchivee;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussion désarchivée.'**
  String get discussionDesarchivee;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Désarchiver'**
  String get desarchiver;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Archiver'**
  String get archiver;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Épingler en haut de la liste'**
  String get epinglerHautListe;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Un nouveau message la fera réapparaître dans la liste.'**
  String get nouveauMessageFeraReapparaitreDans;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous : '**
  String get vous2;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Contact bloqué'**
  String get contactBloque;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Propose de vider la discussion'**
  String get proposeViderDiscussion;

  /// Écran : ui/features/home/discussions_tab.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Durée des messages : {ttlSeconds}'**
  String dureeMessagesTtlseconds(Object ttlSeconds);

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'{who}🎤 Message vocal'**
  String whoMessageVocal(Object who);

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Fiche du groupe'**
  String get ficheGroupe;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Fiche de {title}'**
  String ficheTitle(Object title);

  /// Écran : ui/features/home/discussions_tab.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'s\'efface dans {now}'**
  String effaceDansNow(Object now);

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'En sourdine'**
  String get sourdine2;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Épinglée'**
  String get epinglee;

  /// Écran : ui/features/home/discussions_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Effacer la recherche'**
  String get effacerRecherche;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get tous;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Non lus'**
  String get nonLus;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Épinglés'**
  String get epingles;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Archivés ({archivedCount})'**
  String archivesArchivedcount(Object archivedCount);

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe trouvé'**
  String get aucunGroupeTrouve;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe ne correspond à « {text} ».'**
  String aucunGroupeNeCorrespondText(Object text);

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe dans ce filtre.'**
  String get aucunGroupeDansCeFiltre;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe pour l’instant'**
  String get aucunGroupePourInstant;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Créez un groupe et invitez vos contacts. Chacun choisit de le rejoindre ; les messages s’effacent comme dans vos discussions. Un code reçu ? Touchez l’icône en haut pour rejoindre un groupe.'**
  String get creezGroupeInvitezVosContacts;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Le groupe « {title} » a été supprimé'**
  String groupeTitleEteSupprime(Object title);

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Par un administrateur du groupe'**
  String get parAdministrateurGroupe;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Invitations'**
  String get invitations;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Demandes envoyées'**
  String get demandesEnvoyees;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'En attente d’un administrateur'**
  String get attenteAdministrateur;

  /// Écran : ui/features/home/groups_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre'**
  String get rejoindre;

  /// Écran : ui/features/home/home_shell.dart
  ///
  /// In fr, this message translates to:
  /// **'Appuyez encore sur Retour pour quitter'**
  String get appuyezEncoreSurRetourPour;

  /// Écran : ui/features/home/home_shell.dart
  ///
  /// In fr, this message translates to:
  /// **'Discussions'**
  String get discussions;

  /// Écran : ui/features/home/home_shell.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get parametres;

  /// Écran : ui/features/home/home_shell.dart
  ///
  /// In fr, this message translates to:
  /// **'{label}, {badge} en attente'**
  String labelBadgeAttente(Object label, Object badge);

  /// Écran : ui/features/lock/app_lock_screens.dart, ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Effacer'**
  String get effacer;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Empreinte non reconnue. Saisissez votre code.'**
  String get empreinteNonReconnueSaisissezVotre;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code incorrect.'**
  String get codeIncorrect;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre code Privio'**
  String get saisissezVotreCodePrivio;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Trop d’essais. Réessayez dans {remaining}.'**
  String tropEssaisReessayezDansRemaining(Object remaining);

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Utiliser l’empreinte'**
  String get utiliserEmpreinte;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code oublié ?'**
  String get codeOublie;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Le contenu de Privio reste masqué tant que l’application est verrouillée.'**
  String get contenuPrivioResteMasqueTant;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code oublié'**
  String get codeOublie2;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour des raisons de sécurité, le code ne peut pas être retrouvé. Vous pouvez vous déconnecter : les messages gardés sur ce téléphone seront effacés, puis vous vous reconnecterez avec votre numéro et le code reçu par SMS. Vos discussions encore actives réapparaîtront.'**
  String get pourRaisonsSecuriteCodeNe;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter et effacer ce téléphone'**
  String get seDeconnecterEffacerCeTelephone;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Immédiatement'**
  String get immediatement;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Après 1 minute'**
  String get apres1Minute;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Après 5 minutes'**
  String get apres5Minutes;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Après 30 minutes'**
  String get apres30Minutes;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Après {seconds} min'**
  String apresSecondsMin(Object seconds);

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Verrouillage'**
  String get verrouillage;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Un code à {kPinLength} chiffres, propre à Privio, est demandé à l’ouverture de l’application. Il protège vos messages si quelqu’un utilise votre téléphone.'**
  String codeKpinlengthChiffresProprePrivio(Object kPinLength);

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Verrouiller Privio'**
  String get verrouillerPrivio;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Redemander le code'**
  String get redemanderCode;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller avec l’empreinte'**
  String get deverrouillerAvecEmpreinte;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Le code reste toujours accepté'**
  String get codeResteToujoursAccepte;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code oublié : il faudra vous déconnecter, ce qui efface les messages gardés sur ce téléphone. Les captures d’écran restent bloquées dans tous les cas.'**
  String get codeOublieIlFaudraVous;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code actuel'**
  String get codeActuel;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Nouveau code'**
  String get nouveauCode;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un code à {kPinLength} chiffres'**
  String choisissezCodeKpinlengthChiffres(Object kPinLength);

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Confirmez le code'**
  String get confirmezCode;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Trop d’essais. Réessayez dans {now}.'**
  String tropEssaisReessayezDansNow(Object now);

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code trop simple (suite ou chiffres identiques). Choisissez-en un autre.'**
  String get codeTropSimpleSuiteOu;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Les deux codes ne correspondent pas. Recommencez.'**
  String get deuxCodesNeCorrespondentPas;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Verrouillage activé.'**
  String get verrouillageActive;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code modifié.'**
  String get codeModifie;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Créer un code'**
  String get creerCode;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactiver le verrouillage'**
  String get desactiverVerrouillage;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Code Privio'**
  String get codePrivio;

  /// Écran : ui/features/lock/app_lock_screens.dart
  ///
  /// In fr, this message translates to:
  /// **'Évitez votre date de naissance ou une suite simple.'**
  String get evitezVotreDateNaissanceOu;

  /// Écran : ui/features/moderation/moderation_gate.dart, ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{day}/{month}/{year} à {hour}:{minute}'**
  String dayMonthYearHourMinute(Object day, Object month, Object year, Object hour, Object minute);

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Compte suspendu'**
  String get compteSuspendu;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Sans limite de durée'**
  String get sansLimiteDuree;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Jusqu’au {until}'**
  String jusquUntil(Object until);

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'L’équipe Privio a suspendu votre compte à la suite de signalements (motif : {toLowerCase}). Pendant la suspension, vous ne pouvez ni lire ni envoyer de messages. Vos messages déjà envoyés s’effacent normalement.'**
  String equipePrivioSuspenduVotreCompte(Object toLowerCase);

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Contester'**
  String get contester;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Expliquez pourquoi la sanction vous semble injustifiée. Une seule contestation est possible.'**
  String get expliquezPourquoiSanctionVousSemble;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre explication'**
  String get votreExplication;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyer ma contestation'**
  String get envoyerMaContestation;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Contestation examinée : la suspension est maintenue.'**
  String get contestationExamineeSuspensionEstMaintenue;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Contestation envoyée : l’équipe Privio l’examine.'**
  String get contestationEnvoyeeEquipePrivioExamine;

  /// Écran : ui/features/moderation/moderation_gate.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get seDeconnecter;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Message de l’équipe Privio'**
  String get messageEquipePrivio;

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre compte a fait l’objet de signalements (motif : {toLowerCase}). Merci de respecter les règles de Privio : pas de spam, de harcèlement, de menaces ni de contenu inapproprié. En cas de récidive, votre compte pourra être suspendu.'**
  String votreCompteFaitObjetSignalements(Object toLowerCase);

  /// Écran : ui/features/moderation/moderation_gate.dart
  ///
  /// In fr, this message translates to:
  /// **'J’ai compris'**
  String get jAiCompris;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Des messages qui disparaissent'**
  String get messagesQuiDisparaissent;

  /// Écran : ui/features/onboarding/onboarding_screen.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Chaque message est effacé automatiquement 72 heures après son envoi, qu\'il ait été lu ou non.'**
  String get chaqueMessageEstEffaceAutomatiquement;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Protégés pendant leur transport'**
  String get protegesPendantLeurTransport;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos messages circulent par une connexion chiffrée entre votre téléphone et les serveurs de Privio.'**
  String get vosMessagesCirculentParConnexion;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pas de transfert ni de copie'**
  String get pasTransfertNiCopie;

  /// Écran : ui/features/onboarding/onboarding_screen.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'Les messages ne peuvent être ni transférés, ni copiés, ni enregistrés dans la galerie. Les captures d\'écran sont bloquées sur Android ; une photo prise avec un autre appareil reste toutefois possible.'**
  String get messagesNePeuventEtreNi;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue sur Privio'**
  String get bienvenueSurPrivio;

  /// Écran : ui/features/onboarding/onboarding_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Une messagerie privée où les messages s’effacent tout seuls. Ce qu’il faut savoir :'**
  String get messageriePriveeOuMessagesEffacent;

  /// Écran : ui/features/onboarding/onboarding_screen.dart — typo-fr: ignore (texte validé, inchangé)
  ///
  /// In fr, this message translates to:
  /// **'J\'ai lu et compris ces engagements.'**
  String get jAiLuComprisCes;

  /// Écran : ui/features/permissions/permissions_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Autoriser les notifications'**
  String get autoriserNotifications;

  /// Écran : ui/features/permissions/permissions_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Restez informé'**
  String get restezInforme;

  /// Écran : ui/features/permissions/permissions_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Soyez prévenu d’un nouveau message. La notification n’affiche jamais son contenu.'**
  String get soyezPrevenuNouveauMessageNotification;

  /// Écran : ui/features/permissions/permissions_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le micro et l’appareil photo ne seront demandés que lorsque vous en aurez besoin.'**
  String get microAppareilPhotoNeSeront;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vérification de la disponibilité…'**
  String get verificationDisponibilite;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Cet identifiant est disponible.'**
  String get cetIdentifiantEstDisponible;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Il permet à vos proches de vous trouver sans connaître votre numéro.'**
  String get ilPermetVosProchesVous;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre profil'**
  String get votreProfil;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Création…'**
  String get creation;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Créer mon profil'**
  String get creerMonProfil;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro vérifié : {phone}'**
  String numeroVerifiePhone(Object phone);

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre nom'**
  String get votreNom;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Visible par les personnes avec qui vous échangez.'**
  String get visibleParPersonnesAvecQui;

  /// Écran : ui/features/profile_setup/profile_setup_screen.dart, ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Identifiant'**
  String get identifiant;

  /// Écran : ui/features/settings/appearance_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Apparence'**
  String get apparence;

  /// Écran : ui/features/settings/appearance_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Thème'**
  String get theme;

  /// Écran : ui/features/settings/appearance_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Taille du texte'**
  String get tailleTexte;

  /// Écran : ui/features/settings/appearance_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'La taille choisie s’ajoute à celle réglée dans votre téléphone.'**
  String get tailleChoisieAjouteCelleReglee;

  /// Écran : ui/features/settings/appearance_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Bonjour ! On se voit demain ?'**
  String get bonjourOnSeVoitDemain;

  /// Écran : ui/features/settings/appearance_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Oui, vers 10 h.'**
  String get ouiVers10H;

  /// Écran : ui/features/settings/blocked_users_screen.dart, ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Personnes bloquées'**
  String get personnesBloquees;

  /// Écran : ui/features/settings/blocked_users_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Personne n’est bloqué'**
  String get personneNEstBloque;

  /// Écran : ui/features/settings/blocked_users_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous pouvez bloquer quelqu’un depuis sa fiche contact.'**
  String get vousPouvezBloquerQuelquDepuis;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'C’est déjà votre numéro.'**
  String get cEstDejaVotreNumero;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro changé.'**
  String get numeroChange;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer de numéro'**
  String get changerNumero;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre compte, votre identifiant, vos discussions et vos groupes sont conservés. Vos contacts ne sont pas prévenus : votre numéro n’est jamais affiché dans Privio.'**
  String get votreCompteVotreIdentifiantVos;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro actuel : {currentPhone}'**
  String numeroActuelCurrentphone(Object currentPhone);

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Nouveau numéro'**
  String get nouveauNumero;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Sans indicatif : Burkina Faso (+226)'**
  String get sansIndicatifBurkinaFaso226;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Recevoir un code sur ce numéro'**
  String get recevoirCodeSurCeNumero;

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code à 6 chiffres envoyé par SMS au {newPhone}.'**
  String saisissezCode6ChiffresEnvoye2(Object newPhone);

  /// Écran : ui/features/settings/change_phone_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Changer le numéro saisi'**
  String get changerNumeroSaisi;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre profil, votre identifiant et votre numéro sont supprimés.'**
  String get votreProfilVotreIdentifiantVotre;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos messages envoyés sont supprimés, y compris chez les personnes qui les ont reçus.'**
  String get vosMessagesEnvoyesSontSupprimes;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos blocages et vos discussions disparaissent.'**
  String get vosBlocagesVosDiscussionsDisparaissent;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les messages enregistrés sur ce téléphone sont détruits.'**
  String get messagesEnregistresSurCeTelephone;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Un signalement vous concernant peut être conservé jusqu’à 90 jours pour la modération.'**
  String get signalementVousConcernantPeutEtre;

  /// Écran : ui/features/settings/delete_account_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer mon compte'**
  String get supprimerMonCompte;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette action est définitive.'**
  String get cetteActionEstDefinitive;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour confirmer, écrivez SUPPRIMER'**
  String get pourConfirmerEcrivezSupprimer;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Suppression…'**
  String get suppression;

  /// Écran : ui/features/settings/delete_account_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Supprimer définitivement mon compte'**
  String get supprimerDefinitivementMonCompte;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Quand mes messages sont-ils effacés ?'**
  String get quandMesMessagesSontIls;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Chaque message s’efface automatiquement après la durée de la discussion (72 h par défaut, ou moins si vous l’avez réglée), qu’il ait été lu ou non. Il disparaît du serveur et de votre téléphone, même sans connexion.'**
  String get chaqueMessageEffaceAutomatiquementApres;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment changer la durée des messages ?'**
  String get commentChangerDureeMessages;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Dans une discussion, touchez la minuterie en haut, ou la carte « Les messages de cette discussion s’effacent… ». Pour un seul message, touchez la minuterie dans la zone de saisie. Une durée ne dépasse jamais 72 h.'**
  String get dansDiscussionTouchezMinuterieHaut;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mes messages sont-ils chiffrés ?'**
  String get mesMessagesSontIlsChiffres;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ils sont protégés pendant leur transport (connexion chiffrée) et enregistrés chiffrés sur votre téléphone. Sur les serveurs de Privio, ils restent techniquement accessibles à Privio jusqu’à leur expiration, puis sont définitivement effacés.'**
  String get ilsSontProtegesPendantLeur;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Peut-on faire une capture d’écran ?'**
  String get peutOnFaireCaptureEcran;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Non, les captures d’écran sont bloquées dans Privio sur Android. Une photo prise avec un autre appareil reste toutefois possible.'**
  String get nonCapturesEcranSontBloquees;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pourquoi ai-je été déconnecté ?'**
  String get pourquoiAiJeEteDeconnecte;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Privio ne s’ouvre que sur un seul téléphone à la fois. Une connexion sur un autre appareil déconnecte le précédent et efface les messages qui y étaient enregistrés.'**
  String get privioNeOuvreQueSur;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Que se passe-t-il sans réseau ?'**
  String get queSePasseTIl;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les messages déjà reçus restent lisibles. Ceux que vous écrivez attendent et partent seuls dès le retour du réseau.'**
  String get messagesDejaRecusRestentLisibles;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment bloquer ou signaler quelqu’un ?'**
  String get commentBloquerOuSignalerQuelqu;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Touchez le nom du contact en haut de la discussion, puis « Bloquer » ou « Signaler ». Pour signaler un message précis, faites un appui long sur ce message.'**
  String get touchezNomContactHautDiscussion;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment écrire à quelqu’un pour la première fois ?'**
  String get commentEcrireQuelquPourPremiere;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Touchez le crayon, cherchez son identifiant (ou son numéro), puis « Envoyer une demande », avec un petit mot si vous voulez. Dès qu’elle accepte, la discussion s’ouvre chez vous deux. Sans réponse, la demande expire après 24 h ; après un refus, attendez quelques minutes avant de redemander (3 fois par jour au plus). Paramètres, Confidentialité : vous pouvez refuser toute demande.'**
  String get touchezCrayonCherchezSonIdentifiant;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pourquoi ne puis-je pas trouver quelqu’un ?'**
  String get pourquoiNePuisJePas;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'La recherche demande l’identifiant exact (ex. @awa_s). Par numéro, on ne trouve que les personnes qui ont activé « Me trouver par mon numéro ».'**
  String get rechercheDemandeIdentifiantExactEx;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Combien de photos puis-je envoyer ?'**
  String get combienPhotosPuisJeEnvoyer;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Jusqu’à 5 photos par jour, groupes compris ; le compteur repart à minuit. Une photo s’efface comme les messages et ne peut pas être enregistrée dans la galerie. Dans la galerie, vous pouvez en choisir plusieurs à la fois.'**
  String get jusqu5PhotosParJour;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Combien de temps dure un message vocal ?'**
  String get combienTempsDureMessageVocal;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'30 secondes au plus. Touchez le micro pour enregistrer sans le tenir, ou maintenez-le : glissez vers la gauche pour annuler, vers le haut pour lâcher le doigt. Sans le doigt, le bouton pause permet de reprendre plus tard ; les pauses ne comptent pas.'**
  String get n30SecondesPlusTouchezMicro;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment créer un groupe ?'**
  String get commentCreerGroupe;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Dans l’onglet Groupes, touchez « Nouveau groupe », donnez-lui un nom et choisissez les personnes à inviter (25 membres au plus). Chacune doit accepter l’invitation.'**
  String get dansOngletGroupesTouchezNouveau;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment vider une discussion ?'**
  String get commentViderDiscussion;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ouvrez le menu en haut à droite de la discussion, puis « Vider la discussion ». « Seulement chez moi » vide votre copie. « Pour nous deux » envoie une demande : si la personne accepte dans les 24 h, tout disparaît des deux côtés, sans trace. Dans un groupe, les administrateurs peuvent vider pour tous.'**
  String get ouvrezMenuHautDroiteDiscussion;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Que se passe-t-il si j’oublie mon code ?'**
  String get queSePasseTIl2;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Touchez « Code oublié ? » sur l’écran de verrouillage. Il faudra vous déconnecter, ce qui efface les messages gardés sur ce téléphone, puis vous reconnecter par SMS.'**
  String get touchezCodeOublieSurEcran;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Qui voit que je suis en ligne ?'**
  String get quiVoitQueJeSuis;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Par défaut, vos contacts. Changez-le dans Paramètres, Confidentialité, « En ligne et vu à ». Ce choix ne vous empêche pas de voir celui des autres.'**
  String get parDefautVosContactsChangez;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Comment économiser mes données ?'**
  String get commentEconomiserMesDonnees;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Dans Paramètres, Stockage et données, choisissez quand les photos se téléchargent : toujours, en Wi-Fi seulement ou jamais (vous touchez alors la photo pour la télécharger). Le même écran indique les données utilisées.'**
  String get dansParametresStockageDonneesChoisissez;

  /// Écran : ui/features/settings/help_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Aide et assistance'**
  String get aideAssistance;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Questions fréquentes'**
  String get questionsFrequentes;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Assistance'**
  String get assistance;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Contacter l’assistance'**
  String get contacterAssistance;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Un problème, une question ? Décrivez-le en quelques mots.'**
  String get problemeQuestionDecrivezQuelquesMots;

  /// Écran : ui/features/settings/help_screen.dart, ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mes demandes'**
  String get mesDemandes;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos messages à l’assistance et nos réponses'**
  String get vosMessagesAssistanceNosReponses;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Merci, votre message a été transmis à l’assistance. La réponse arrivera dans « Mes demandes ».'**
  String get merciVotreMessageEteTransmis;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Décrivez votre problème (sans données sensibles)'**
  String get decrivezVotreProblemeSansDonnees;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Diagnostic de connexion'**
  String get diagnosticConnexion;

  /// Écran : ui/features/settings/help_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Réception des messages en direct'**
  String get receptionMessagesDirect;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ma fiche'**
  String get maFiche;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get profil;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get nom;

  /// Écran : ui/features/settings/my_profile_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un court texte de présentation'**
  String get ajouterCourtTextePresentation;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'@{handle} · ne peut pas être changé'**
  String handleNePeutPasEtre(Object handle);

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mon QR code'**
  String get monQrCode;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'À faire scanner dans Privio pour vous trouver'**
  String get faireScannerDansPrivioPour;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Numéro'**
  String get numero;

  /// Écran : ui/features/settings/my_profile_screen.dart, ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Qui voit quoi'**
  String get quiVoitQuoi;

  /// Écran : ui/features/settings/my_profile_screen.dart, ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Confidentialité'**
  String get confidentialite;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo, À propos, en ligne… pour tous ou par discussion'**
  String get photoProposLignePourTous;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Nom enregistré.'**
  String get nomEnregistre;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos contacts et les membres de vos groupes le voient. Les anciens messages d’événements de groupe gardent l’ancien nom.'**
  String get vosContactsMembresVosGroupes;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'À propos retiré.'**
  String get proposRetire;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'À propos enregistré.'**
  String get proposEnregistre;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo de profil retirée.'**
  String get photoProfilRetiree;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photo de profil mise à jour.'**
  String get photoProfilMiseJour;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Par exemple : « Disponible », « Au travail ». Qui le voit se règle dans Confidentialité.'**
  String get parExempleDisponibleTravailQui;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre court texte'**
  String get votreCourtTexte;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mon QR code Privio'**
  String get monQrCodePrivio;

  /// Écran : ui/features/settings/my_profile_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour vous trouver, la personne ouvre Privio : Nouvelle discussion → Scanner un QR code.'**
  String get pourVousTrouverPersonneOuvre;

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Vos messages à l’assistance et nos réponses apparaîtront ici.'**
  String get vosMessagesAssistanceNosReponses2;

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les demandes et les réponses sont gardées 90 jours.'**
  String get demandesReponsesSontGardees90;

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyée le {createdAt}'**
  String envoyeeCreatedat(Object createdAt);

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoyée'**
  String get envoyee;

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Réponse de l’équipe Privio'**
  String get reponseEquipePrivio;

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Le {repliedAt}'**
  String repliedat(Object repliedAt);

  /// Écran : ui/features/settings/my_support_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'L’équipe Privio vous répondra ici ; vous recevrez une notification.'**
  String get equipePrivioVousRepondraIci;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Durée par défaut des messages'**
  String get dureeParDefautMessages;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour les discussions et groupes que vous créerez.'**
  String get pourDiscussionsGroupesQueVous;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Statut « en ligne » et « vu à »'**
  String get statutLigneVu;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Qui voit si vous êtes connecté, et quand vous l’étiez pour la dernière fois.'**
  String get quiVoitSiVousEtes;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les autres voient vos initiales à la place.'**
  String get autresVoientVosInitialesPlace;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Votre court texte de présentation, affiché sur votre fiche.'**
  String get votreCourtTextePresentationAffiche;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Invitations dans les groupes'**
  String get invitationsDansGroupes;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les personnes non autorisées ne peuvent pas vous inviter (sans qu’on le leur dise). Une invitation doit toujours être acceptée.'**
  String get personnesNonAutoriseesNePeuvent;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Qui peut m’inviter dans un groupe'**
  String get quiPeutMInviterDans;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'« Mes contacts » : les personnes avec qui vous êtes connecté (discussion à deux). Une personne bloquée ne voit jamais rien. Chaque discussion peut avoir ses propres réglages (fiche du contact ou du groupe).'**
  String get mesContactsPersonnesAvecQui;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Messages'**
  String get messages;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Si désactivés, on ne voit plus quand vous avez lu. Vous voyez toujours ceux des autres.'**
  String get siDesactivesOnNeVoit;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivé : personne ne voit quand vous écrivez.'**
  String get desactivePersonneNeVoitQuand;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'{maxTtlSeconds} · nouvelles discussions'**
  String maxttlsecondsNouvellesDiscussions(Object maxTtlSeconds);

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Pour effacer une discussion entière : fiche du contact ou du groupe, « Vider la discussion ».'**
  String get pourEffacerDiscussionEntiereFiche;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Liens et GIF'**
  String get liensGif;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'L’aperçu d’un lien est préparé par le serveur Privio : votre téléphone ne contacte pas le site, et vos contacts non plus.'**
  String get apercuLienEstPreparePar;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Sécurité'**
  String get securite;

  /// Écran : ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Verrouillage de l’application'**
  String get verrouillageApplication;

  /// Écran : ui/features/settings/privacy_screen.dart, ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Activé · {toLowerCase}'**
  String activeTolowercase(Object toLowerCase);

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Captures d’écran'**
  String get capturesEcran;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Toujours bloquées dans Privio (non modifiable).'**
  String get toujoursBloqueesDansPrivioNon;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Tout le monde peut vous envoyer une demande.'**
  String get toutMondePeutVousEnvoyer;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Personne ne peut vous envoyer de demande.'**
  String get personneNePeutVousEnvoyer;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Tout public'**
  String get toutPublic;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Recommandé.'**
  String get recommande;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Modéré'**
  String get modere;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Quelques contenus moins adaptés aux enfants.'**
  String get quelquesContenusMoinsAdaptesEnfants;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Aperçus des liens'**
  String get apercusLiens;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Titre et image des liens que vous envoyez.'**
  String get titreImageLiensQueVous;

  /// Écran : ui/features/settings/privacy_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Contenu des GIF'**
  String get contenuGif;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter ?'**
  String get seDeconnecter2;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Vous devrez recevoir un nouveau code SMS pour vous reconnecter.'**
  String get vousDevrezRecevoirNouveauCode;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'En ligne, photo, accusés de lecture, invitations, durée par défaut'**
  String get lignePhotoAccusesLectureInvitations;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Me trouver par mon numéro'**
  String get meTrouverParMonNumero;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Activé : on peut aussi vous trouver par votre numéro.'**
  String get activeOnPeutAussiVous;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivé : on vous trouve seulement par votre identifiant.'**
  String get desactiveOnVousTrouveSeulement;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Désactivé : on vous trouve seulement par @{handle}.'**
  String desactiveOnVousTrouveSeulement2(Object handle);

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Notifications et gestes'**
  String get notificationsGestes;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Sans nom ni contenu.'**
  String get sansNomNiContenu;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Sons et vibrations'**
  String get sonsVibrations;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Envoi, réception, effacement… Rien en mode silencieux du téléphone.'**
  String get envoiReceptionEffacementRienMode;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Thème clair ou sombre, taille du texte'**
  String get themeClairOuSombreTaille;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Fond d’écran des discussions'**
  String get fondEcranDiscussions;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Motifs, couleurs ou une de vos photos'**
  String get motifsCouleursOuVosPhotos;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Groupes dans Discussions'**
  String get groupesDansDiscussions;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Les groupes apparaissent aussi dans Discussions.'**
  String get groupesApparaissentAussiDansDiscussions;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Séparés : les groupes sont seulement dans l’onglet Groupes.'**
  String get separesGroupesSontSeulementDans;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Réaction du double appui'**
  String get reactionDoubleAppui;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Toucher deux fois un message pour réagir.'**
  String get toucherDeuxFoisMessagePour;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce téléphone'**
  String get ceTelephone;

  /// Écran : ui/features/settings/settings_tab.dart, ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Stockage et données'**
  String get stockageDonnees;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement des photos, données utilisées, espace'**
  String get telechargementPhotosDonneesUtiliseesEspace;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Seul appareil connecté'**
  String get seulAppareilConnecte;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Une connexion sur un autre téléphone déconnecte celui-ci.'**
  String get connexionSurAutreTelephoneDeconnecte;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Administration'**
  String get administration;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Tableau de bord de Privio (chiffres seulement)'**
  String get tableauBordPrivioChiffresSeulement;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Inviter un ami'**
  String get inviterAmi;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Partager votre identifiant'**
  String get partagerVotreIdentifiant;

  /// Écran : ui/features/settings/settings_tab.dart
  ///
  /// In fr, this message translates to:
  /// **'Privio {appVersionProvider} · Messagerie privée et éphémère'**
  String privioAppversionproviderMessageriePriveeEphemere(Object appVersionProvider);

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Effacer les photos et vocaux gardés ?'**
  String get effacerPhotosVocauxGardes;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Les photos et vocaux gardés sur ce téléphone sont effacés. Tant que les messages ne sont pas effacés, vous pourrez les télécharger de nouveau (cela consomme des données). Les envois en attente sont conservés.'**
  String get photosVocauxGardesSurCe;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Rien à effacer.'**
  String get rienEffacer;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement automatique des photos'**
  String get telechargementAutomatiquePhotos;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Sans téléchargement automatique, une photo reçue s’affiche en attente : touchez-la pour la télécharger. Les vocaux ne se téléchargent que lorsque vous les écoutez. Vos propres envois ne sont jamais retéléchargés.'**
  String get sansTelechargementAutomatiquePhotoRecue;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Données utilisées par les photos et vocaux'**
  String get donneesUtiliseesParPhotosVocaux;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Ce mois-ci'**
  String get ceMoisCi;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Reçu {month} · envoyé {month2}'**
  String recuMonthEnvoyeMonth2(Object month, Object month2);

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Mois précédent'**
  String get moisPrecedent;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Reçu {previousMonth} · envoyé {previousMonth2}'**
  String recuPreviousmonthEnvoyePreviousmonth2(Object previousMonth, Object previousMonth2);

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Remettre les compteurs à zéro'**
  String get remettreCompteursZero;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photos, vocaux et photos de profil échangés depuis ce téléphone. Les messages texte, très légers, ne sont pas comptés. Chiffres indicatifs : votre opérateur fait foi.'**
  String get photosVocauxPhotosProfilEchanges;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Espace sur ce téléphone'**
  String get espaceSurCeTelephone;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Photos et vocaux sur ce téléphone'**
  String get photosVocauxSurCeTelephone;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Indisponible'**
  String get indisponible;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Calcul…'**
  String get calcul;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Effacer les photos et vocaux gardés'**
  String get effacerPhotosVocauxGardes2;

  /// Écran : ui/features/settings/storage_screen.dart
  ///
  /// In fr, this message translates to:
  /// **'Chaque photo ou vocal s’efface avec son message.'**
  String get chaquePhotoOuVocalEfface;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Motif Privio'**
  String get motifPrivio;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Points'**
  String get points;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Vagues'**
  String get vagues;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Uni'**
  String get uni;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Fond · {title}'**
  String fondTitle(Object title);

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Salut, ça va ?'**
  String get salutCaVa;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Par défaut pour toutes les discussions. Chaque discussion peut avoir le sien (fiche de la discussion).'**
  String get parDefautPourToutesDiscussions;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Seulement pour cette discussion. La photo choisie reste sur ce téléphone.'**
  String get seulementPourCetteDiscussionPhoto;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Par défaut'**
  String get parDefaut;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Ma photo'**
  String get maPhoto;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisir une photo'**
  String get choisirPhoto;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'Choisir une autre photo'**
  String get choisirAutrePhoto;

  /// Écran : ui/features/settings/wallpaper.dart
  ///
  /// In fr, this message translates to:
  /// **'La photo n’est jamais envoyée : elle reste sur ce téléphone.'**
  String get photoNEstJamaisEnvoyee;

  /// Écran : verrouillage (lecteur d’écran)
  ///
  /// In fr, this message translates to:
  /// **'{filled, plural, one{{filled} chiffre} other{{filled} chiffres}} sur {total}'**
  String pinProgress(int filled, Object total);

  /// Écran : verrouillage
  ///
  /// In fr, this message translates to:
  /// **'Code incorrect. Encore {count, plural, one{{count} essai} other{{count} essais}} avant une attente.'**
  String pinWrongAttemptsLeft(int count);

  /// Écran : envoi de photos
  ///
  /// In fr, this message translates to:
  /// **'Après l’envoi : {after, plural, one{{after} photo} other{{after} photos}} aujourd’hui ({limit} par jour).'**
  String photoQuotaAfterSend(int after, Object limit);

  /// Heure ajoutée à une phrase (« Nouvel essai possible à 14:30 »)
  ///
  /// In fr, this message translates to:
  /// **' à {time}'**
  String atTime(Object time);

  /// Écran : discussion (photo en vue unique)
  ///
  /// In fr, this message translates to:
  /// **'Photo · vue unique'**
  String get photoViewOnce;

  /// Écran : discussion (vocal en vue unique)
  ///
  /// In fr, this message translates to:
  /// **'Vocal · vue unique'**
  String get voiceViewOnce;

  /// Écran : discussion (sélection multiple)
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{{n} sélectionné} other{{n} sélectionnés}}'**
  String selectedCount(int n);

  /// Remplace le nom d’un membre inconnu
  ///
  /// In fr, this message translates to:
  /// **'ce membre'**
  String get ceMembre;

  /// Écran : discussion de groupe
  ///
  /// In fr, this message translates to:
  /// **'Le message de {name} sera supprimé pour tous les membres du groupe.'**
  String deleteGroupMessageForAll(Object name);

  /// Aperçu d’un autocollant
  ///
  /// In fr, this message translates to:
  /// **'Autocollant'**
  String get stickerNoLabel;

  /// Aperçu d’un autocollant
  ///
  /// In fr, this message translates to:
  /// **'Autocollant « {label} »'**
  String stickerWithLabel(Object label);

  /// Écran : discussion
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée : en attente de l’accord de {name} pour supprimer la discussion.'**
  String deleteRequestSent(Object name);

  /// Écran : discussion
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée : en attente de l’accord de {name} pour vider toute la discussion.'**
  String clearRequestSent(Object name);

  /// Écran : discussion (lecteur d’écran)
  ///
  /// In fr, this message translates to:
  /// **'Descendre aux derniers messages, {count, plural, one{{count} nouveau} other{{count} nouveaux}}'**
  String scrollDownNew(int count);

  /// Écran : fiche (médias)
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, one{{count} élément} other{{count} éléments}} · effacés avec les messages'**
  String mediaCountErased(int count);

  /// Écran : fiche du contact, carte d’une personne
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, one{{count} groupe en commun} other{{count} groupes en commun}}'**
  String groupsInCommon(int count);

  /// Lecteur d’écran : enregistrement d’un vocal
  ///
  /// In fr, this message translates to:
  /// **'Enregistrement en pause, {elapsed} sur {max}'**
  String recordingPaused(Object elapsed, Object max);

  /// Lecteur d’écran : enregistrement d’un vocal
  ///
  /// In fr, this message translates to:
  /// **'Enregistrement en cours, {elapsed} sur {max}'**
  String recordingRunning(Object elapsed, Object max);

  /// Écran : messages favoris
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{{n} message} other{{n} messages}} · s’effacent avec les messages'**
  String favoritesCountErased(int n);

  /// Écran : stockage
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{{n} fichier effacé.} other{{n} fichiers effacés.}}'**
  String filesErased(int n);

  /// Écran : stockage
  ///
  /// In fr, this message translates to:
  /// **'{files, plural, one{{files} fichier} other{{files} fichiers}} · {size}'**
  String filesSize(int files, Object size);

  /// Écran : groupes (invitation reçue)
  ///
  /// In fr, this message translates to:
  /// **'{name} vous invite · {count, plural, one{{count} membre} other{{count} membres}}'**
  String groupInviteLine(Object name, int count);

  /// Personne inconnue
  ///
  /// In fr, this message translates to:
  /// **'Quelqu’un'**
  String get someone;

  /// Écran : nouveau groupe
  ///
  /// In fr, this message translates to:
  /// **'Créer et inviter {count, plural, one{{count} personne} other{{count} personnes}}'**
  String createAndInvite(int count);

  /// Écran : groupe
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{{n} invitation envoyée.} other{{n} invitations envoyées.}}'**
  String invitationsSent(int n);

  /// Écran : inviter dans un groupe
  ///
  /// In fr, this message translates to:
  /// **'Inviter {count, plural, one{{count} personne} other{{count} personnes}}'**
  String invitePeople(int count);

  /// Écran : choix de la durée des messages
  ///
  /// In fr, this message translates to:
  /// **'Valider {duration}'**
  String validateTtl(Object duration);

  /// Bouton
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get validate;

  /// État de la connexion en temps réel
  ///
  /// In fr, this message translates to:
  /// **'Indisponible'**
  String get unavailable;

  /// État de la connexion en temps réel
  ///
  /// In fr, this message translates to:
  /// **'Indisponible ({detail})'**
  String unavailableDetail(Object detail);

  /// Taille en mégaoctets
  ///
  /// In fr, this message translates to:
  /// **'{size} Mo'**
  String sizeMo(Object size);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez créé le groupe « {title} »'**
  String evtCreatedMine(Object title);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a créé le groupe « {title} »'**
  String evtCreatedOther(Object actor, Object title);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez retiré {target} du groupe'**
  String evtRemovedMine(Object target);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a retiré {target} du groupe'**
  String evtRemovedOther(Object actor, Object target);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez nommé {target} administrateur'**
  String evtAdminAddedMine(Object target);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a nommé {target} administrateur'**
  String evtAdminAddedOther(Object actor, Object target);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez retiré le rôle d’administrateur à {target}'**
  String evtAdminRemovedMine(Object target);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a retiré le rôle d’administrateur à {target}'**
  String evtAdminRemovedOther(Object actor, Object target);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez confié le groupe à {target}'**
  String evtOwnerChangedMine(Object target);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a confié le groupe à {target}'**
  String evtOwnerChangedOther(Object actor, Object target);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez renommé le groupe « {title} »'**
  String evtTitleMine(Object title);

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a renommé le groupe « {title} »'**
  String evtTitleOther(Object actor, Object title);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez modifié la description du groupe'**
  String get evtDescriptionMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a modifié la description du groupe'**
  String evtDescriptionOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez changé la photo du groupe'**
  String get evtPhotoMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a changé la photo du groupe'**
  String evtPhotoOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez retiré la photo du groupe'**
  String get evtPhotoRemovedMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a retiré la photo du groupe'**
  String evtPhotoRemovedOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez réservé l’envoi de messages aux administrateurs'**
  String get evtPostingAdminsMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a réservé l’envoi de messages aux administrateurs'**
  String evtPostingAdminsOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez permis à tous les membres d’écrire'**
  String get evtPostingAllMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a permis à tous les membres d’écrire'**
  String evtPostingAllOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez réservé la modification du groupe aux administrateurs'**
  String get evtInfoAdminsMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a réservé la modification du groupe aux administrateurs'**
  String evtInfoAdminsOther(Object actor);

  /// Message système de groupe (fait par moi)
  ///
  /// In fr, this message translates to:
  /// **'Vous avez permis à tous les membres de modifier le groupe'**
  String get evtInfoAllMine;

  /// Message système de groupe (fait par un membre)
  ///
  /// In fr, this message translates to:
  /// **'{actor} a permis à tous les membres de modifier le groupe'**
  String evtInfoAllOther(Object actor);

  /// Paramètres → Langue (titre)
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get languageTitle;

  /// Paramètres → Langue (sous-titre tant que seul le français est proposé)
  ///
  /// In fr, this message translates to:
  /// **'Mooré et dioula bientôt'**
  String get languageSubtitleSoon;

  /// Paramètres → Langue : langue pas encore disponible
  ///
  /// In fr, this message translates to:
  /// **'Traduction en cours'**
  String get languageInProgress;

  /// Paramètres → Langue (note)
  ///
  /// In fr, this message translates to:
  /// **'Les textes pas encore traduits restent en français. Les boutons standard d’Android et les dates restent aussi en français.'**
  String get languageNote;

  /// Écran de bienvenue : bouton de choix de la langue
  ///
  /// In fr, this message translates to:
  /// **'Langue : {language}'**
  String languageChip(Object language);

  /// Écran : envoi de photos (photo 1 sur 3)
  ///
  /// In fr, this message translates to:
  /// **'{index} sur {total}'**
  String photoIndexOf(Object index, Object total);

  /// Lecteur d’écran : action sur une photo
  ///
  /// In fr, this message translates to:
  /// **'agrandir'**
  String get hintEnlarge;

  /// Nombre de membres d’un groupe
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, one{{count} membre} other{{count} membres}}'**
  String membersCount(int count);

  /// Ajouté à l’heure d’un message modifié
  ///
  /// In fr, this message translates to:
  /// **' · modifié'**
  String get editedSuffix;

  /// Bandeau au-dessus de la zone de saisie (« Réponse à Awa : … »)
  ///
  /// In fr, this message translates to:
  /// **'{label} : {text}'**
  String labelColonText(Object label, Object text);

  /// Lecteur d’écran : étoile d’un message favori
  ///
  /// In fr, this message translates to:
  /// **'favori'**
  String get semFavorite;

  /// Lecteur d’écran : durée d’un vocal
  ///
  /// In fr, this message translates to:
  /// **'{s, plural, one{{s} seconde} other{{s} secondes}}'**
  String secondsSpoken(int s);

  /// Lecteur d’écran : action du micro
  ///
  /// In fr, this message translates to:
  /// **'enregistrer'**
  String get hintRecord;

  /// Liste des membres : moi
  ///
  /// In fr, this message translates to:
  /// **'{name} (vous)'**
  String nameYou(Object name);

  /// Durée en minutes
  ///
  /// In fr, this message translates to:
  /// **'{n} min'**
  String unitMinutes(Object n);

  /// Durée en heures
  ///
  /// In fr, this message translates to:
  /// **'{n} h'**
  String unitHours(Object n);

  /// Durée en secondes
  ///
  /// In fr, this message translates to:
  /// **'{n} s'**
  String unitSeconds(Object n);

  /// Lecteur d’écran : fond d’écran sélectionné
  ///
  /// In fr, this message translates to:
  /// **'choisi'**
  String get semChosen;

  /// Durée des messages en minutes (espace insécable)
  ///
  /// In fr, this message translates to:
  /// **'{n} min'**
  String ttlMinutes(Object n);

  /// Durée des messages en heures (espace insécable)
  ///
  /// In fr, this message translates to:
  /// **'{n} h'**
  String ttlHours(Object n);

  /// Durée des messages en heures et minutes (4 h 30, espaces insécables)
  ///
  /// In fr, this message translates to:
  /// **'{h} h {m}'**
  String ttlHoursMinutes(Object h, Object m);

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Mon compte'**
  String get settingsAccountSection;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Préférences'**
  String get settingsPreferencesSection;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Privio'**
  String get settingsPrivioSection;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Qui voit quoi, demandes, accusés de lecture, personnes bloquées'**
  String get settingsPrivacySubtitle;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Verrouillage, changement de numéro, captures d’écran'**
  String get settingsSecuritySubtitle;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Notifications et sons'**
  String get notificationsSons;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Notifications sans contenu, sons et vibrations'**
  String get settingsNotificationsSubtitle;

  /// Écran : Paramètres
  ///
  /// In fr, this message translates to:
  /// **'Fond d’écran, réaction du double appui, archivées'**
  String get settingsChatsSubtitle;

  /// Écran : Confidentialité
  ///
  /// In fr, this message translates to:
  /// **'Qui peut me joindre'**
  String get privacyReachSection;

  /// Écran : Liste des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Archivés'**
  String get archivesTitle;

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Tout marquer comme lu'**
  String get toutMarquerCommeLu;

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Tout marquer comme lu ?'**
  String get markAllReadTitle;

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{Les messages non lus d’une discussion seront marqués comme lus.} other{Les messages non lus de {n} discussions seront marqués comme lus.}} Si vos accusés de lecture sont activés, les personnes verront « lu ».'**
  String markAllReadBody(int n);

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Marquer comme lu'**
  String get marquerCommeLu;

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, one{1 discussion marquée comme lue.} other{{n} discussions marquées comme lues.}}'**
  String markAllReadDone(int n);

  /// Écran : Listes des discussions et des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Verrouiller Privio maintenant'**
  String get verrouillerMaintenant;

  /// Écran : Liste des discussions (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Demandes de connexion ({n})'**
  String demandesConnexionCount(int n);

  /// Écran : Liste des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Demandes envoyées ({n})'**
  String demandesEnvoyeesCount(int n);

  /// Écran : Liste des groupes (menu ⋮)
  ///
  /// In fr, this message translates to:
  /// **'Aucune demande en attente.'**
  String get aucuneDemandeEnvoyee;

  /// Écran : Messages favoris (toutes les discussions)
  ///
  /// In fr, this message translates to:
  /// **'{conversation} · {sender} · {time}'**
  String favoriteLine(Object conversation, Object sender, Object time);

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Nom, @identifiant ou numéro'**
  String get searchContactsLabel;

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Nouvelles personnes : identifiant exact ou numéro complet'**
  String get searchContactsHelper;

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Mes contacts ({n})'**
  String mesContactsCount(int n);

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Contacts'**
  String get contactsTitle;

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Aucun contact ne correspond.'**
  String get aucunContactCorrespond;

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Vos contacts apparaîtront ici dès qu’une demande de connexion sera acceptée.'**
  String get aucunContactPourInstant;

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Chercher « {query} » sur Privio'**
  String chercherSurPrivio(Object query);

  /// Écran : Nouvelle discussion
  ///
  /// In fr, this message translates to:
  /// **'Identifiant exact ou numéro complet'**
  String get chercherSurPrivioAide;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Vérification en deux étapes'**
  String get twoStepTitle;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Activée'**
  String get twoStepOn;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Désactivée'**
  String get twoStepOff;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez un code de sécurité à 6 chiffres. Il sera demandé, en plus du code reçu par SMS, si quelqu’un se connecte à votre compte sur un autre téléphone, et pour changer de numéro.'**
  String get twoStepIntro;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un code différent du code de verrouillage de ce téléphone et ne le donnez à personne. Si vous l’oubliez, seule l’assistance Privio pourra désactiver la vérification, après avoir vérifié votre identité.'**
  String get twoStepHint;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Activer'**
  String get activer;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Désactiver'**
  String get desactiver;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Changer le code de sécurité'**
  String get twoStepChange;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Vérification en deux étapes activée.'**
  String get twoStepEnabledDone;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Vérification en deux étapes désactivée.'**
  String get twoStepDisabledDone;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Code de sécurité modifié.'**
  String get twoStepChangedDone;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Code de sécurité'**
  String get codeSecurite;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Code de sécurité actuel'**
  String get codeSecuriteActuel;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Ce compte est protégé par un code de sécurité. Saisissez-le pour continuer. Le téléphone déjà connecté le reste tant que le bon code n’est pas saisi.'**
  String get twoStepVerifyIntro;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Code de sécurité oublié'**
  String get twoStepForgotTitle;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'L’assistance Privio peut désactiver la vérification en deux étapes après avoir vérifié votre identité. Envoyer une demande ?'**
  String get twoStepForgotBody;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée à l’assistance le {date}. Dès que la vérification sera désactivée, Privio s’ouvrira sur ce téléphone.'**
  String twoStepResetRequested(Object date);

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Vérifier maintenant'**
  String get verifierMaintenant;

  /// Écran : Vérification en deux étapes
  ///
  /// In fr, this message translates to:
  /// **'Se connecter avec un autre numéro'**
  String get twoStepOtherNumber;

  /// Écran : Changer de numéro
  ///
  /// In fr, this message translates to:
  /// **'Votre compte est protégé : saisissez votre code de sécurité pour changer de numéro.'**
  String get twoStepPhoneChangeIntro;

  /// Écran : Liste des discussions
  ///
  /// In fr, this message translates to:
  /// **'Protégez votre compte'**
  String get twoStepPromptTitle;

  /// Écran : Liste des discussions
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez un code de sécurité en plus du SMS, pour qu’un vol de votre carte SIM ne suffise pas à ouvrir votre compte.'**
  String get twoStepPromptBody;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'La vérification en deux étapes est déjà activée.'**
  String get twoStepAlreadyEnabled;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'La vérification en deux étapes n’est pas activée.'**
  String get twoStepNotEnabled;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Saisissez d’abord votre code de sécurité.'**
  String get twoStepRequired;

  /// Écran : Notifications et sons
  ///
  /// In fr, this message translates to:
  /// **'Rappel avant effacement'**
  String get expiryReminderTitle;

  /// Écran : Notifications et sons
  ///
  /// In fr, this message translates to:
  /// **'Une notification sans contenu quand des messages non lus vont s’effacer dans moins de 4 h.'**
  String get expiryReminderSubtitle;

  /// Écran : Discussion (bulle, lecteur d’écran)
  ///
  /// In fr, this message translates to:
  /// **'S’efface bientôt, dans {remaining}'**
  String bubbleSoon(Object remaining);

  /// Écran : Demandes de connexion, Nouvelle discussion, Carte d’une personne
  ///
  /// In fr, this message translates to:
  /// **'Attention : vous avez déjà un contact nommé {name} (@{contactHandle}). Ce compte est différent : @{handle}. Vérifiez auprès de la personne avant d’accepter ou de lui écrire.'**
  String impersonationWarning(Object name, Object contactHandle, Object handle);

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Ce que Privio garde'**
  String get keepTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Privio est fait pour que vos échanges ne durent pas. Voici ce que nous gardons, combien de temps, et pourquoi.'**
  String get keepIntro;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Vos messages'**
  String get keepMessagesTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Messages, photos, vocaux, GIF et aperçus de liens sont gardés sur nos serveurs le temps de vous les remettre, puis effacés automatiquement à la fin de leur durée (72 h au plus). Une fois effacés, personne ne peut les récupérer, ni vous, ni nous.'**
  String get keepMessages1;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'« Supprimer pour tout le monde » efface aussitôt. Une photo ou un vocal en vue unique ne s’ouvre qu’une fois.'**
  String get keepMessages2;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Favoris et messages épinglés disparaissent avec le message.'**
  String get keepMessages3;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Votre compte'**
  String get keepAccountTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Votre numéro sert à vous connecter. Il n’est jamais montré aux autres ; on ne vous trouve par votre numéro que si vous l’avez autorisé.'**
  String get keepAccount1;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Votre nom, votre identifiant, votre photo et votre « À propos » sont visibles selon vos réglages de confidentialité.'**
  String get keepAccount2;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Vos contacts, vos groupes, vos blocages et vos réglages sont gardés jusqu’à la suppression de votre compte, qui efface tout.'**
  String get keepAccount3;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Gardé un peu plus longtemps'**
  String get keepLongerTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Demandes de connexion : le petit mot est effacé 5 minutes après l’acceptation ; la demande, 7 jours après la réponse.'**
  String get keepLonger1;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Signalements et demandes d’assistance : 90 jours. Un signalement ne contient la copie d’un message que si la personne qui signale l’a jointe.'**
  String get keepLonger2;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Journal des notifications (sans nom ni contenu) : 7 jours.'**
  String get keepLonger3;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Journal des actions de l’équipe Privio : 30 jours.'**
  String get keepLonger4;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Ce que nous ne faisons jamais'**
  String get keepNeverTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Pas de publicité, pas de revente de vos données.'**
  String get keepNever1;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Pas d’annuaire : on ne trouve quelqu’un que par son identifiant exact, ou par son numéro s’il l’a permis.'**
  String get keepNever2;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Les notifications n’affichent ni nom ni contenu.'**
  String get keepNever3;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'L’outil de l’équipe Privio n’affiche jamais vos discussions, sauf la copie jointe à un signalement.'**
  String get keepNever4;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Captures d’écran bloquées, pas de sauvegarde de Privio vers le cloud.'**
  String get keepNever5;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Sur ce téléphone'**
  String get keepPhoneTitle;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Une copie protégée de vos discussions permet de les lire hors connexion. Elle s’efface avec les messages, et entièrement quand vous vous déconnectez.'**
  String get keepPhone1;

  /// Écran : Ce que Privio garde — texte validé le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Ce que nous gardons, combien de temps, et pourquoi'**
  String get keepEntrySubtitle;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel entrant'**
  String get callIncoming;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel Privio entrant'**
  String get callIncomingLocked;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Ça sonne…'**
  String get callRinging;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Connexion…'**
  String get callConnecting;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Connexion faible, reconnexion…'**
  String get callReconnecting;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel terminé · {duration}'**
  String callEndedDuration(Object duration);

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel terminé'**
  String get callEnded;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel refusé'**
  String get callDeclined;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Pas de réponse'**
  String get callNoAnswer;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Déjà en appel'**
  String get callBusy;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel interrompu'**
  String get callFailed;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel annulé'**
  String get callCancelled;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel manqué'**
  String get callMissed;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Décrocher'**
  String get decrocher;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get refuser2;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Raccrocher'**
  String get raccrocher;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Micro'**
  String get micro;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Micro coupé'**
  String get microCoupe;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Haut-parleur'**
  String get hautParleur;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Réduire'**
  String get reduire;

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel en cours · {duration} — toucher pour revenir'**
  String callBar(Object duration);

  /// Écran : Appel
  ///
  /// In fr, this message translates to:
  /// **'Appel en cours — toucher pour revenir'**
  String get callBarRinging;

  /// Écran : Discussion, Fiche du contact
  ///
  /// In fr, this message translates to:
  /// **'Appeler'**
  String get appeler;

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel sortant · {duration}'**
  String callTraceOutgoing(Object duration);

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel entrant · {duration}'**
  String callTraceIncoming(Object duration);

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel sans réponse'**
  String get callTraceNoAnswer;

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel manqué'**
  String get callTraceMissed;

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel refusé'**
  String get callTraceDeclined;

  /// Écran : Discussion (trace d’appel)
  ///
  /// In fr, this message translates to:
  /// **'Appel annulé'**
  String get callTraceCancelled;

  /// Écran : Confidentialité
  ///
  /// In fr, this message translates to:
  /// **'Recevoir des appels'**
  String get acceptCallsTitle;

  /// Écran : Confidentialité
  ///
  /// In fr, this message translates to:
  /// **'Vos contacts peuvent vous appeler.'**
  String get acceptCallsOn;

  /// Écran : Confidentialité
  ///
  /// In fr, this message translates to:
  /// **'Personne ne peut vous appeler.'**
  String get acceptCallsOff;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Cette personne ne reçoit pas d’appels pour le moment.'**
  String get callsDisabledError;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Un appel est déjà en cours.'**
  String get callAlreadyActiveError;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Les appels se font à deux, avec un contact.'**
  String get callDirectOnlyError;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Cet appel n’existe plus.'**
  String get callNotFoundError;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Cet appel est terminé.'**
  String get callEndedError;

  /// Écran : Messages d’erreur
  ///
  /// In fr, this message translates to:
  /// **'Ce type d’appel n’est pas encore disponible.'**
  String get callKindUnavailableError;

  /// Écran : Ce que Privio garde — ligne validée le 15/11/2026
  ///
  /// In fr, this message translates to:
  /// **'Appels : ni la voix ni l’image ne sont jamais enregistrées ni gardées. Qui a appelé qui, quand et combien de temps est gardé 7 jours, puis effacé ; la trace dans la discussion s’efface comme les messages.'**
  String get keepCalls;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Connexion faible'**
  String get callWeak;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Appel en cours'**
  String get callOngoingNotice;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Appels entrants'**
  String get callChannelIncoming;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Appels manqués'**
  String get callChannelMissed;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Sortie du son'**
  String get callRouteTitle;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Son'**
  String get callRouteButton;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Écouteur du téléphone'**
  String get callRouteEarpiece;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Haut-parleur'**
  String get callRouteSpeaker;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Bluetooth'**
  String get callRouteBluetooth;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Casque filaire'**
  String get callRouteWired;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Appels avec le téléphone verrouillé'**
  String get callFullScreenTitle;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Pour voir et décrocher les appels Privio quand le téléphone est verrouillé ou que Privio est fermé, autorisez Privio à afficher les appels en plein écran. Le nom de la personne n’apparaît pas tant que le téléphone est verrouillé.'**
  String get callFullScreenBody;

  /// Écran : Appel (lot 9.1b)
  ///
  /// In fr, this message translates to:
  /// **'Autoriser'**
  String get callFullScreenAllow;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo'**
  String get callVideoButton;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo entrant'**
  String get callVideoIncoming;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo Privio entrant'**
  String get callVideoIncomingLocked;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Caméra'**
  String get callCamera;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Caméra coupée'**
  String get callCameraOff;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Changer de caméra'**
  String get callFlip;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Caméra refusée : autorisez-la dans les réglages du téléphone.'**
  String get callCameraDenied;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo sortant · {duration}'**
  String callTraceVideoOutgoing(String duration);

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo entrant · {duration}'**
  String callTraceVideoIncoming(String duration);

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo sans réponse'**
  String get callTraceVideoNoAnswer;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo manqué'**
  String get callTraceVideoMissed;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo refusé'**
  String get callTraceVideoDeclined;

  /// Appels vidéo (lot 9.2)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo annulé'**
  String get callTraceVideoCancelled;

  /// Menus : afficher les autres actions (lot 8.5a)
  ///
  /// In fr, this message translates to:
  /// **'Voir plus'**
  String get voirPlus;

  /// Aide : licences (lot 8.5b)
  ///
  /// In fr, this message translates to:
  /// **'Licences'**
  String get licences;

  /// Aide : licences (lot 8.5b)
  ///
  /// In fr, this message translates to:
  /// **'Logiciels libres et émojis animés utilisés par Privio'**
  String get licencesSubtitle;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Découvrir Privio'**
  String get discoverTitle;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Les fonctions principales en 6 écrans'**
  String get discoverEntrySubtitle;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Passer'**
  String get discoverSkip;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Suivant'**
  String get discoverNext;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'C’est parti'**
  String get discoverStart;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue sur Privio'**
  String get discover1Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Une messagerie privée où les messages s’effacent d’eux-mêmes. Voici l’essentiel en quelques écrans.'**
  String get discover1Body;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Démarrer une discussion'**
  String get discover2Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Touchez le crayon : vos contacts s’affichent, et vous pouvez chercher un identifiant. Scannez aussi le QR code d’un proche, ou retrouvez vos demandes de connexion dans le menu ⋮.'**
  String get discover2Body;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Vos messages s’effacent'**
  String get discover3Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Chaque discussion a sa durée, 72 h au départ. Touchez ⏱ en haut d’une discussion pour la changer : passé ce délai, les messages disparaissent chez tout le monde.'**
  String get discover3Body;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Les groupes'**
  String get discover4Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Créez un groupe dans l’onglet Groupes, invitez avec un lien ou un QR code et nommez des administrateurs pour vous aider.'**
  String get discover4Body;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Appels audio et vidéo'**
  String get discover5Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Appelez un contact depuis la discussion avec 📞 ou 🎥. Ni la voix ni l’image ne sont enregistrées.'**
  String get discover5Body;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Votre protection'**
  String get discover6Title;

  /// Guide Découvrir Privio (lot 8.5c)
  ///
  /// In fr, this message translates to:
  /// **'Verrouillez Privio avec un code (Paramètres › Sécurité). Les captures d’écran sont bloquées. Dans Confidentialité, choisissez qui voit votre photo et qui peut vous joindre.'**
  String get discover6Body;

  /// Erreur : fonctionnalité coupée dans la console (lot 5.5)
  ///
  /// In fr, this message translates to:
  /// **'Cette fonction est momentanément indisponible.'**
  String get featureDisabledError;

  /// Erreur : inscriptions fermées (lot 5.5)
  ///
  /// In fr, this message translates to:
  /// **'Les inscriptions sont fermées pour le moment. Réessayez plus tard.'**
  String get signupsClosedError;

  /// No description provided for @saisissezAuMoins4Chiffres.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez au moins 4 chiffres du numéro.'**
  String get saisissezAuMoins4Chiffres;

  /// No description provided for @handleChangeNotAllowedError.
  ///
  /// In fr, this message translates to:
  /// **'Votre identifiant ne peut pas être changé.'**
  String get handleChangeNotAllowedError;

  /// No description provided for @handleAlwaysReservedError.
  ///
  /// In fr, this message translates to:
  /// **'Ce mot est toujours réservé.'**
  String get handleAlwaysReservedError;

  /// No description provided for @avatarNotFoundError.
  ///
  /// In fr, this message translates to:
  /// **'Ce compte n’a plus de photo de profil.'**
  String get avatarNotFoundError;

  /// No description provided for @deviceNotFoundError.
  ///
  /// In fr, this message translates to:
  /// **'Cet appareil est déjà déconnecté.'**
  String get deviceNotFoundError;

  /// No description provided for @choisissezUnNouvelIdentifiant.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un nouvel identifiant'**
  String get choisissezUnNouvelIdentifiant;

  /// No description provided for @equipePrivioRemplaceIdentifiant.
  ///
  /// In fr, this message translates to:
  /// **'L’équipe Privio a remplacé votre identifiant, qui ne respectait pas les règles de Privio. Choisissez-en un nouveau pour continuer. Vos discussions et vos groupes ne changent pas.'**
  String get equipePrivioRemplaceIdentifiant;

  /// No description provided for @effacerApresLecture.
  ///
  /// In fr, this message translates to:
  /// **'Effacer après lecture'**
  String get effacerApresLecture;

  /// No description provided for @effacerApresLectureAide.
  ///
  /// In fr, this message translates to:
  /// **'Les messages envoyés à partir de maintenant disparaissent après avoir été lus, chez vous comme chez la personne qui les lit. Dans un groupe, chacun les voit disparaître à son rythme ; ils sont supprimés pour tous quand tout le monde les a lus.'**
  String get effacerApresLectureAide;

  /// No description provided for @effacerApresLectureGroupeAdmins.
  ///
  /// In fr, this message translates to:
  /// **'Dans un groupe, seuls les administrateurs peuvent le régler.'**
  String get effacerApresLectureGroupeAdmins;

  /// No description provided for @eraseOff.
  ///
  /// In fr, this message translates to:
  /// **'Désactivé'**
  String get eraseOff;

  /// No description provided for @erase30s.
  ///
  /// In fr, this message translates to:
  /// **'30 secondes'**
  String get erase30s;

  /// No description provided for @erase5min.
  ///
  /// In fr, this message translates to:
  /// **'5 minutes'**
  String get erase5min;

  /// No description provided for @erase1h.
  ///
  /// In fr, this message translates to:
  /// **'1 heure'**
  String get erase1h;

  /// No description provided for @eraseBanner.
  ///
  /// In fr, this message translates to:
  /// **'Effacement après lecture : {delay}'**
  String eraseBanner(Object delay);

  /// No description provided for @systemEraseOn.
  ///
  /// In fr, this message translates to:
  /// **'{who} activé l’effacement après lecture ({delay}).'**
  String systemEraseOn(Object who, Object delay);

  /// No description provided for @systemEraseOff.
  ///
  /// In fr, this message translates to:
  /// **'{who} désactivé l’effacement après lecture.'**
  String systemEraseOff(Object who);

  /// No description provided for @bubbleErase.
  ///
  /// In fr, this message translates to:
  /// **'S’efface après lecture'**
  String get bubbleErase;

  /// No description provided for @readEraseInvalidError.
  ///
  /// In fr, this message translates to:
  /// **'Ce délai n’est pas proposé.'**
  String get readEraseInvalidError;

  /// No description provided for @masquerDiscussion.
  ///
  /// In fr, this message translates to:
  /// **'Masquer la discussion'**
  String get masquerDiscussion;

  /// No description provided for @nePlusMasquer.
  ///
  /// In fr, this message translates to:
  /// **'Ne plus masquer'**
  String get nePlusMasquer;

  /// No description provided for @discussionsCachees.
  ///
  /// In fr, this message translates to:
  /// **'Discussions cachées'**
  String get discussionsCachees;

  /// No description provided for @aucuneDiscussionCachee.
  ///
  /// In fr, this message translates to:
  /// **'Aucune discussion cachée'**
  String get aucuneDiscussionCachee;

  /// No description provided for @aucuneDiscussionCacheeMessage.
  ///
  /// In fr, this message translates to:
  /// **'Appui long sur une discussion, puis « Masquer la discussion ».'**
  String get aucuneDiscussionCacheeMessage;

  /// No description provided for @discussionMasquee.
  ///
  /// In fr, this message translates to:
  /// **'Discussion masquée. Appui long sur le logo Privio pour la retrouver.'**
  String get discussionMasquee;

  /// No description provided for @discussionReaffichee.
  ///
  /// In fr, this message translates to:
  /// **'La discussion est de retour dans la liste.'**
  String get discussionReaffichee;

  /// No description provided for @codePrivioCree.
  ///
  /// In fr, this message translates to:
  /// **'Code Privio créé.'**
  String get codePrivioCree;

  /// No description provided for @codePrivioPourDiscussionsCachees.
  ///
  /// In fr, this message translates to:
  /// **'Ce code ouvrira vos discussions cachées. Il ne verrouille pas Privio à l’ouverture.'**
  String get codePrivioPourDiscussionsCachees;

  /// No description provided for @messagesVocaux.
  ///
  /// In fr, this message translates to:
  /// **'Messages vocaux'**
  String get messagesVocaux;

  /// No description provided for @appels.
  ///
  /// In fr, this message translates to:
  /// **'Appels'**
  String get appels;

  /// No description provided for @autres.
  ///
  /// In fr, this message translates to:
  /// **'Autres'**
  String get autres;

  /// No description provided for @modeEco.
  ///
  /// In fr, this message translates to:
  /// **'Mode éco'**
  String get modeEco;

  /// No description provided for @modeEcoActif.
  ///
  /// In fr, this message translates to:
  /// **'Activé : Privio consomme moins de données.'**
  String get modeEcoActif;

  /// No description provided for @modeEcoInactif.
  ///
  /// In fr, this message translates to:
  /// **'Désactivé'**
  String get modeEcoInactif;

  /// No description provided for @modeEcoDetail.
  ///
  /// In fr, this message translates to:
  /// **'Photos et vocaux envoyés allégés ; photos, vocaux et GIF reçus téléchargés seulement au toucher ; GIF et aperçus des liens coupés ; vidéo réduite pendant les appels. Il ne s’active qu’à la main.'**
  String get modeEcoDetail;

  /// No description provided for @modeEcoPhotosAuToucher.
  ///
  /// In fr, this message translates to:
  /// **'Mode éco activé : les photos reçues se téléchargent seulement au toucher.'**
  String get modeEcoPhotosAuToucher;

  /// No description provided for @economiseCeMois.
  ///
  /// In fr, this message translates to:
  /// **'Économisé ce mois-ci'**
  String get economiseCeMois;

  /// No description provided for @estimationModeEco.
  ///
  /// In fr, this message translates to:
  /// **'Estimation, grâce au Mode éco'**
  String get estimationModeEco;

  /// No description provided for @gifToucherPourAfficher.
  ///
  /// In fr, this message translates to:
  /// **'GIF · toucher pour afficher'**
  String get gifToucherPourAfficher;

  /// No description provided for @modeEcoActiveTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Mode éco activé'**
  String get modeEcoActiveTooltip;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle version de Privio est disponible.'**
  String get majDisponible;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Mettre à jour'**
  String get mettreAJour;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Mettez Privio à jour'**
  String get majRequiseTitre;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Cette version de Privio n’est plus prise en charge. Installez la nouvelle version pour continuer à échanger.'**
  String get majRequiseTexte;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Le lien de la nouvelle version n’est pas encore disponible. Réessayez un peu plus tard.'**
  String get majLienAbsent;

  /// Écran : ui/core/widgets/update_banner.dart
  ///
  /// In fr, this message translates to:
  /// **'Version installée : {version}'**
  String majVersionInstallee(String version);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Vérifié en personne'**
  String get verifieEnPersonne;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Vérifier en personne'**
  String get verifierEnPersonne;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Placez le code de vérification de votre contact dans le cadre'**
  String get verifyScanHint;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ce QR code n’est pas un code de vérification Privio.'**
  String get verifyScanInvalid;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'{name} utilise maintenant un nouveau téléphone.'**
  String verifyLapsedDevice(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'{name} a changé de numéro.'**
  String verifyLapsedPhone(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'{name} a changé de téléphone et de numéro.'**
  String verifyLapsedBoth(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Revérifiez en personne dès que possible.'**
  String get verifyAgainHint;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Revérifier'**
  String get verifyAgain;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Le {date}'**
  String verifiedOn(String date);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Est-ce bien {name} ?'**
  String verifyIntroTitle(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Retrouvez-vous face à face. L’un montre son code, l’autre le scanne : les deux téléphones verront « Vérifié en personne ».'**
  String get verifyIntroText;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Montrer mon code'**
  String get verifyShowMyCode;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Scanner son code'**
  String get verifyScanTheirCode;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Le badge disparaît si {name} se connecte sur un nouveau téléphone ou change de numéro.'**
  String verifyBadgeNote(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Montrez ce code à {name}'**
  String verifyShowTitle(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Code de vérification Privio'**
  String get verifyQrLabel;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Valable encore {time}'**
  String verifyValidFor(String time);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Sur le téléphone de {name} : votre fiche → Vérifier en personne → Scanner son code.'**
  String verifyShowHelp(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ce code a expiré.'**
  String get verifyExpired;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Nouveau code'**
  String get verifyNewCode;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Vous et {name} êtes vérifiés en personne'**
  String verifyDone(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Le badge « Vérifié en personne » apparaît sur vos deux téléphones.'**
  String get verifyDoneText;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Terminé'**
  String get verifyFinished;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Face à face, avec un QR code'**
  String get verifyRowHelp;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Vérification à refaire'**
  String get verifyToRedo;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Surnom privé'**
  String get surnomPrive;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Visible par vous seul, partout dans Privio. {name} ne le saura pas.'**
  String surnomPriveAide(String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un surnom, visible par vous seul'**
  String get ajouterSurnom;

  /// Fiche d’un contact ou d’un membre : surnom privé, puis vrai nom (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'{nickname} · {name}'**
  String surnomEtVraiNom(String nickname, String name);

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get retirer;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Surnom enregistré'**
  String get surnomEnregistre;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Surnom retiré'**
  String get surnomRetire;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'La vérification en personne se fait avec un contact.'**
  String get verifyNotContactError;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ce code a été créé pour une autre personne.'**
  String get verifyWrongPersonError;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ce code n’est pas valable.'**
  String get verifyCodeInvalidError;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Ce code a expiré. Demandez-en un nouveau.'**
  String get verifyCodeExpiredError;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Un surnom fait 40 caractères au plus.'**
  String get nicknameInvalidError;

  /// Écran : ui/features/conversations/verify_in_person.dart (lot 10.4)
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez pas donner de surnom à cette personne.'**
  String get nicknameNotAllowedError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Sondage'**
  String get sondage;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Nouveau sondage'**
  String get nouveauSondage;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Question'**
  String get sondageQuestion;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Choix {n}'**
  String sondageChoix(int n);

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un choix'**
  String get sondageAjouterChoix;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Plusieurs réponses'**
  String get sondagePlusieursReponses;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Vote anonyme'**
  String get sondageVoteAnonyme;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Votes visibles'**
  String get sondageVotesVisibles;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Chacun voit les totaux, personne ne voit qui a voté quoi.'**
  String get sondageVoteAnonymeAide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Les membres voient qui a choisi quoi.'**
  String get sondageVotesVisiblesAide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Le sondage s’efface avec les messages de la discussion. Vous pourrez le fermer à tout moment.'**
  String get sondageEphemereAide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Écrivez une question et au moins deux choix différents.'**
  String get sondageInvalide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{aucun vote} =1{1 vote} other{{count} votes}}'**
  String sondageVotes(int count);

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Personne n’a encore voté} =1{1 personne a voté} other{{count} personnes ont voté}}'**
  String sondageVotants(int count);

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Une seule réponse'**
  String get sondageUneReponse;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Plusieurs réponses possibles'**
  String get sondagePlusieursLabel;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Sondage fermé'**
  String get sondageFerme;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Fermer le sondage'**
  String get sondageFermer;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Plus personne ne pourra voter. Les résultats restent visibles jusqu’à l’effacement du sondage.'**
  String get sondageFermerConfirm;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Retirer mon vote'**
  String get sondageRetirerVote;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Voir les votes'**
  String get sondageVoirVotes;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'{who}📊 {question}'**
  String sondageApercu(String who, String question);

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Ce sondage n’est pas valable.'**
  String get pollInvalidError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Ce sondage est fermé.'**
  String get pollClosedError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Ce sondage n’existe plus.'**
  String get pollNotFoundError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Les sondages se font dans les groupes.'**
  String get pollGroupOnlyError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Dans un groupe d’annonces, seuls les administrateurs écrivent. Ce réglage ne change pas.'**
  String get announcementLockedError;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Type de groupe'**
  String get typeGroupe;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Discussion'**
  String get groupeDiscussion;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Tout le monde peut écrire.'**
  String get groupeDiscussionAide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Annonces'**
  String get groupeAnnonces;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs écrivent. Les membres réagissent et votent, sans voir les autres membres. Ce choix est définitif.'**
  String get groupeAnnoncesAide;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Groupe d’annonces : seuls les administrateurs écrivent. Vous pouvez réagir et voter.'**
  String get annoncesComposer;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Dans un groupe d’annonces, seuls les administrateurs voient la liste des membres.'**
  String get annoncesMembresCaches;

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Annonces · {members}'**
  String annoncesSousTitre(String members);

  /// Lot 10.5 : groupes « Annonces » et sondages
  ///
  /// In fr, this message translates to:
  /// **'Un membre'**
  String get unMembre;

  /// Lot 9.3 : vocaux et son des appels
  ///
  /// In fr, this message translates to:
  /// **'Écouter les vocaux avant de les envoyer'**
  String get vocalEcouterAvant;

  /// Lot 9.3 : vocaux et son des appels
  ///
  /// In fr, this message translates to:
  /// **'En levant le doigt, vous écoutez le vocal, puis vous l’envoyez ou le supprimez.'**
  String get vocalEcouterAvantOui;

  /// Lot 9.3 : vocaux et son des appels
  ///
  /// In fr, this message translates to:
  /// **'En levant le doigt, le vocal part tout de suite.'**
  String get vocalEcouterAvantNon;

  /// Lot 9.3 : vocaux et son des appels
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le vocal'**
  String get envoyerVocal;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Nouvel autocollant'**
  String get nouvelAutocollant;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'À partir d’une photo : le sujet est détouré sur votre téléphone.'**
  String get nouvelAutocollantAide;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Autocollant ajouté à vos autocollants'**
  String get autocollantAjoute;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Détourage…'**
  String get detourageEnCours;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Pincez et glissez pour recadrer.'**
  String get autocollantRecadrerAide;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Détourer le sujet'**
  String get detourerSujet;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Détourage impossible sur cette photo : recadrez-la.'**
  String get detourageImpossible;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Texte (facultatif)'**
  String get texteFacultatif;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Partageable'**
  String get autocollantPartageable;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Les personnes qui le reçoivent peuvent l’ajouter à leurs autocollants.'**
  String get autocollantPartageableOui;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Personne ne peut l’ajouter à ses autocollants.'**
  String get autocollantPartageableNon;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Mes autocollants'**
  String get mesAutocollants;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Autocollants Privio'**
  String get autocollantsPrivio;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Créer un autocollant'**
  String get creerAutocollant;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Retirer de mes autocollants'**
  String get retirerAutocollant;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Cet autocollant disparaîtra de vos autocollants. Les messages déjà envoyés ne changent pas.'**
  String get retirerAutocollantConfirm;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Autocollant retiré'**
  String get autocollantRetire;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Ajouter à mes autocollants'**
  String get ajouterAMesAutocollants;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Vous avez déjà 60 autocollants. Retirez-en un pour en ajouter.'**
  String get stickerLimitError;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Cet autocollant n’existe plus.'**
  String get stickerNotFoundError;

  /// Lot 7.4 : autocollants personnels
  ///
  /// In fr, this message translates to:
  /// **'Son auteur ne permet pas de l’ajouter à vos autocollants.'**
  String get stickerNotShareableError;

  /// Écran d’appel du téléphone (sans nom, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe Privio'**
  String get groupCallIncomingLocked;

  /// Écran d’appel du téléphone (sans nom, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe Privio'**
  String get groupCallVideoIncomingLocked;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe'**
  String get groupCallTitle;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe…'**
  String get groupCallIncoming;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe…'**
  String get groupCallVideoIncoming;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre'**
  String get groupCallJoin;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get groupCallLeave;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Vous'**
  String get groupCallMe;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'{count}/{max}'**
  String groupCallCount(int count, int max);

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Lancé par {name}'**
  String groupCallStartedBy(String name);

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 personne dans l’appel} other{{count} personnes dans l’appel}}'**
  String groupCallInCall(int count);

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe · {duration} · {count, plural, =1{1 personne} other{{count} personnes}}'**
  String groupCallBar(String duration, int count);

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe en cours · {count, plural, =1{1 personne} other{{count} personnes}}'**
  String groupCallOngoing(int count);

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Complet'**
  String get groupCallFullShort;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe'**
  String get groupCallButton;

  /// Écran : Appel de groupe (lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe'**
  String get groupCallVideoButton;

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe · {duration}'**
  String groupCallTrace(String duration);

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe · {duration}'**
  String groupCallTraceVideo(String duration);

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe sans réponse'**
  String get groupCallTraceNoAnswer;

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe sans réponse'**
  String get groupCallTraceVideoNoAnswer;

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel de groupe manqué de {name}'**
  String groupCallTraceMissed(String name);

  /// Écran : Discussion (trace d’appel de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Appel vidéo de groupe manqué de {name}'**
  String groupCallTraceVideoMissed(String name);

  /// Erreur (appels de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'L’appel est complet (8 personnes au plus).'**
  String get groupCallFullError;

  /// Erreur (appels de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Les appels de groupe se font dans un groupe.'**
  String get groupCallGroupOnlyError;

  /// Erreur (appels de groupe, lot 9.4)
  ///
  /// In fr, this message translates to:
  /// **'Les appels de groupe sont momentanément indisponibles. Réessayez plus tard.'**
  String get groupCallUnavailableError;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['dyu', 'fr', 'mos'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'dyu':
      return AppLocalizationsDyu();
    case 'fr':
      return AppLocalizationsFr();
    case 'mos':
      return AppLocalizationsMos();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
