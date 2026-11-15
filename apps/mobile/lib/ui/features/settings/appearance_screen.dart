import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/appearance_providers.dart';
import '../../core/widgets/settings_card.dart';

/// Lot 8.1a — Apparence : thème clair, sombre ou automatique ; taille du texte.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider).value ?? const Appearance();
    final ctl = ref.read(appearanceProvider.notifier);
    return Scaffold(
      key: const Key('appearance.screen'),
      appBar: AppBar(title: Text(L.t.apparence)),
      body: SettingsListView(
        children: [
          SettingsSectionTitle(L.t.theme, first: true),
          SettingsCard(
            children: [
              RadioGroup<String>(
                groupValue: look.theme,
                onChanged: (v) {
                  if (v != null) ctl.setTheme(v);
                },
                child: Column(
                  children: [
                    for (final e in Appearance.themeLabels.entries)
                      RadioListTile<String>(
                        key: Key('appearance.theme.${e.key}'),
                        value: e.key,
                        title: Text(e.value),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.tailleTexte),
          SettingsCard(
            children: [
              RadioGroup<String>(
                groupValue: look.textSize,
                onChanged: (v) {
                  if (v != null) ctl.setTextSize(v);
                },
                child: Column(
                  children: [
                    for (final e in Appearance.textLabels.entries)
                      RadioListTile<String>(
                        key: Key('appearance.size.${e.key}'),
                        value: e.key,
                        title: Text(e.value),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.l),
          const _Preview(),
          SettingsNote(L.t.tailleChoisieAjouteCelleReglee),
        ],
      ),
    );
  }
}

/// Aperçu d'une discussion avec la taille et le thème choisis.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    Widget bubble(String text, {required bool out}) => Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: out ? p.bubbleOut : p.bubbleIn,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(color: out ? p.onBubbleOut : p.onBubbleIn),
        ),
      ),
    );
    return Container(
      key: const Key('appearance.preview'),
      padding: const EdgeInsets.all(PrivioSpacing.m),
      decoration: BoxDecoration(
        color: p.chatBackground,
        borderRadius: BorderRadius.circular(PrivioRadius.large),
      ),
      child: Column(
        children: [
          bubble(L.t.bonjourOnSeVoitDemain, out: false),
          bubble(L.t.ouiVers10H, out: true),
        ],
      ),
    );
  }
}
