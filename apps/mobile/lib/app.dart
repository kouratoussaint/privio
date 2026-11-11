import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/privio_theme.dart';
import 'router/app_router.dart';

class PrivioApp extends ConsumerWidget {
  const PrivioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Privio',
    debugShowCheckedModeBanner: false,
    theme: PrivioTheme.light,
    darkTheme: PrivioTheme.dark,
    themeMode: ThemeMode.system,
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(routerProvider),
  );
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
