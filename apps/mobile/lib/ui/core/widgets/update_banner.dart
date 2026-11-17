import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import '../motion/motion.dart';

/// Lot 5.7 — bandeau « Mise à jour disponible » fermé pour la session en cours (il revient
/// au prochain lancement tant que la version reste sous la version conseillée).
class DismissedUpdate extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final dismissedUpdateProvider = NotifierProvider<DismissedUpdate, bool>(DismissedUpdate.new);

Future<void> _openUpdate(WidgetRef ref, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  await ref.read(openExternalUrlProvider)(uri);
}

/// En haut des listes Discussions et Groupes, sous le message d'information.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    final hidden = update.level != UpdateLevel.recommended || ref.watch(dismissedUpdateProvider);
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
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
                key: const Key('update.banner'),
                color: theme.colorScheme.primary.withValues(alpha: dark ? 0.24 : 0.1),
                borderRadius: BorderRadius.circular(PrivioRadius.large),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: p.accentText),
                      const SizedBox(width: 12),
                      Expanded(child: Text(L.t.majDisponible, style: theme.textTheme.bodyMedium)),
                      if (update.url.isNotEmpty)
                        TextButton(
                          key: const Key('update.banner.open'),
                          onPressed: () => unawaited(_openUpdate(ref, update.url)),
                          child: Text(L.t.mettreAJour),
                        ),
                      IconButton(
                        key: const Key('update.banner.close'),
                        tooltip: L.t.fermer,
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => ref.read(dismissedUpdateProvider.notifier).dismiss(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Recouvre l'application quand la version installée est sous la version minimale : seule
/// la mise à jour reste possible. Les réglages sont relus au retour dans l'app et par
/// « Réessayer ».
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    if (update.level != UpdateLevel.required) return child;
    return Stack(
      children: [
        ExcludeSemantics(child: IgnorePointer(child: child)),
        Positioned.fill(
          child: Material(
            child: _UpdateRequiredView(url: update.url, version: ref.watch(appVersionProvider)),
          ),
        ),
      ],
    );
  }
}

class _UpdateRequiredView extends ConsumerWidget {
  const _UpdateRequiredView({required this.url, required this.version});

  final String url;
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PrivioSpacing.xl),
          child: Column(
            key: const Key('update.required'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.system_update_rounded, size: 44, color: p.accentText),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              Text(
                L.t.majRequiseTitre,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PrivioSpacing.m),
              Text(
                url.isEmpty ? L.t.majLienAbsent : L.t.majRequiseTexte,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PrivioSpacing.s),
              Text(
                L.t.majVersionInstallee(version),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              if (url.isNotEmpty)
                FilledButton.icon(
                  key: const Key('update.required.open'),
                  onPressed: () => unawaited(_openUpdate(ref, url)),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(L.t.mettreAJour),
                ),
              TextButton(
                key: const Key('update.required.retry'),
                onPressed: () => ref.invalidate(messagingRulesProvider),
                child: Text(L.t.reessayer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
