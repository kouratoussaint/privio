import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../../state/profile_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ttl_picker.dart';
import 'conversation_details.dart';
import 'report_sheet.dart';
import '../../core/widgets/settings_card.dart';
import 'message_extras.dart';
import '../settings/wallpaper.dart';
import '../calls/call_screen.dart';

/// Fiche contact (depuis une discussion) : photo en grand, « À propos », durée, sourdine,
/// « Vider », médias, groupes en commun, blocage et signalement (lot 7.1a).
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  bool _busy = false;

  Future<void> _toggle(String userId, String name, {required bool block}) async {
    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L.t.bloquerName(name)),
          content: Text(L.t.vousNePourrezPlusVous),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
            FilledButton(
              key: const Key('contact.block.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t.bloquer),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await setBlocked(ref, userId, blocked: block);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block ? L.t.nameEstBloque(name) : L.t.nameEstDebloque(name))),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ttl(ConversationSummary s) async {
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final picked = await showTtlPicker(
      context,
      title: L.t.dureeMessages,
      help: L.t.pourProchainsMessagesChezVous,
      current: s.ttlSeconds,
      min: rules.minTtlSeconds,
      max: rules.maxTtlSeconds,
      keyPrefix: 'contact.ttl',
    );
    if (picked == null || picked == s.ttlSeconds || !mounted) return;
    try {
      await ref.read(messagingApiProvider).setConversationTtl(s.id, picked);
      await ref.read(conversationsProvider.notifier).refresh();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final now = DateTime.now();
    final summary = ref.watch(conversationSummaryProvider(widget.conversationId));
    final blockedList = ref.watch(blockedUsersProvider);
    final peerId = summary?.peerId;
    if (summary == null || peerId == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    final profile = ref.watch(contactProfileProvider(peerId)).value;
    final groups = ref.watch(commonGroupsProvider(peerId)).value ?? const <CommonGroup>[];
    final iBlocked = blockedList.value?.any((b) => b.id == peerId) ?? false;
    final about = profile?.about;
    // Lot 7.2a : une carte blanche par partie, comme Paramètres.
    return Scaffold(
      appBar: AppBar(title: Text(L.t.infos)),
      body: SettingsListView(
        children: [
          SettingsCard(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              FicheAvatar(
                name: summary.title,
                path: profile?.avatarPath ?? summary.peerAvatarPath,
                seed: peerId,
              ),
              const SizedBox(height: PrivioSpacing.l),
              Text(
                summary.title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (summary.peerHandle != null)
                Text(
                  '@${summary.peerHandle}',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              if (!summary.blocked)
                Builder(
                  builder: (context) {
                    final label = presenceLabel(
                      ref.watch(presenceProvider(peerId)).value ?? const UserPresence(),
                      now,
                    );
                    return label.isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            label,
                            key: const Key('contact.presence'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                  },
                ),
              // Lot 9.1a : appeler ce contact.
              if (!summary.blocked && !summary.peerDeleted)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.m),
                  child: Center(
                    child: FilledButton.tonalIcon(
                      key: const Key('contact.call'),
                      onPressed: () => startCallFrom(context, ref, summary.id),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(L.t.appeler),
                    ),
                  ),
                ),
              if (about != null)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.l),
                  child: Column(
                    key: const Key('contact.about'),
                    children: [
                      Text(
                        L.t.propos,
                        style: theme.textTheme.labelMedium?.copyWith(color: p.accentText),
                      ),
                      const SizedBox(height: PrivioSpacing.xs),
                      Text(about, textAlign: TextAlign.center),
                    ],
                  ),
                ),
            ],
          ),
          SettingsSectionTitle(L.t.discussion),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('contact.ttl'),
                leading: Icon(Icons.timer_outlined, color: p.accentText),
                title: Text(L.t.dureeMessages),
                subtitle: Text(formatTtl(summary.ttlSeconds)),
                trailing: const Icon(Icons.chevron_right),
                onTap: summary.blocked ? null : () => _ttl(summary),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('contact.mute'),
                leading: Icon(
                  summary.isMuted(now)
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  color: p.accentText,
                ),
                title: Text(L.t.notifications),
                subtitle: Text(muteLabel(summary, now)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => chooseMute(context, ref, summary),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('contact.clear'),
                leading: Icon(Icons.cleaning_services_outlined, color: p.accentText),
                title: Text(L.t.viderDiscussion),
                trailing: const Icon(Icons.chevron_right),
                // Lot 7.2a : le choix s'ouvre ici, on reste sur la fiche.
                onTap: () => chooseClear(context, ref, summary),
              ),
              // Lot 7.3a : fond d'écran propre à cette discussion.
              const SettingsDivider(),
              ListTile(
                key: const Key('fiche.wallpaper'),
                leading: Icon(Icons.wallpaper_outlined, color: p.accentText),
                title: Text(L.t.fondEcran),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        WallpaperScreen(conversationId: summary.id, title: summary.title),
                  ),
                ),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.medias),
          SettingsCard(
            children: [
              ConversationMediaSection(conversationId: summary.id, title: summary.title),
              const SettingsDivider(),
              // Lot 7.2c2 : mes messages favoris.
              FavoritesRow(conversationId: summary.id, title: summary.title),
            ],
          ),
          SettingsSectionTitle(L.t.confidentialiteCetteDiscussion),
          SettingsCard(children: [ConversationPrivacySection(summary: summary)]),
          SettingsNote(L.t.cesChoixNeValentQue),
          if (groups.isNotEmpty) ...[
            SettingsSectionTitle(
              L.t.groupsInCommon(groups.length),
              key: const Key('contact.common_groups'),
            ),
            SettingsCard(
              children: [
                for (final g in groups)
                  ListTile(
                    key: Key('contact.group.${g.id}'),
                    leading: UserAvatar(
                      name: g.title,
                      avatarPath: g.avatarPath,
                      seed: g.id,
                      radius: 20,
                      icon: Icons.groups_rounded,
                    ),
                    title: Text(g.title),
                    subtitle: Text(L.t.membersCount(g.memberCount)),
                    onTap: () => context.push(Routes.chat(g.id)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: PrivioSpacing.xl),
          SettingsCard(
            children: [
              if (blockedList.isLoading)
                const Padding(
                  padding: EdgeInsets.all(PrivioSpacing.l),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ListTile(
                  key: const Key('contact.block'),
                  enabled: !_busy,
                  leading: Icon(
                    iBlocked ? Icons.lock_open : Icons.block,
                    color: iBlocked ? null : theme.colorScheme.error,
                  ),
                  title: Text(
                    iBlocked ? L.t.debloquer : L.t.bloquer,
                    style: iBlocked
                        ? null
                        : theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  ),
                  onTap: () => _toggle(peerId, summary.title, block: !iBlocked),
                ),
              const SettingsDivider(),
              // Lot 7.2b1 : supprimer chez moi, ou pour nous deux (avec accord).
              ListTile(
                key: const Key('contact.delete'),
                leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text(
                  L.t.supprimerDiscussion,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                ),
                onTap: () => chooseDelete(context, ref, summary),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('contact.report'),
                leading: Icon(Icons.flag_outlined, color: theme.colorScheme.error),
                title: Text(
                  L.t.signalerCeContact,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                ),
                onTap: () => showReportSheet(
                  context,
                  reportedUserId: peerId,
                  reportedName: summary.title,
                  conversationId: widget.conversationId,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
