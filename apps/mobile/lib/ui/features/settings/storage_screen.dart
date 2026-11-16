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

const _ecoGreen = Color(0xFF2E9D5B);

String _kindLabel(String k) => switch (k) {
  'photo' => L.t.photos,
  'voice' => L.t.messagesVocaux,
  'gif' => 'GIF',
  'call' => L.t.appels,
  _ => L.t.autres,
};

/// Écran 25 — stockage et économie de données (DATA-001, 003, 008, 009).
/// Lot 10.3 : Mode éco et consommation détaillée.
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
    final eco = ref.watch(ecoOnProvider);

    return Scaffold(
      appBar: AppBar(title: Text(L.t.stockageDonnees)),
      body: SettingsListView(
        children: [
          // Lot 10.3 : Mode éco, tout en haut.
          SettingsSectionTitle(L.t.modeEco, first: true),
          SettingsCard(
            children: [
              SwitchListTile(
                key: const Key('storage.eco'),
                secondary: Icon(Icons.eco_outlined, color: eco ? _ecoGreen : p.accentText),
                title: Text(L.t.modeEco),
                subtitle: Text(eco ? L.t.modeEcoActif : L.t.modeEcoInactif),
                value: eco,
                onChanged: (v) => ref.read(ecoModeProvider.notifier).set(v),
              ),
            ],
          ),
          SettingsNote(L.t.modeEcoDetail),
          // Lot 10.3 : consommation du mois en haut, par type, et ce que le Mode éco a évité.
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
                for (final k in kUsageKinds)
                  if (usage.ofKind(usage.month, k) > 0)
                    ListTile(
                      key: Key('storage.usage.kind.$k'),
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 72, right: PrivioSpacing.l),
                      title: Text(_kindLabel(k)),
                      trailing: Text(formatBytes(usage.ofKind(usage.month, k))),
                    ),
                if (usage.saved(usage.month) > 0)
                  ListTile(
                    key: const Key('storage.usage.saved'),
                    leading: const Icon(Icons.eco, color: _ecoGreen),
                    title: Text(L.t.economiseCeMois),
                    subtitle: Text(L.t.estimationModeEco),
                    trailing: Text(
                      formatBytes(usage.saved(usage.month)),
                      style: const TextStyle(color: _ecoGreen, fontWeight: FontWeight.w700),
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
          SettingsSectionTitle(L.t.telechargementAutomatiquePhotos),
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
                        enabled: !eco,
                      ),
                  ],
                ),
              ),
            ],
          ),
          SettingsNote(
            eco ? L.t.modeEcoPhotosAuToucher : L.t.sansTelechargementAutomatiquePhotoRecue,
          ),
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
