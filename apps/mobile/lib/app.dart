import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/privio_theme.dart';
import 'data/services/device_services.dart';
import 'router/app_router.dart';
import 'state/data_providers.dart';
import 'state/messaging_providers.dart';
import 'state/privacy_providers.dart';
import 'ui/features/lock/app_lock_screens.dart';

class PrivioApp extends ConsumerWidget {
  const PrivioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Réseau (DATA-006, DATA-007) : coupure signalée aussitôt ; au retour, les envois en
    // attente partent et la liste se met à jour sans geste.
    ref.listen(netKindProvider, (previous, next) {
      final kind = next.value;
      if (kind == null) return;
      final offline = ref.read(offlineProvider.notifier);
      if (kind == NetKind.none) {
        offline.report(offline: true);
      } else if (previous?.value == NetKind.none || ref.read(offlineProvider)) {
        offline.report(offline: false);
        ref.invalidate(conversationsProvider);
      }
    });
    return MaterialApp.router(
      title: 'Privio',
      debugShowCheckedModeBanner: false,
      theme: PrivioTheme.light,
      darkTheme: PrivioTheme.dark,
      themeMode: ThemeMode.system,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      // Verrouillage (SEC-004) : recouvre tout, navigateur compris.
      builder: (context, child) =>
          AppLockGate(child: PresenceBeacon(child: child ?? const SizedBox.shrink())),
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
