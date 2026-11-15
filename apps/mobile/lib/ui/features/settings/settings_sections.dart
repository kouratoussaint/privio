import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/reactions.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/feedback_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/push_providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/settings_card.dart';
import '../lock/app_lock_screens.dart' show delayLabel;
import 'change_phone_screen.dart';
import 'two_step_screens.dart';
import 'wallpaper.dart';
import '../../../state/providers.dart';
import '../../../core/errors/app_failure.dart';

/// Lot 8.3a : sous-écrans des Paramètres (page d'accueil courte, une ligne par écran).

/// Sécurité : verrouillage, changement de numéro, captures d'écran, appareil unique.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final lock = ref.watch(appLockProvider).value;
    final phone = ref.watch(sessionControllerProvider).value?.account?.phoneE164;
    return Scaffold(
      appBar: AppBar(title: Text(L.t.securite)),
      body: SettingsListView(
        children: [
          const SizedBox(height: PrivioSpacing.s),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('security.lock'),
                leading: Icon(Icons.lock_outline, color: p.accentText),
                title: Text(L.t.verrouillageApplication),
                subtitle: Text(
                  (lock?.enabled ?? false)
                      ? L.t.activeTolowercase(delayLabel(lock!.config.delaySeconds).toLowerCase())
                      : L.t.desactive2,
                ),
                trailing: Icon(Icons.chevron_right, color: secondary),
                onTap: () => context.push(Routes.appLock),
              ),
              const SettingsDivider(),
              // Lot 8.4a : vérification en deux étapes.
              ListTile(
                key: const Key('security.two_step'),
                leading: Icon(Icons.verified_user_outlined, color: p.accentText),
                title: Text(L.t.twoStepTitle),
                subtitle: switch (ref.watch(twoStepStateProvider)) {
                  AsyncData(:final value) => Text(value.enabled ? L.t.twoStepOn : L.t.twoStepOff),
                  _ => null,
                },
                trailing: Icon(Icons.chevron_right, color: secondary),
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const TwoStepSettingsScreen()));
                  ref.invalidate(twoStepStateProvider);
                },
              ),
              if (phone != null) ...[
                const SettingsDivider(),
                ListTile(
                  key: const Key('security.phone'),
                  leading: Icon(Icons.phone_outlined, color: p.accentText),
                  title: Text(L.t.changerNumero),
                  subtitle: Text(PhoneNumber.format(phone)),
                  trailing: Icon(Icons.chevron_right, color: secondary),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(builder: (_) => ChangePhoneScreen(currentPhone: phone)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: PrivioSpacing.l),
          SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.screenshot_monitor_outlined, color: p.accentText),
                title: Text(L.t.capturesEcran),
                subtitle: Text(L.t.toujoursBloqueesDansPrivioNon),
              ),
              const SettingsDivider(),
              ListTile(
                leading: Icon(Icons.phone_android, color: p.accentText),
                title: Text(L.t.seulAppareilConnecte),
                subtitle: Text(L.t.connexionSurAutreTelephoneDeconnecte),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lot 8.4b : rappel avant effacement (serveur).
final expiryReminderProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(accountApiProvider).expiryReminder(),
);

/// Notifications et sons.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L.t.notificationsSons)),
      body: SettingsListView(
        children: [
          const SizedBox(height: PrivioSpacing.s),
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
              // Lot 8.4b : rappel avant effacement (réglage gardé sur le serveur).
              SwitchListTile(
                key: const Key('settings.expiry_reminder'),
                value: ref.watch(expiryReminderProvider).value ?? true,
                secondary: Icon(Icons.hourglass_bottom_rounded, color: p.accentText),
                title: Text(L.t.expiryReminderTitle),
                subtitle: Text(L.t.expiryReminderSubtitle),
                onChanged: ref.watch(expiryReminderProvider).isLoading
                    ? null
                    : (v) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref.read(accountApiProvider).setExpiryReminder(v);
                        } on Object catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                        }
                        ref.invalidate(expiryReminderProvider);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Discussions : fond d'écran, réaction du double appui, groupes, archivées.
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final together = ref.watch(groupsInDiscussionsProvider).value ?? false;
    final archived = (ref.watch(conversationsProvider).value ?? const <ConversationSummary>[])
        .where((c) => c.archived)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(L.t.discussions)),
      body: SettingsListView(
        children: [
          const SizedBox(height: PrivioSpacing.s),
          SettingsCard(
            children: [
              // Lot 7.3a : fond d'écran par défaut des discussions.
              ListTile(
                key: const Key('settings.wallpaper'),
                leading: Icon(Icons.wallpaper_outlined, color: p.accentText),
                title: Text(L.t.fondEcranDiscussions),
                subtitle: Text(L.t.motifsCouleursOuVosPhotos),
                trailing: Icon(Icons.chevron_right, color: secondary),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const WallpaperScreen())),
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
              const SettingsDivider(),
              // Lot 7.2b1 : groupes séparés des discussions (par défaut) ou ensemble.
              SwitchListTile(
                key: const Key('settings.groups_together'),
                value: together,
                secondary: Icon(Icons.forum_outlined, color: p.accentText),
                title: Text(L.t.groupesDansDiscussions),
                subtitle: Text(
                  together
                      ? L.t.groupesApparaissentAussiDansDiscussions
                      : L.t.separesGroupesSontSeulementDans,
                ),
                onChanged: (v) => ref.read(groupsInDiscussionsProvider.notifier).set(v),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('settings.archived'),
                leading: Icon(Icons.archive_outlined, color: p.accentText),
                title: Text(L.t.archivees),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$archived',
                      style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
                    ),
                    const SizedBox(width: PrivioSpacing.xs),
                    Icon(Icons.chevron_right, color: secondary),
                  ],
                ),
                onTap: () => context.push(Routes.archived),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
