import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du projet « privio-e1ef4 » (application Android com.privio.app).
///
/// Ces identifiants ne sont PAS des secrets : ils figurent dans tout APK et identifient
/// seulement le projet. La protection repose sur la restriction de la clé d'API dans la
/// console Google Cloud (application Android com.privio.app + empreinte SHA-256 de la clé
/// de signature) — voir docs/adr/ADR-011. Aucun secret serveur (compte de service FCM)
/// n'est jamais dans l'application.
const privioFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCLo8EaEeMISl5ZMO2JQLqfwBIrkjFQxuQ',
  appId: '1:1038472124226:android:8280b53240d3cde49adadb',
  messagingSenderId: '1038472124226',
  projectId: 'privio-e1ef4',
  storageBucket: 'privio-e1ef4.firebasestorage.app',
);
