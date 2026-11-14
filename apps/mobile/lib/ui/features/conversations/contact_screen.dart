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
          title: Text('Bloquer $name\u202F?'),
          content: const Text(
            'Vous ne pourrez plus vous écrire, dans un sens comme dans l’autre, et cette '
            'personne ne pourra plus vous trouver. Vous pourrez la débloquer à tout moment.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              key: const Key('contact.block.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bloquer'),
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
          SnackBar(content: Text(block ? '$name est bloqué.' : '$name est débloqué.')),
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
      title: 'Durée des messages',
      help: 'Pour les prochains messages, chez vous deux.',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Infos')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xl),
        children: [
          FicheAvatar(
            name: summary.title,
            path: profile?.avatarPath ?? summary.peerAvatarPath,
            seed: peerId,
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(summary.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
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
          if (about != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xl,
                PrivioSpacing.l,
                PrivioSpacing.xl,
                0,
              ),
              child: Column(
                key: const Key('contact.about'),
                children: [
                  Text(
                    'À propos',
                    style: theme.textTheme.labelMedium?.copyWith(color: p.accentText),
                  ),
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(about, textAlign: TextAlign.center),
                ],
              ),
            ),
          const Divider(height: PrivioSpacing.xxl),
          ListTile(
            key: const Key('contact.ttl'),
            leading: Icon(Icons.timer_outlined, color: p.accentText),
            title: const Text('Durée des messages'),
            subtitle: Text(formatTtl(summary.ttlSeconds)),
            trailing: const Icon(Icons.chevron_right),
            onTap: summary.blocked ? null : () => _ttl(summary),
          ),
          ListTile(
            key: const Key('contact.mute'),
            leading: Icon(
              summary.isMuted(now)
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
              color: p.accentText,
            ),
            title: const Text('Notifications'),
            subtitle: Text(muteLabel(summary, now)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => chooseMute(context, ref, summary),
          ),
          ListTile(
            key: const Key('contact.clear'),
            leading: Icon(Icons.cleaning_services_outlined, color: p.accentText),
            title: const Text('Vider la discussion'),
            trailing: const Icon(Icons.chevron_right),
            // La discussion ouvre son propre choix (chez moi / pour nous deux).
            onTap: () => context.pop('clear'),
          ),
          const Divider(height: PrivioSpacing.xl),
          ConversationMediaSection(conversationId: summary.id, title: summary.title),
          if (groups.isNotEmpty) ...[
            const Divider(height: PrivioSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
              child: Text(
                '${groups.length} groupe${groups.length > 1 ? 's' : ''} en commun',
                key: const Key('contact.common_groups'),
                style: theme.textTheme.titleSmall,
              ),
            ),
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
                subtitle: Text('${g.memberCount} membre${g.memberCount > 1 ? 's' : ''}'),
                onTap: () => context.push(Routes.chat(g.id)),
              ),
          ],
          const Divider(height: PrivioSpacing.xl),
          if (blockedList.isLoading)
            const LoadingView()
          else
            ListTile(
              key: const Key('contact.block'),
              enabled: !_busy,
              leading: Icon(
                iBlocked ? Icons.lock_open : Icons.block,
                color: iBlocked ? null : theme.colorScheme.error,
              ),
              title: Text(
                iBlocked ? 'Débloquer' : 'Bloquer',
                style: iBlocked
                    ? null
                    : theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
              onTap: () => _toggle(peerId, summary.title, block: !iBlocked),
            ),
          ListTile(
            key: const Key('contact.report'),
            leading: Icon(Icons.flag_outlined, color: theme.colorScheme.error),
            title: Text(
              'Signaler ce contact',
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
    );
  }
}
