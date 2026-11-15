import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/reactions.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/console_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import '../../../state/push_providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/avatar.dart';
import '../lock/app_lock_screens.dart' show delayLabel;
import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/settings_card.dart';
import 'my_profile_screen.dart';
import '../../../state/feedback_providers.dart';
import 'wallpaper.dart';
import 'appearance_screen.dart';
import '../../../data/services/share_service.dart';
import 'language_screen.dart';
import '../../../state/appearance_providers.dart';

/// Écran 22 — paramètres (design lot 2.D) : profil, confidentialité, appareil, déconnexion.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.seDeconnecter2),
        content: Text(L.t.vousDevrezRecevoirNouveauCode),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('settings.signout.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.seDeconnecter),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final profile = account?.profile;
    final blockedCount = ref.watch(blockedUsersProvider).value?.length;
    final secondary = theme.colorScheme.onSurfaceVariant;

    return BrandScaffold(
      title: Text(L.t.parametres),
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
              SettingsCard(
                children: [
                  InkWell(
                    key: const Key('settings.profile'),
                    // Lot 7.2a : la ligne du profil ouvre « Ma fiche » (nom, photo, À propos).
                    onTap: () => context.push(Routes.myProfile),
                    child: Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.l),
                      child: Row(
                        children: [
                          UserAvatar(
                            name: profile.displayName,
                            avatarPath: profile.avatarPath,
                            seed: account!.userId,
                            radius: 30,
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
                          Icon(Icons.chevron_right, color: secondary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            SettingsSectionTitle(L.t.confidentialite),
            // Lot 7.1a : « À propos » (140 caractères), visible selon Confidentialité.
            if (profile != null)
              SettingsCard(
                children: [
                  ListTile(
                    key: const Key('settings.about'),
                    leading: Icon(Icons.info_outline, color: p.accentText),
                    title: Text(L.t.propos),
                    subtitle: Text(
                      (profile.about ?? '').isEmpty
                          ? L.t.ajouterCourtTextePresentation
                          : profile.about!,
                    ),
                    trailing: Icon(Icons.edit_outlined, color: secondary),
                    onTap: () => editMyAbout(context, ref, profile.about),
                  ),
                ],
              ),
            if (profile != null) const SizedBox(height: PrivioSpacing.l),
            SettingsCard(
              children: [
                ListTile(
                  key: const Key('settings.privacy'),
                  leading: Icon(Icons.shield_outlined, color: p.accentText),
                  title: Text(L.t.confidentialite),
                  subtitle: Text(L.t.lignePhotoAccusesLectureInvitations),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.privacy),
                ),
                const SettingsDivider(),
                SwitchListTile(
                  key: const Key('settings.discoverable'),
                  value: account?.phoneDiscoverable ?? false,
                  onChanged: account == null ? null : (v) => _toggleDiscoverable(context, ref, v),
                  secondary: Icon(Icons.phone_outlined, color: p.accentText),
                  title: Text(L.t.meTrouverParMonNumero),
                  subtitle: Text(
                    (account?.phoneDiscoverable ?? false)
                        ? L.t.activeOnPeutAussiVous
                        : profile == null
                        ? L.t.desactiveOnVousTrouveSeulement
                        : L.t.desactiveOnVousTrouveSeulement2(profile.handle),
                  ),
                ),
                const SettingsDivider(),
                ListTile(
                  key: const Key('settings.blocked'),
                  leading: Icon(Icons.block, color: p.accentText),
                  title: Text(L.t.personnesBloquees),
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
                const SettingsDivider(),
                ListTile(
                  key: const Key('settings.lock'),
                  leading: Icon(Icons.lock_outline, color: p.accentText),
                  title: Text(L.t.verrouillageApplication),
                  subtitle: Text(
                    (ref.watch(appLockProvider).value?.enabled ?? false)
                        ? L.t.activeTolowercase(
                            delayLabel(ref.watch(appLockProvider).value!.config.delaySeconds)
                                .toLowerCase(),
                          )
                        : L.t.desactive2,
                  ),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.appLock),
                ),
              ],
            ),
            SettingsSectionTitle(L.t.notificationsGestes),
            SettingsCard(
              children: [
                SwitchListTile(
                  key: const Key('settings.push'),
                  value: ref.watch(pushProvider).value ?? false,
                  onChanged: (v) => ref.read(pushProvider.notifier).setEnabled(v),
                  secondary: Icon(Icons.notifications_outlined, color: p.accentText),
                  title: Text(L.t.notifications),
                  subtitle: Text(L.t.sansNomNiContenu),
                ),
                const SettingsDivider(),
                // Lot 7.2b2 : sons courts et vibrations (activés par défaut).
                SwitchListTile(
                  key: const Key('settings.sounds'),
                  value: ref.watch(soundsEnabledProvider).value ?? true,
                  secondary: Icon(Icons.volume_up_outlined, color: p.accentText),
                  title: Text(L.t.sonsVibrations),
                  subtitle: Text(L.t.envoiReceptionEffacementRienMode),
                  onChanged: (v) => ref.read(soundsEnabledProvider.notifier).set(v),
                ),
                const SettingsDivider(),
                // Lot 8.2a : langue de l'application.
                ListTile(
                  key: const Key('settings.language'),
                  leading: Icon(Icons.translate_rounded, color: p.accentText),
                  title: Text(L.t.languageTitle),
                  subtitle: Text(
                    ref.watch(releasedLanguagesProvider).length < 2
                        ? '${kLanguages[ref.watch(appearanceProvider).value?.language ?? 'fr']} · '
                              '${L.t.languageSubtitleSoon}'
                        : kLanguages[ref.watch(appearanceProvider).value?.language ?? 'fr'] ?? '',
                  ),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(MaterialPageRoute<void>(builder: (_) => const LanguageScreen())),
                ),
                const SettingsDivider(),
                // Lot 8.1a : thème et taille du texte.
                ListTile(
                  key: const Key('settings.appearance'),
                  leading: Icon(Icons.palette_outlined, color: p.accentText),
                  title: Text(L.t.apparence),
                  subtitle: Text(L.t.themeClairOuSombreTaille),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(MaterialPageRoute<void>(builder: (_) => const AppearanceScreen())),
                ),
                const SettingsDivider(),
                // Lot 7.3a : fond d'écran par défaut des discussions.
                ListTile(
                  key: const Key('settings.wallpaper'),
                  leading: Icon(Icons.wallpaper_outlined, color: p.accentText),
                  title: Text(L.t.fondEcranDiscussions),
                  subtitle: Text(L.t.motifsCouleursOuVosPhotos),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  // Au-dessus des onglets, comme les autres écrans des Paramètres.
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(MaterialPageRoute<void>(builder: (_) => const WallpaperScreen())),
                ),
                const SettingsDivider(),
                // Lot 7.2b1 : groupes séparés des discussions (par défaut) ou ensemble.
                SwitchListTile(
                  key: const Key('settings.groups_together'),
                  value: ref.watch(groupsInDiscussionsProvider).value ?? false,
                  secondary: Icon(Icons.forum_outlined, color: p.accentText),
                  title: Text(L.t.groupesDansDiscussions),
                  subtitle: Text(
                    ref.watch(groupsInDiscussionsProvider).value ?? false
                        ? L.t.groupesApparaissentAussiDansDiscussions
                        : L.t.separesGroupesSontSeulementDans,
                  ),
                  onChanged: (v) => ref.read(groupsInDiscussionsProvider.notifier).set(v),
                ),
                const SettingsDivider(),
                ListTile(
                  key: const Key('settings.quick_reaction'),
                  leading: Icon(Icons.touch_app_outlined, color: p.accentText),
                  title: Text(L.t.reactionDoubleAppui),
                  subtitle: Text(L.t.toucherDeuxFoisMessagePour),
                  trailing: Text(
                    ref.watch(quickReactionProvider).value ?? '❤️',
                    style: theme.textTheme.titleLarge,
                  ),
                  onTap: () => _chooseQuickReaction(context, ref),
                ),
              ],
            ),
            SettingsSectionTitle(L.t.ceTelephone),
            SettingsCard(
              children: [
                ListTile(
                  key: const Key('settings.storage'),
                  leading: Icon(Icons.data_saver_on_outlined, color: p.accentText),
                  title: Text(L.t.stockageDonnees),
                  subtitle: Text(L.t.telechargementPhotosDonneesUtiliseesEspace),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.storage),
                ),
                const SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.phone_android, color: p.accentText),
                  title: Text(L.t.seulAppareilConnecte),
                  subtitle: Text(L.t.connexionSurAutreTelephoneDeconnecte),
                ),
              ],
            ),
            // Lot 5.1 : entrée visible uniquement pour le compte administrateur (réponse du
            // serveur ; pour tout autre compte, la console n'existe pas).
            if (ref.watch(consoleAccessProvider).value ?? false) ...[
              const SizedBox(height: PrivioSpacing.l),
              SettingsCard(
                children: [
                  ListTile(
                    key: const Key('settings.console'),
                    leading: Icon(Icons.admin_panel_settings_outlined, color: p.accentText),
                    title: Text(L.t.administration),
                    subtitle: Text(L.t.tableauBordPrivioChiffresSeulement),
                    trailing: Icon(Icons.chevron_right, color: secondary),
                    onTap: () => context.push(Routes.console),
                  ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.l),
            SettingsCard(
              children: [
                // Lot 8.1c : inviter un ami (partage de mon identifiant).
                ListTile(
                  key: const Key('settings.invite'),
                  leading: Icon(Icons.favorite_border_rounded, color: p.accentText),
                  title: Text(L.t.inviterAmi),
                  subtitle: Text(L.t.partagerVotreIdentifiant),
                  onTap: () => ref.read(shareTextProvider)(inviteText(profile?.handle)),
                ),
                const SettingsDivider(),
                ListTile(
                  key: const Key('settings.help'),
                  leading: Icon(Icons.help_outline, color: p.accentText),
                  title: Text(L.t.aideAssistance),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => context.push(Routes.help),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.l),
            SettingsCard(
              children: [
                ListTile(
                  key: const Key('settings.signout'),
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    L.t.seDeconnecter,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  ),
                  onTap: () => _confirmSignOut(context, ref),
                ),
                const SettingsDivider(),
                ListTile(
                  key: const Key('settings.delete'),
                  leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                  title: Text(
                    L.t.supprimerMonCompte,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  ),
                  onTap: () => context.push(Routes.deleteAccount),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.xl),
            Text(
              L.t.privioAppversionproviderMessageriePriveeEphemere(ref.watch(appVersionProvider)),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
