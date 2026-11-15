import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../state/appearance_providers.dart';
import '../../core/widgets/settings_card.dart';

/// Lot 8.2a — Paramètres → Langue. Seules les langues dont les textes P1 sont traduits et
/// relus sont proposées ; les autres apparaissent grisées (« Traduction en cours »).
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider).value?.language ?? 'fr';
    final released = ref.watch(releasedLanguagesProvider);
    return Scaffold(
      key: const Key('language.screen'),
      appBar: AppBar(title: Text(L.t.languageTitle)),
      body: SettingsListView(
        children: [
          SettingsCard(
            children: [
              RadioGroup<String>(
                groupValue: current,
                onChanged: (v) {
                  if (v != null) ref.read(appearanceProvider.notifier).setLanguage(v);
                },
                child: Column(
                  children: [
                    for (final e in kLanguages.entries)
                      RadioListTile<String>(
                        key: Key('language.${e.key}'),
                        value: e.key,
                        enabled: released.contains(e.key),
                        title: Text(e.value),
                        subtitle: released.contains(e.key) ? null : Text(L.t.languageInProgress),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SettingsNote(L.t.languageNote),
        ],
      ),
    );
  }
}

/// Choix de la langue sur l'écran de bienvenue (affiché seulement s'il y a un choix).
class LanguageChip extends ConsumerWidget {
  const LanguageChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final released = ref.watch(releasedLanguagesProvider);
    if (released.length < 2) return const SizedBox.shrink();
    final current = ref.watch(appearanceProvider).value?.language ?? 'fr';
    return Align(
      alignment: Alignment.topRight,
      child: TextButton.icon(
        key: const Key('language.chip'),
        icon: const Icon(Icons.translate_rounded),
        label: Text(L.t.languageChip(kLanguages[current] ?? current)),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) {
                Navigator.pop(ctx);
                if (v != null) ref.read(appearanceProvider.notifier).setLanguage(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final code in released)
                    RadioListTile<String>(
                      key: Key('language.sheet.$code'),
                      value: code,
                      title: Text(kLanguages[code] ?? code),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
