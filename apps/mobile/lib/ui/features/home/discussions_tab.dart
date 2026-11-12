import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';

/// Écran 08 — liste des discussions, rafraîchie en temps réel.
class DiscussionsTab extends ConsumerStatefulWidget {
  const DiscussionsTab({super.key});

  @override
  ConsumerState<DiscussionsTab> createState() => _DiscussionsTabState();
}

class _DiscussionsTabState extends ConsumerState<DiscussionsTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Les aperçus de messages expirés disparaissent même sans signal réseau.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.invalidate(conversationsProvider);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privio')),
      floatingActionButton: FloatingActionButton(
        key: const Key('discussions.new'),
        tooltip: 'Nouvelle discussion',
        onPressed: () => context.push(Routes.newConversation),
        child: const Icon(Icons.edit_outlined),
      ),
      body: switch (conversations) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.chat_bubble_outline,
          title: 'Aucune discussion pour l\'instant',
          message:
              'Touchez le crayon pour écrire à quelqu\'un. Chaque message s\'efface '
              'automatiquement 72 heures après son envoi.',
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
          child: ListView.separated(
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(indent: 80),
            itemBuilder: (_, i) => _ConversationTile(summary: value[i]),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(conversationsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.summary});

  final ConversationSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final mine = summary.lastSenderId != null && summary.lastSenderId == me;
    final preview = switch (summary) {
      ConversationSummary(blocked: true) => 'Contact bloqué',
      ConversationSummary(lastMessageId: null) => 'Aucun message',
      ConversationSummary(lastDeleted: true) => 'Message supprimé',
      _ => '${mine ? 'Vous : ' : ''}${summary.lastBody ?? ''}',
    };
    final unread = summary.unreadCount;
    return ListTile(
      key: Key('conversation.${summary.id}'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.l,
        vertical: PrivioSpacing.xs,
      ),
      leading: InitialAvatar(name: summary.title),
      title: Row(
        children: [
          Expanded(child: Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (summary.pinned)
            Icon(Icons.push_pin, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread > 0
            ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
            : theme.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMessageTime(summary.sortAt), style: theme.textTheme.labelSmall),
          if (unread > 0) ...[
            const SizedBox(height: PrivioSpacing.xs),
            Badge(
              label: Text(unread > 99 ? '99+' : '$unread'),
              backgroundColor: theme.colorScheme.primary,
              textColor: theme.colorScheme.onPrimary,
            ),
          ],
        ],
      ),
      onTap: () => context.push(Routes.chat(summary.id)),
    );
  }
}
