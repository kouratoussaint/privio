import 'l10n/l10n.dart';

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'core/config/env.dart';
import 'core/diagnostics/tech_log.dart';
import 'data/services/device_info.dart';
import 'data/storage/secure_session_storage.dart';
import 'data/services/call_background.dart';
import 'ui/core/emoji/big_emojis.dart';

import 'package:flutter/foundation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(ConfigErrorApp(reason: L.t.configurationAbsenteCompilezAvecDart));
    return;
  }
  if (Env.publishableKeyLooksSecret) {
    runApp(ConfigErrorApp(reason: L.t.cleRefuseeCleSecreteSupabase));
    return;
  }

  // Lot 6.1 : journal technique local (sans contenu ni nom), joint seulement avec
  // l'accord de la personne à une demande d'assistance.
  final techLog = TechLog.instance;
  await techLog.load();
  techLog.install();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  final client = Supabase.instance.client;

  // Lot 8.5b : crédit des émojis animés intégrés (licence CC BY 4.0).
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(['Noto Animated Emoji'], kNotoAnimatedEmojiCredit),
    ),
  );

  // Lot 9.1b : appels reçus Privio fermé (message de réveil, écran d'appel du téléphone).
  if (Platform.isAndroid) {
    FirebaseMessaging.onBackgroundMessage(privioBackgroundMessage);
    try {
      await FlutterCallkitIncoming.onBackgroundMessage(privioCallkitBackground);
    } on Object {
      // Sans écran d'appel du téléphone, les appels sonnent Privio ouvert.
    }
  }

  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [...privioServerOverrides(client), ...privioDeviceOverrides()],
      child: const PrivioApp(),
    ),
  );
  unawaited(_noterDemarrage(techLog));
}

/// Lot 6.1 : durée du démarrage à froid (lancement du processus → premier écran dessiné),
/// notée au journal technique et dans le journal d'Android (mesurée par la CI).
Future<void> _noterDemarrage(TechLog techLog) async {
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  final ms = await millisecondsSinceProcessStart();
  final d = await const PlatformDeviceInfo().read();
  techLog.started(appVersion: Env.appVersion, android: d.osVersion, model: d.model, startupMs: ms);
  if (ms != null) debugPrint('Privio — démarrage : $ms ms');
}
