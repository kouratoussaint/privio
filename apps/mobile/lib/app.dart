import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/privio_theme.dart';
import 'data/services/device_services.dart';
import 'router/app_router.dart';
import 'state/data_providers.dart';
import 'state/messaging_providers.dart';
import 'state/privacy_providers.dart';
import 'ui/features/moderation/moderation_gate.dart';
import 'ui/features/lock/app_lock_screens.dart';
import 'state/feedback_providers.dart';
import 'state/appearance_providers.dart';
import 'l10n/l10n.dart';

class PrivioApp extends ConsumerWidget {
  const PrivioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lot 7.2b2 : réglage « Sons et vibrations » lu dès le démarrage.
    ref.listen(soundsEnabledProvider, (_, _) {});
    // Réseau (DATA-006, DATA-007) : coupure signalée aussitôt ; au retour, les envois en
    // attente partent et la liste se met à jour sans geste.
    ref.listen(netKindProvider, (previous, next) {
      final kind = next.value;
      if (kind == null) return;
      final offline = ref.read(offlineProvider.notifier);
      if (kind == NetKind.none) {
        // Le téléphone annonce lui-même qu'il n'a plus de réseau : signalé tout de suite.
        offline.report(offline: true, certain: true);
      } else if (previous?.value == NetKind.none || ref.read(offlineProvider)) {
        offline.report(offline: false);
        ref.invalidate(conversationsProvider);
      }
    });
    // Lot 8.1a : thème et taille du texte choisis dans Paramètres → Apparence.
    final look = ref.watch(appearanceProvider).value ?? const Appearance();
    // Lot 8.2a : langue choisie (français par défaut) ; textes accessibles via L.t.
    final locale = Locale(look.language);
    L.use(locale);
    return MaterialApp.router(
      title: 'Privio',
      debugShowCheckedModeBanner: false,
      theme: PrivioTheme.light,
      darkTheme: PrivioTheme.dark,
      themeMode: look.themeMode,
      locale: locale,
      supportedLocales: [for (final code in kLanguages.keys) Locale(code)],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        FallbackLocalizationsDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
        FallbackLocalizationsDelegate<CupertinoLocalizations>(
          GlobalCupertinoLocalizations.delegate,
        ),
        FallbackLocalizationsDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
      ],
      routerConfig: ref.watch(routerProvider),
      // Verrouillage (SEC-004) : recouvre tout, navigateur compris.
      // Modération (lot 5.3) : compte suspendu ou avertissement, sous le verrouillage.
      builder: (context, child) {
        // Lot 8.2a : changer de langue reconstruit tous les écrans (textes lus via L.t).
        final app = KeyedSubtree(
          key: ValueKey(look.language),
          child: AppLockGate(
            child: ModerationGate(child: PresenceBeacon(child: child ?? const SizedBox.shrink())),
          ),
        );
        if (look.textFactor == 1.0) return app;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(media.textScaler.scale(1) * look.textFactor),
          ),
          child: app,
        );
      },
    );
  }
}

/// Affiché si la configuration de compilation est absente ou dangereuse.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: PrivioTheme.light,
    darkTheme: PrivioTheme.dark,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(reason, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
}
