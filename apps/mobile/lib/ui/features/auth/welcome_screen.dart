import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/privio_theme.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../router/routes.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/privio_brand.dart';
import '../../core/widgets/state_views.dart';

/// Écran 03 — un seul choix : le numéro de téléphone (aucune option e-mail).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(sessionControllerProvider).value?.notice;
    return Theme(
      data: PrivioTheme.entry,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: FlowLayout(
              bottom: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const Key('welcome.phone'),
                    onPressed: () => context.push(Routes.phone),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Continuer avec mon numéro de téléphone'),
                  ),
                  const SizedBox(height: PrivioSpacing.s),
                  Text(
                    'Un code de vérification vous sera envoyé par SMS.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              children: [
                if (notice != null) ...[
                  NoticeBanner(
                    message: notice,
                    onClose: () => ref.read(sessionControllerProvider.notifier).clearNotice(),
                  ),
                  const SizedBox(height: PrivioSpacing.l),
                ],
                const SizedBox(height: PrivioSpacing.xxl),
                const Center(child: PrivioSymbol(size: 128)),
                const SizedBox(height: PrivioSpacing.l),
                const Center(child: PrivioWordmark()),
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  'Messagerie privée et éphémère',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
