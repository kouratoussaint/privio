import '../../../state/data_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/reactions.dart';
import '../../../data/services/photo_picker.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import '../../../state/push_providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/avatar.dart';
import '../lock/app_lock_screens.dart' show delayLabel;
import '../../core/widgets/brand_scaffold.dart';

/// Écran 22 — paramètres (design lot 2.D) : profil, confidentialité, appareil, déconnexion.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter\u202F?'),
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

  Future<void> _chooseQuickReaction(BuildContext context, WidgetRef ref) async {
    final current = ref.read(quickReactionProvider).value ?? '❤️';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.l),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: PrivioSpacing.s,
            children: [
              for (final e in kQuickReactions)
                ChoiceChip(
                  key: Key('quick.$e'),
                  selected: e == current,
                  label: Text(e, style: const TextStyle(fontSize: 22)),
                  onSelected: (_) => Navigator.pop(ctx, e),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await ref.read(quickReactionProvider.notifier).set(picked);
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

  /// Photo de profil : prendre, choisir ou retirer. Préparée sur le téléphone (carrée,
  /// sans métadonnées), vérifiée et nettoyée encore par le serveur.
  Future<void> _editAvatar(BuildContext context, WidgetRef ref, {required bool hasAvatar}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('avatar.camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              key: const Key('avatar.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasAvatar)
              ListTile(
                key: const Key('avatar.remove'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(
                  'Retirer la photo',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(accountApiProvider);
      if (choice == 'remove') {
        await api.removeAvatar();
      } else {
        final source = choice == 'camera' ? PhotoSource.camera : PhotoSource.gallery;
        final raw = await ref
            .read(appLockProvider.notifier)
            .runExternal(() => ref.read(photoPickerProvider).pick(source));
        if (raw == null) return;
        final photo = await ref.read(photoPreparerProvider)(raw, avatar: true);
        await api.setAvatar(photo.bytes);
        countDataW(ref, sent: photo.bytes.length);
      }
      await ref.read(sessionControllerProvider.notifier).refreshAccount();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice == 'remove' ? 'Photo de profil retirée.' : 'Photo de profil mise à jour.',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
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
                        Semantics(
                          button: true,
                          label: 'Modifier la photo de profil',
                          child: InkWell(
                            key: const Key('settings.avatar'),
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                _editAvatar(context, ref, hasAvatar: profile.avatarPath != null),
                            child: Stack(
                              children: [
                                UserAvatar(
                                  name: profile.displayName,
                                  avatarPath: profile.avatarPath,
                                  seed: account!.userId,
                                  radius: 30,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: CircleAvatar(
                                    radius: 11,
                                    backgroundColor: p.accentText,
                                    child: const Icon(
                                      Icons.photo_camera,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                ListTile(
                  key: const Key('settings.privacy'),
                  leading: Icon(Icons.shield_outlined, color: p.accentText),
                  title: const Text('Confidentialité'),
                  subtitle: const Text(
                    'En ligne, photo, accusés de lecture, invitations, durée par défaut',
                  ),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.privacy),
                ),
                const _Divider(),
                SwitchListTile(
                  key: const Key('settings.discoverable'),
                  value: account?.phoneDiscoverable ?? false,
                  onChanged: account == null ? null : (v) => _toggleDiscoverable(context, ref, v),
                  secondary: Icon(Icons.phone_outlined, color: p.accentText),
                  title: const Text('Me trouver par mon numéro'),
                  subtitle: Text(
                    (account?.phoneDiscoverable ?? false)
                        ? 'Activé\u202F: on peut aussi vous trouver par votre numéro.'
                        : profile == null
                        ? 'Désactivé\u202F: on vous trouve seulement par votre identifiant.'
                        : 'Désactivé\u202F: on vous trouve seulement par @${profile.handle}.',
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
                const _Divider(),
                ListTile(
                  key: const Key('settings.lock'),
                  leading: Icon(Icons.lock_outline, color: p.accentText),
                  title: const Text('Verrouillage de l’application'),
                  subtitle: Text(
                    (ref.watch(appLockProvider).value?.enabled ?? false)
                        ? 'Activé · ${delayLabel(ref.watch(appLockProvider).value!.config.delaySeconds).toLowerCase()}'
                        : 'Désactivé',
                  ),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.appLock),
                ),
              ],
            ),
            const _SectionTitle('Notifications et gestes'),
            _Card(
              children: [
                SwitchListTile(
                  key: const Key('settings.push'),
                  value: ref.watch(pushProvider).value ?? false,
                  onChanged: (v) => ref.read(pushProvider.notifier).setEnabled(v),
                  secondary: Icon(Icons.notifications_outlined, color: p.accentText),
                  title: const Text('Notifications'),
                  subtitle: const Text('Sans nom ni contenu.'),
                ),
                const _Divider(),
                ListTile(
                  key: const Key('settings.quick_reaction'),
                  leading: Icon(Icons.touch_app_outlined, color: p.accentText),
                  title: const Text('Réaction du double appui'),
                  subtitle: const Text('Toucher deux fois un message pour réagir.'),
                  trailing: Text(
                    ref.watch(quickReactionProvider).value ?? '❤️',
                    style: theme.textTheme.titleLarge,
                  ),
                  onTap: () => _chooseQuickReaction(context, ref),
                ),
              ],
            ),
            const _SectionTitle('Ce téléphone'),
            _Card(
              children: [
                ListTile(
                  key: const Key('settings.storage'),
                  leading: Icon(Icons.data_saver_on_outlined, color: p.accentText),
                  title: const Text('Stockage et données'),
                  subtitle: const Text('Téléchargement des photos, données utilisées, espace'),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.storage),
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
