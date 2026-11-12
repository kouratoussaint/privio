import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/realtime_service.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/brand_scaffold.dart';

/// Écran 22 — paramètres (design lot 2.D) : profil, confidentialité, appareil, déconnexion.
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
    final p = PrivioPalette.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final profile = account?.profile;
    final blockedCount = ref.watch(blockedUsersProvider).value?.length;
    final secondary = theme.colorScheme.onSurfaceVariant;

    return BrandScaffold(
      title: const Text('Paramètres'),
      body: ColoredBox(
        color: theme.colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.l,
            PrivioSpacing.xl,
            PrivioSpacing.l,
            PrivioSpacing.xl,
          ),
          children: [
            if (profile != null)
              _Card(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(PrivioSpacing.l),
                    child: Row(
                      children: [
                        InitialAvatar(name: profile.displayName, seed: account!.userId, radius: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile.displayName, style: theme.textTheme.titleMedium),
                              Text(
                                '@${profile.handle}',
                                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
                              ),
                              if (account.phoneE164 != null)
                                Text(
                                  PhoneNumber.format(account.phoneE164!),
                                  style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const _SectionTitle('Confidentialité'),
            _Card(
              children: [
                SwitchListTile(
                  key: const Key('settings.discoverable'),
                  value: account?.phoneDiscoverable ?? false,
                  onChanged: account == null ? null : (v) => _toggleDiscoverable(context, ref, v),
                  secondary: Icon(Icons.phone_outlined, color: p.accentText),
                  title: const Text('Me trouver par mon numéro'),
                  subtitle: Text(
                    profile == null
                        ? 'Désactivé par défaut.'
                        : 'Désactivé par défaut : on vous trouve par votre identifiant @${profile.handle}.',
                  ),
                ),
                const _Divider(),
                ListTile(
                  key: const Key('settings.blocked'),
                  leading: Icon(Icons.block, color: p.accentText),
                  title: const Text('Personnes bloquées'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (blockedCount != null)
                        Text(
                          '$blockedCount',
                          style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
                        ),
                      const SizedBox(width: PrivioSpacing.xs),
                      Icon(Icons.chevron_right, color: secondary),
                    ],
                  ),
                  onTap: () => context.push(Routes.blockedUsers),
                ),
              ],
            ),
            const _SectionTitle('Ce téléphone'),
            _Card(
              children: [
                ValueListenableBuilder<RealtimeStatus>(
                  valueListenable: ref.watch(realtimeStatusProvider).status,
                  builder: (_, status, _) {
                    final ok = status.state == RealtimeState.connected;
                    final color = ok
                        ? p.success
                        : (status.state == RealtimeState.error ? p.warn : secondary);
                    return ListTile(
                      key: const Key('settings.realtime'),
                      leading: Icon(Icons.sync, color: p.accentText),
                      title: const Text('Réception instantanée'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              status.label,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const _Divider(),
                ListTile(
                  leading: Icon(Icons.phone_android, color: p.accentText),
                  title: const Text('Seul appareil connecté'),
                  subtitle: const Text('Une connexion sur un autre téléphone déconnecte celui-ci.'),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.l),
            _Card(
              children: [
                ListTile(
                  key: const Key('settings.help'),
                  leading: Icon(Icons.help_outline, color: p.accentText),
                  title: const Text('Aide et assistance'),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.help),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.l),
            _Card(
              children: [
                ListTile(
                  key: const Key('settings.signout'),
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    'Se déconnecter',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  ),
                  onTap: () => _confirmSignOut(context, ref),
                ),
                const _Divider(),
                ListTile(
                  key: const Key('settings.delete'),
                  leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                  title: Text(
                    'Supprimer mon compte',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  ),
                  onTap: () => context.push(Routes.deleteAccount),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.xl),
            Text(
              'Privio ${ref.watch(appVersionProvider)} · Messagerie privée et éphémère',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PrivioSpacing.xs,
      PrivioSpacing.xl,
      PrivioSpacing.xs,
      PrivioSpacing.s,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? p.field : p.sheet,
        borderRadius: BorderRadius.circular(PrivioRadius.large),
        border: Border.all(color: p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(indent: 56, height: 1);
}
