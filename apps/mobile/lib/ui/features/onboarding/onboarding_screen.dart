import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/privio_brand.dart';
import '../../core/widgets/state_views.dart';

/// Écran 02 — engagements affichés (formulation validée A2, voir docs/adr/ADR-002) :
/// aucune promesse de chiffrement côté serveur ni de protection absolue contre les captures.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const commitments = [
    (
      Icons.timer_outlined,
      'Des messages qui disparaissent',
      'Chaque message est effacé automatiquement 72 heures après son envoi, '
          'qu\'il ait été lu ou non.',
    ),
    (
      Icons.lock_outline,
      'Protégés pendant leur transport',
      'Vos messages circulent par une connexion chiffrée entre votre téléphone '
          'et les serveurs de Privio.',
    ),
    (
      Icons.block,
      'Pas de transfert ni de copie',
      'Les messages ne peuvent être ni transférés, ni copiés, ni enregistrés dans la '
          'galerie. Les captures d\'écran sont bloquées sur Android ; une photo prise '
          'avec un autre appareil reste toutefois possible.',
    ),
  ];

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _accepted = false;
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: FlowLayout(
        bottom: FilledButton(
          key: const Key('onboarding.continue'),
          onPressed: _accepted && !_busy ? _continue : null,
          child: const Text('Continuer'),
        ),
        children: [
          const SizedBox(height: PrivioSpacing.xl),
          const Center(child: PrivioSymbol(size: 88)),
          const SizedBox(height: PrivioSpacing.l),
          Text(
            'Bienvenue sur Privio',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            'Une messagerie privée et éphémère. Voici ce que Privio fait pour vous :',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.xl),
          for (final (icon, title, body) in OnboardingScreen.commitments) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: PrivioSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: PrivioSpacing.xs),
                          Text(body, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: PrivioSpacing.m),
          ],
          CheckboxListTile(
            key: const Key('onboarding.consent'),
            value: _accepted,
            onChanged: (v) => setState(() => _accepted = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('J\'ai lu et compris ces engagements.'),
          ),
        ],
      ),
    );
  }
}
