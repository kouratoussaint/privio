import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../state/messaging_providers.dart';
import '../motion/motion.dart';

/// Lot 5.5 — message d'information écrit dans la console (« Maintenance ce soir à 22 h »),
/// en haut des listes Discussions et Groupes. Fermé, il ne revient que si le texte change.
class DismissedAnnouncement extends Notifier<String?> {
  @override
  String? build() => null;

  void dismiss(String text) => state = text;
}

final dismissedAnnouncementProvider = NotifierProvider<DismissedAnnouncement, String?>(
  DismissedAnnouncement.new,
);

class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appFeaturesProvider).announcement;
    final hidden = text.isEmpty || ref.watch(dismissedAnnouncementProvider) == text;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const amber = Color(0xFFB7700F);
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.enter,
      child: hidden
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.l,
                PrivioSpacing.s,
                PrivioSpacing.l,
                PrivioSpacing.xs,
              ),
              child: Material(
                key: const Key('announcement.banner'),
                color: amber.withValues(alpha: dark ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(PrivioRadius.large),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined, color: amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          key: const Key('announcement.text'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('announcement.close'),
                        tooltip: L.t.fermer,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () =>
                            ref.read(dismissedAnnouncementProvider.notifier).dismiss(text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
