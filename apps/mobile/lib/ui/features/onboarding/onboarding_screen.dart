import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_theme.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/state_views.dart';
import '../../core/motion/illustrations.dart';
import '../settings/language_screen.dart';

/// Écran 02 — engagements affichés (formulation validée A2, voir docs/adr/ADR-002) :
/// aucune promesse de chiffrement côté serveur ni de protection absolue contre les captures.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static List<(IconData, String, String)> get commitments => [
    (
      Icons.timer_outlined,
      L.t.messagesQuiDisparaissent,
      // typo-fr: ignore-next (engagements validés A2, inchangés)
      L.t.chaqueMessageEstEffaceAutomatiquement,
    ),
    (Icons.lock_outline, L.t.protegesPendantLeurTransport, L.t.vosMessagesCirculentParConnexion),
    (
      Icons.block,
      L.t.pasTransfertNiCopie,
      // typo-fr: ignore-next (engagements validés A2, inchangés)
      L.t.messagesNePeuventEtreNi,
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
    return Theme(
      data: PrivioTheme.entry,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: FlowLayout(
              bottom: FilledButton(
                key: const Key('onboarding.continue'),
                onPressed: _accepted && !_busy ? _continue : null,
                child: Text(L.t.continuer),
              ),
              children: [
                // Lot 8.2a : choix de la langue dès le premier écran.
                const LanguageChip(),
                const SizedBox(height: PrivioSpacing.xl),
                const Center(child: AnimatedLogo(size: 80)),
                Text(
                  L.t.bienvenueSurPrivio,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  L.t.messageriePriveeOuMessagesEffacent,
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
                          // Lot 7.2b2 : chaque engagement a son icône animée.
                          FloatingIcon(
                            icon: icon,
                            size: 22,
                            motion: switch (icon) {
                              Icons.timer_outlined => IconMotion.vanish,
                              Icons.lock_outline => IconMotion.pulse,
                              _ => IconMotion.float,
                            },
                          ),
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
                  // typo-fr: ignore-next (engagements validés A2, inchangés)
                  title: Text(L.t.jAiLuComprisCes),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
