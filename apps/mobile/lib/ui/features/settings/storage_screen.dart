import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../core/widgets/settings_card.dart';
import '../../../state/data_providers.dart';
import '../../../state/providers.dart';

/// Place occupée par les médias gardés (chiffrés) sur ce téléphone.
final mediaUsageProvider = FutureProvider.autoDispose<({int files, int bytes})>(
  (ref) => ref.read(localCacheProvider).mediaUsage(),
);

/// Écran 25 — stockage et économie de données (DATA-001, 003, 008, 009).
class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.effacerPhotosVocauxGardes),
        content: Text(L.t.photosVocauxGardesSurCe),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('storage.clear.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.effacer),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref.read(localCacheProvider).clearMedia();
    ref.invalidate(mediaUsageProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(n == 0 ? L.t.rienEffacer : L.t.filesErased(n))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final mode = ref.watch(photoAutoDownloadProvider).value ?? PhotoAutoDownload.always;
    final usage = ref.watch(dataUsageProvider).value;
    final space = ref.watch(mediaUsageProvider);

    return Scaffold(
      appBar: AppBar(title: Text(L.t.stockageDonnees)),
      body: SettingsListView(
        children: [
          SettingsSectionTitle(L.t.telechargementAutomatiquePhotos, first: true),
          SettingsCard(
            children: [
              RadioGroup<PhotoAutoDownload>(
                groupValue: mode,
                onChanged: (v) {
                  if (v != null) ref.read(photoAutoDownloadProvider.notifier).set(v);
                },
                child: Column(
                  children: [
                    for (final m in PhotoAutoDownload.values)
                      RadioListTile<PhotoAutoDownload>(
                        key: Key('storage.auto.${m.id}'),
                        value: m,
                        title: Text(m.label),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SettingsNote(L.t.sansTelechargementAutomatiquePhotoRecue),
          SettingsSectionTitle(L.t.donneesUtiliseesParPhotosVocaux),
          SettingsCard(
            children: [
              if (usage != null) ...[
                ListTile(
                  key: const Key('storage.usage.month'),
                  leading: Icon(Icons.swap_vert, color: p.accentText),
                  title: Text(L.t.ceMoisCi),
                  subtitle: Text(
                    L.t.recuMonthEnvoyeMonth2(
                      formatBytes(usage.received(usage.month)),
                      formatBytes(usage.sent(usage.month)),
                    ),
                  ),
                ),
                ListTile(
                  key: const Key('storage.usage.previous'),
                  leading: Icon(Icons.history, color: p.accentText),
                  title: Text(L.t.moisPrecedent),
                  subtitle: Text(
                    L.t.recuPreviousmonthEnvoyePreviousmonth2(
                      formatBytes(usage.received(usage.previousMonth)),
                      formatBytes(usage.sent(usage.previousMonth)),
                    ),
                  ),
                ),
                const SettingsDivider(),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.s),
                  child: TextButton(
                    key: const Key('storage.usage.reset'),
                    onPressed: () => ref.read(dataUsageProvider.notifier).reset(),
                    child: Text(L.t.remettreCompteursZero),
                  ),
                ),
              ),
            ],
          ),
          SettingsNote(L.t.photosVocauxPhotosProfilEchanges),
          SettingsSectionTitle(L.t.espaceSurCeTelephone),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('storage.space'),
                leading: Icon(Icons.sd_storage_outlined, color: p.accentText),
                title: Text(L.t.photosVocauxSurCeTelephone),
                subtitle: Text(switch (space) {
                  AsyncData(:final value) => L.t.filesSize(value.files, formatBytes(value.bytes)),
                  AsyncError() => L.t.indisponible,
                  _ => L.t.calcul,
                }),
              ),
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: OutlinedButton.icon(
                  key: const Key('storage.clear'),
                  onPressed: () => _clear(context, ref),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(L.t.effacerPhotosVocauxGardes2),
                ),
              ),
            ],
          ),
          SettingsNote(L.t.chaquePhotoOuVocalEfface),
        ],
      ),
    );
  }
}
