import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../router/routes.dart';
import '../../../data/services/realtime_service.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';

/// Écran 22 (version étape 1) : profil, découvrabilité par numéro, appareil, déconnexion.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous devrez recevoir un nouveau code SMS pour vous reconnecter.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('settings.signout.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionControllerProvider.notifier).signOut();
  }

  Future<void> _toggleDiscoverable(BuildContext context, WidgetRef ref, bool value) async {
    try {
      await ref.read(sessionControllerProvider.notifier).setPhoneDiscoverable(value);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final profile = account?.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        children: [
          if (profile != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(profile.displayName.characters.first.toUpperCase()),
                ),
                title: Text(profile.displayName),
                subtitle: Text(
                  '@${profile.handle}'
                  '${account?.phoneE164 == null ? '' : '\n${PhoneNumber.format(account!.phoneE164!)}'}',
                ),
                isThreeLine: account?.phoneE164 != null,
              ),
            ),
          const SizedBox(height: PrivioSpacing.l),
          Text('Confidentialité', style: theme.textTheme.titleSmall),
          SwitchListTile(
            key: const Key('settings.discoverable'),
            value: account?.phoneDiscoverable ?? false,
            onChanged: account == null ? null : (v) => _toggleDiscoverable(context, ref, v),
            title: const Text('Me trouver par mon numéro'),
            subtitle: const Text(
              'Les personnes qui connaissent votre numéro pourront vous trouver. '
              'Désactivé par défaut ; votre identifiant Privio suffit pour être trouvé.',
            ),
          ),
          ListTile(
            key: const Key('settings.blocked'),
            leading: const Icon(Icons.block),
            title: const Text('Personnes bloquées'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.blockedUsers),
          ),
          const Divider(),
          Text('Appareil', style: theme.textTheme.titleSmall),
          ValueListenableBuilder<RealtimeStatus>(
            valueListenable: ref.watch(realtimeStatusProvider).status,
            builder: (_, status, _) => ListTile(
              key: const Key('settings.realtime'),
              leading: const Icon(Icons.sync),
              title: const Text('Réception instantanée'),
              subtitle: Text(status.label),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('Ce téléphone'),
            subtitle: Text(
              'Privio n\'est ouvert que sur un seul téléphone à la fois. Une connexion '
              'sur un autre appareil déconnecte celui-ci.',
            ),
          ),
          const Divider(),
          ListTile(
            key: const Key('settings.signout'),
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Se déconnecter',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmSignOut(context, ref),
          ),
          const SizedBox(height: PrivioSpacing.xl),
          Text(
            'Privio ${ref.watch(appVersionProvider)}',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
