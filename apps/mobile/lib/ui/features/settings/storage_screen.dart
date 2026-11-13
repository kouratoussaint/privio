import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
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
        title: const Text('Effacer les médias gardés ?'),
        content: const Text(
          'Les photos et vocaux gardés sur ce téléphone sont effacés. Tant que les messages '
          'n\'ont pas expiré, vous pourrez les télécharger de nouveau (cela consomme des données). '
          'Les envois en attente sont conservés.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('storage.clear.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref.read(localCacheProvider).clearMedia();
    ref.invalidate(mediaUsageProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0 ? 'Rien à effacer.' : '$n fichier${n > 1 ? 's' : ''} effacé${n > 1 ? 's' : ''}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final mode = ref.watch(photoAutoDownloadProvider).value ?? PhotoAutoDownload.always;
    final usage = ref.watch(dataUsageProvider).value;
    final space = ref.watch(mediaUsageProvider);

    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.xs,
      ),
      child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: p.accentText)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Stockage et données')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xl),
        children: [
          title('Téléchargement automatique des photos'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text(
              'Sans téléchargement automatique, une photo reçue s\'affiche en attente : '
              'touchez-la pour la télécharger. Les vocaux ne se téléchargent que lorsque vous '
              'les écoutez. Vos propres envois ne sont jamais retéléchargés.',
              style: muted,
            ),
          ),
          const Divider(height: PrivioSpacing.xxl),
          title('Données utilisées par les médias'),
          if (usage != null) ...[
            ListTile(
              key: const Key('storage.usage.month'),
              leading: Icon(Icons.swap_vert, color: p.accentText),
              title: const Text('Ce mois-ci'),
              subtitle: Text(
                'Reçu ${formatBytes(usage.received(usage.month))} · '
                'envoyé ${formatBytes(usage.sent(usage.month))}',
              ),
            ),
            ListTile(
              key: const Key('storage.usage.previous'),
              leading: Icon(Icons.history, color: p.accentText),
              title: const Text('Mois précédent'),
              subtitle: Text(
                'Reçu ${formatBytes(usage.received(usage.previousMonth))} · '
                'envoyé ${formatBytes(usage.sent(usage.previousMonth))}',
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text(
              'Photos, vocaux et photos de profil échangés depuis ce téléphone. Les messages '
              'texte, très légers, ne sont pas comptés. Chiffres indicatifs : votre opérateur '
              'fait foi.',
              style: muted,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.s),
              child: TextButton(
                key: const Key('storage.usage.reset'),
                onPressed: () => ref.read(dataUsageProvider.notifier).reset(),
                child: const Text('Remettre les compteurs à zéro'),
              ),
            ),
          ),
          const Divider(height: PrivioSpacing.xl),
          title('Espace sur ce téléphone'),
          ListTile(
            key: const Key('storage.space'),
            leading: Icon(Icons.sd_storage_outlined, color: p.accentText),
            title: const Text('Médias gardés (chiffrés)'),
            subtitle: Text(switch (space) {
              AsyncData(:final value) =>
                '${value.files} fichier${value.files > 1 ? 's' : ''} · ${formatBytes(value.bytes)}',
              AsyncError() => 'Indisponible',
              _ => 'Calcul…',
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text(
              'Chaque média est effacé automatiquement à l\'expiration de son message.',
              style: muted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            child: OutlinedButton.icon(
              key: const Key('storage.clear'),
              onPressed: () => _clear(context, ref),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Effacer les médias gardés'),
            ),
          ),
        ],
      ),
    );
  }
}
