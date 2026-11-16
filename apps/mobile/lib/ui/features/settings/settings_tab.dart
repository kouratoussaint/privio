import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../router/routes.dart';
import '../../../state/console_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/settings_card.dart';
import 'my_profile_screen.dart';
import 'appearance_screen.dart';
import '../../../data/services/share_service.dart';
import 'language_screen.dart';
import '../../../state/appearance_providers.dart';
import '../../core/motion/motion.dart';

/// Écran 22 — paramètres (design lot 2.D, réorganisés au lot 8.3a) : profil, puis une ligne
/// par écran (Mon compte, Préférences, Ce téléphone, Privio), déconnexion.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final profile = account?.profile;
    final secondary = theme.colorScheme.onSurfaceVariant;

    return BrandScaffold(
      title: Text(L.t.parametres),
      body: ColoredBox(
        color: theme.colorScheme.surface,
        // Lot 8.5a : sections en cascade à l'ouverture.
        child: EntranceScope(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.l,
              PrivioSpacing.xl,
              PrivioSpacing.l,
              PrivioSpacing.xl,
            ),
            children: cascade([
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
                            // Lot 8.3a : mon QR code, sans passer par Ma fiche.
                            IconButton(
                              key: const Key('settings.qr'),
                              tooltip: L.t.monQrCode,
                              icon: Icon(Icons.qr_code_2_rounded, color: p.accentText),
                              onPressed: () => showMyQrCode(
                                context,
                                handle: profile.handle,
                                name: profile.displayName,
                              ),
                            ),
                            Icon(Icons.chevron_right, color: secondary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              // Lot 8.3a : une ligne par écran, regroupées par thème.
              SettingsSectionTitle(L.t.settingsAccountSection),
              SettingsCard(
                children: [
                  _Entry(
                    key: const Key('settings.privacy'),
                    icon: Icons.shield_outlined,
                    title: L.t.confidentialite,
                    subtitle: L.t.settingsPrivacySubtitle,
                    onTap: () => context.push(Routes.privacy),
                  ),
                  const SettingsDivider(),
                  _Entry(
                    key: const Key('settings.security'),
                    icon: Icons.lock_outline,
                    title: L.t.securite,
                    subtitle: L.t.settingsSecuritySubtitle,
                    onTap: () => context.push(Routes.security),
                  ),
                ],
              ),
              SettingsSectionTitle(L.t.settingsPreferencesSection),
              SettingsCard(
                children: [
                  _Entry(
                    key: const Key('settings.notifications'),
                    icon: Icons.notifications_outlined,
                    title: L.t.notificationsSons,
                    subtitle: L.t.settingsNotificationsSubtitle,
                    onTap: () => context.push(Routes.notificationSettings),
                  ),
                  const SettingsDivider(),
                  _Entry(
                    key: const Key('settings.chats'),
                    icon: Icons.forum_outlined,
                    title: L.t.discussions,
                    subtitle: L.t.settingsChatsSubtitle,
                    onTap: () => context.push(Routes.chatSettings),
                  ),
                  const SettingsDivider(),
                  // Lot 8.1a : thème et taille du texte.
                  _Entry(
                    key: const Key('settings.appearance'),
                    icon: Icons.palette_outlined,
                    title: L.t.apparence,
                    subtitle: L.t.themeClairOuSombreTaille,
                    onTap: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute<void>(builder: (_) => const AppearanceScreen())),
                  ),
                  const SettingsDivider(),
                  // Lot 8.2a : langue de l'application.
                  _Entry(
                    key: const Key('settings.language'),
                    icon: Icons.translate_rounded,
                    title: L.t.languageTitle,
                    subtitle: ref.watch(releasedLanguagesProvider).length < 2
                        ? '${kLanguages[ref.watch(appearanceProvider).value?.language ?? 'fr']} · '
                              '${L.t.languageSubtitleSoon}'
                        : kLanguages[ref.watch(appearanceProvider).value?.language ?? 'fr'] ?? '',
                    onTap: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute<void>(builder: (_) => const LanguageScreen())),
                  ),
                ],
              ),
              SettingsSectionTitle(L.t.ceTelephone),
              SettingsCard(
                children: [
                  _Entry(
                    key: const Key('settings.storage'),
                    icon: Icons.data_saver_on_outlined,
                    title: L.t.stockageDonnees,
                    subtitle: L.t.telechargementPhotosDonneesUtiliseesEspace,
                    onTap: () => context.push(Routes.storage),
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
              SettingsSectionTitle(L.t.settingsPrivioSection),
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
                  // Lot 8.5a : « Supprimer mon compte » avant « Se déconnecter ».
                  ListTile(
                    key: const Key('settings.delete'),
                    leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                    title: Text(
                      L.t.supprimerMonCompte,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                    ),
                    onTap: () => context.push(Routes.deleteAccount),
                  ),
                  const SettingsDivider(),
                  ListTile(
                    key: const Key('settings.signout'),
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text(
                      L.t.seDeconnecter,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                    ),
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.xl),
              Text(
                L.t.privioAppversionproviderMessageriePriveeEphemere(ref.watch(appVersionProvider)),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ligne des Paramètres qui ouvre un écran.
class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: PrivioPalette.of(context).accentText),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
    onTap: onTap,
  );
}
