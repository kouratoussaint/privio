import 'dart:async';

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
import '../../core/widgets/avatar.dart';
import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/state_views.dart';

enum ConversationFilter { all, unread, pinned }

/// Seuil d'affichage du rappel « s'efface dans … » sur une ligne.
const kExpiringSoon = Duration(hours: 12);

/// Écran 08 — discussions : recherche locale, filtres, liste en temps réel.
class DiscussionsTab extends ConsumerStatefulWidget {
  const DiscussionsTab({super.key});

  @override
  ConsumerState<DiscussionsTab> createState() => _DiscussionsTabState();
}

class _DiscussionsTabState extends ConsumerState<DiscussionsTab> {
  final _search = TextEditingController();
  Timer? _tick;
  ConversationFilter _filter = ConversationFilter.all;

  @override
  void initState() {
    super.initState();
    // Rafraîchissement de secours (temps réel coupé) ; fait aussi disparaître les
    // aperçus de messages expirés.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) ref.invalidate(conversationsProvider);
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<ConversationSummary> _apply(List<ConversationSummary> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((c) {
      final matches =
          q.isEmpty ||
          c.title.toLowerCase().contains(q) ||
          (c.peerHandle ?? '').toLowerCase().contains(q) ||
          (!c.blocked && (c.lastBody ?? '').toLowerCase().contains(q));
      return matches &&
          switch (_filter) {
            ConversationFilter.all => true,
            ConversationFilter.unread => c.unreadCount > 0,
            ConversationFilter.pinned => c.pinned,
          };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final conversations = ref.watch(conversationsProvider);
    final unreadTotal = conversations.value?.where((c) => c.unreadCount > 0).length ?? 0;

    return BrandScaffold(
      title: const BrandTitle(),
      floatingActionButton: FloatingActionButton(
        key: const Key('discussions.new'),
        tooltip: 'Nouvelle discussion',
        onPressed: () => context.push(Routes.newConversation),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.l,
              PrivioSpacing.l,
              PrivioSpacing.l,
              PrivioSpacing.m,
            ),
            child: TextField(
              key: const Key('discussions.search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher une discussion ou un contact',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: p.field,
                contentPadding: const EdgeInsets.symmetric(vertical: PrivioSpacing.m),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PrivioRadius.large + 4),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PrivioRadius.large + 4),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
              children: [
                _FilterChip(
                  label: 'Toutes',
                  selected: _filter == ConversationFilter.all,
                  onTap: () => setState(() => _filter = ConversationFilter.all),
                ),
                _FilterChip(
                  label: 'Non lues',
                  count: unreadTotal,
                  selected: _filter == ConversationFilter.unread,
                  onTap: () => setState(() => _filter = ConversationFilter.unread),
                ),
                _FilterChip(
                  label: 'Épinglées',
                  icon: Icons.push_pin_outlined,
                  selected: _filter == ConversationFilter.pinned,
                  onTap: () => setState(() => _filter = ConversationFilter.pinned),
                ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.s),
          Expanded(
            child: switch (conversations) {
              AsyncData(:final value) when value.isEmpty => const EmptyView(
                icon: Icons.chat_bubble_outline,
                title: 'Aucune discussion pour l\'instant',
                message:
                    'Touchez le crayon pour écrire à quelqu\'un. Chaque message '
                    's\'efface automatiquement 72 heures après son envoi.',
              ),
              AsyncData(:final value) => _List(
                items: _apply(value),
                onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
              ),
              AsyncError(:final error) => ErrorView(
                message: toAppFailure(error).message,
                onRetry: () => ref.invalidate(conversationsProvider),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bg = selected ? (dark ? PrivioColors.lilac : PrivioColors.purpleDeep) : p.field;
    final fg = selected ? (dark ? PrivioColors.navy : Colors.white) : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: PrivioSpacing.s),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: bg,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: PrivioSpacing.xs),
                    ],
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: PrivioSpacing.s),
                      _CountBadge(count: count),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? PrivioColors.lilac : PrivioColors.purple,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: dark ? PrivioColors.navy : Colors.white,
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.items, required this.onRefresh});

  final List<ConversationSummary> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyView(
        icon: Icons.search_off,
        title: 'Aucun résultat',
        message: 'Aucune discussion ne correspond à ce filtre.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: items.length,
        itemBuilder: (_, i) => _ConversationTile(summary: items[i]),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.summary});

  final ConversationSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final me = ref.watch(currentUserIdProvider);
    final mine = summary.lastSenderId != null && summary.lastSenderId == me;
    final unread = summary.unreadCount;
    final now = DateTime.now();
    final read =
        mine &&
        summary.lastSentAt != null &&
        summary.peerReadUpTo != null &&
        !summary.peerReadUpTo!.isBefore(summary.lastSentAt!);
    final expiresSoon =
        summary.lastExpiresAt != null &&
        !summary.blocked &&
        summary.lastExpiresAt!.difference(now) < kExpiringSoon;
    final preview = switch (summary) {
      ConversationSummary(blocked: true) => 'Contact bloqué',
      ConversationSummary(lastMessageId: null) => 'Aucun message',
      ConversationSummary(lastDeleted: true) => 'Message supprimé',
      ConversationSummary(lastKind: 'system') =>
        'Durée des messages : ${formatTtl(summary.ttlSeconds)}',
      _ => '${mine ? 'Vous : ' : ''}${summary.lastBody ?? ''}',
    };
    final secondary = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      key: Key('conversation.${summary.id}'),
      onTap: () => context.push(Routes.chat(summary.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l, vertical: 10),
        child: Row(
          children: [
            InitialAvatar(name: summary.title, seed: summary.peerId ?? summary.id),
            const SizedBox(width: 14),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.divider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              summary.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            formatMessageTime(summary.sortAt, now: now),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: unread > 0 ? p.accentText : secondary,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (read) ...[
                            Icon(
                              Icons.done_all,
                              size: 16,
                              color: p.accentText,
                              semanticLabel: 'Lu',
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: unread > 0 ? theme.colorScheme.onSurface : secondary,
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (expiresSoon) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.timer_outlined, size: 14, color: p.warn),
                            const SizedBox(width: 2),
                            Text(
                              formatRemaining(summary.lastExpiresAt!, now: now),
                              key: Key('expiring.${summary.id}'),
                              semanticsLabel:
                                  's\'efface dans ${formatRemaining(summary.lastExpiresAt!, now: now)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: p.warn,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (summary.pinned) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.push_pin,
                              size: 16,
                              color: secondary,
                              semanticLabel: 'Épinglée',
                            ),
                          ],
                          if (unread > 0) ...[const SizedBox(width: 6), _CountBadge(count: unread)],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
