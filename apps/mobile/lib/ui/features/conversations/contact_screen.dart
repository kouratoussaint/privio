import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/messaging_providers.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/privacy_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import 'report_sheet.dart';

/// Fiche contact (depuis une discussion) : identité publique et blocage.
/// Le signalement arrive au lot 2.5.
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
          title: Text('Bloquer $name ?'),
          content: const Text(
            'Vous ne pourrez plus vous écrire, dans un sens comme dans l\'autre, et cette '
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ref.watch(conversationSummaryProvider(widget.conversationId));
    final blockedList = ref.watch(blockedUsersProvider);
    final peerId = summary?.peerId;
    if (summary == null || peerId == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    final iBlocked = blockedList.value?.any((b) => b.id == peerId) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        children: [
          Center(
            child: UserAvatar(
              name: summary.title,
              avatarPath: summary.peerAvatarPath,
              seed: peerId,
              radius: 48,
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(summary.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          if (summary.peerHandle != null)
            Text(
              '@${summary.peerHandle}',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          if (summary.peerId != null && !summary.blocked)
            Builder(
              builder: (context) {
                final label = presenceLabel(
                  ref.watch(presenceProvider(summary.peerId!)).value ?? const UserPresence(),
                  DateTime.now(),
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
          const SizedBox(height: PrivioSpacing.xxl),
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
