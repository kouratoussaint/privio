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
import '../../../state/providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/swipe_actions.dart';
import '../conversations/connection_requests_screen.dart' show ConnectionRequestsBanner;
import '../conversations/conversation_details.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/illustrations.dart';
import '../groups/group_screens.dart';
import '../conversations/expression_panel.dart';

enum ConversationFilter { all, unread, pinned, groups }

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
    final local = ref.read(localCacheProvider).allMessages;
    // Lot 7.2b1 : groupes et discussions séparés (par défaut) : pas de groupe ici.
    final together = ref.read(groupsInDiscussionsProvider).value ?? false;
    return all.where((c) {
      if (c.archived) return false;
      if (c.isGroup && !together) return false;
      return matchesSearch(c, q, local) &&
          switch (_filter) {
            ConversationFilter.all => true,
            ConversationFilter.unread => c.unreadCount > 0,
            ConversationFilter.pinned => c.pinned,
            ConversationFilter.groups => c.isGroup,
          };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final together = ref.watch(groupsInDiscussionsProvider).value ?? false;
    if (!together && _filter == ConversationFilter.groups) _filter = ConversationFilter.all;
    final unreadTotal =
        conversations.value
            ?.where((c) => !c.archived && c.unreadCount > 0 && (together || !c.isGroup))
            .length ??
        0;
    // Lot 7.2c1 : séparés, les groupes archivés sont dans l'onglet Groupes.
    final archivedCount =
        conversations.value?.where((c) => c.archived && (together || !c.isGroup)).length ?? 0;
    final offline = ref.watch(offlineProvider);

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
            child: ListSearchField(key: const Key('discussions.search'), controller: _search),
          ),
          SizedBox(
            height: 48,
            child: FilterBar(
              chips: [
                FilterPill(
                  label: 'Toutes',
                  selected: _filter == ConversationFilter.all,
                  onTap: () => setState(() => _filter = ConversationFilter.all),
                ),
                FilterPill(
                  label: 'Non lues',
                  count: unreadTotal,
                  selected: _filter == ConversationFilter.unread,
                  onTap: () => setState(() => _filter = ConversationFilter.unread),
                ),
                FilterPill(
                  label: 'Épinglées',
                  selected: _filter == ConversationFilter.pinned,
                  onTap: () => setState(() => _filter = ConversationFilter.pinned),
                ),
                if (together)
                  FilterPill(
                    key: const Key('filter.groups'),
                    label: 'Groupes',
                    selected: _filter == ConversationFilter.groups,
                    onTap: () => setState(() => _filter = ConversationFilter.groups),
                  ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.s),
          AnimatedOfflineBanner(offline: offline),
          // Lot 4.7 : demandes de connexion reçues (ou refus récents) en tête de liste.
          const ConnectionRequestsBanner(),
          if (archivedCount > 0)
            ListTile(
              key: const Key('discussions.archived'),
              leading: const Icon(Icons.archive_outlined),
              title: Text('Archivées ($archivedCount)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push(together ? Routes.archived : Routes.archivedOf('discussions')),
            ),
          Expanded(
            child: switch (conversations) {
              AsyncData(:final value) when value.isEmpty && archivedCount == 0 => const EmptyView(
                icon: Icons.chat_bubble_outline,
                title: 'Aucune discussion pour l’instant',
                message:
                    'Touchez le crayon pour écrire à quelqu’un. Vos messages s’effacent seuls '
                    'au bout de 72 h.',
              ),
              AsyncData(:final value) => _List(
                items: _apply(value),
                onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
              ),
              AsyncError(:final error) => ErrorView(
                message: toAppFailure(error).message,
                onRetry: () => ref.invalidate(conversationsProvider),
              ),
              _ => const SkeletonList(),
            },
          ),
        ],
      ),
    );
  }
}

/// Barre des filtres (lot 4.4, R-09) : les 4 filtres restent visibles sur un écran
/// étroit (320 dp) : marges resserrées et texte légèrement réduit, jamais sous 11 px
/// (85 % de sa taille). Au-delà (très grande police), la barre défile.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.chips});

  final List<FilterPill> chips;

  static const minScale = 0.85;

  /// Mode resserré : marge d'écran, espace entre filtres, marge intérieure, pastille.
  static const denseEdge = PrivioSpacing.s;
  static const denseGap = 6.0;
  static const densePad = PrivioSpacing.s;
  static const denseBadgeGap = 4.0;
  static const denseBadgeMin = 18.0;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    final scaler = MediaQuery.textScalerOf(context);
    // Largeur des textes (réductibles) et des pastilles (fixes).
    double text = 0;
    double badges = 0;
    double denseBadges = 0;
    for (final c in chips) {
      final tp = TextPainter(
        text: TextSpan(text: c.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      text += tp.width;
      tp.dispose();
      if (c.count > 0) {
        final badge = TextPainter(
          text: TextSpan(
            text: c.count > 99 ? '99+' : '${c.count}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        badges += PrivioSpacing.s + (badge.width + 12 < 22 ? 22 : badge.width + 12);
        denseBadges +=
            denseBadgeGap + (badge.width + 8 < denseBadgeMin ? denseBadgeMin : badge.width + 8);
        badge.dispose();
      }
    }
    final gaps = chips.length - 1;
    return LayoutBuilder(
      builder: (context, box) {
        final roomy =
            text + badges + chips.length * 2 * PrivioSpacing.m + gaps * PrivioSpacing.s <=
            box.maxWidth - 2 * PrivioSpacing.l;
        final denseFixed = denseBadges + chips.length * 2 * densePad + gaps * denseGap;
        final scale = (box.maxWidth - 2 * denseEdge - denseFixed) / text;
        if (roomy || scale < minScale) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            children: [
              for (final (i, c) in chips.indexed)
                Padding(
                  padding: EdgeInsets.only(right: i == gaps ? 0 : PrivioSpacing.s),
                  child: c,
                ),
            ],
          );
        }
        final textScale = scale >= 1 ? 1.0 : scale * 0.98;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: denseEdge),
          child: Row(
            children: [
              for (final (i, c) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: denseGap),
                MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scaler.scale(1) * textScale)),
                  child: c.dense(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.isDense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;
  final bool isDense;

  FilterPill dense() => FilterPill(
    key: key,
    label: label,
    selected: selected,
    onTap: onTap,
    count: count,
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bg = selected ? (dark ? PrivioColors.lilac : PrivioColors.purpleDeep) : p.field;
    final fg = selected ? (dark ? PrivioColors.navy : Colors.white) : theme.colorScheme.onSurface;
    return Semantics(
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
              padding: EdgeInsets.symmetric(
                horizontal: isDense ? FilterBar.densePad : PrivioSpacing.m,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count > 0) ...[
                    SizedBox(width: isDense ? FilterBar.denseBadgeGap : PrivioSpacing.s),
                    _CountBadge(count: count, compact: isDense),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.compact = false});

  final int count;

  /// Pastille plus petite pour la barre de filtres resserrée (écran étroit).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(minWidth: compact ? FilterBar.denseBadgeMin : 22),
      height: compact ? FilterBar.denseBadgeMin : 22,
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? PrivioColors.lilac : PrivioColors.purple,
        borderRadius: BorderRadius.circular(compact ? 9 : 11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        // Pastille resserrée : taille fixe, jamais sous 11 px.
        textScaler: compact ? TextScaler.noScaling : null,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
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
        itemBuilder: (_, i) => SwipeableConversationTile(summary: items[i]),
      ),
    );
  }
}

/// Lot 7.2b2 : le bandeau « hors connexion » glisse en place puis se retire.
class AnimatedOfflineBanner extends StatelessWidget {
  const AnimatedOfflineBanner({super.key, required this.offline, this.top = 0});

  final bool offline;
  final double top;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.of(context, Motion.medium),
    transitionBuilder: (child, a) => SizeTransition(
      sizeFactor: CurvedAnimation(parent: a, curve: Motion.enter),
      child: FadeTransition(opacity: a, child: child),
    ),
    child: offline
        ? Padding(
            key: const ValueKey('offline'),
            padding: EdgeInsets.only(top: top),
            child: const OfflineBanner(),
          )
        : const SizedBox(key: ValueKey('online'), width: double.infinity),
  );
}

/// Hors connexion : les discussions enregistrées sur le téléphone restent lisibles.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('offline.banner'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.s),
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m, vertical: PrivioSpacing.s),
        decoration: BoxDecoration(
          color: p.notice,
          borderRadius: BorderRadius.circular(PrivioRadius.medium),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: p.warn),
            const SizedBox(width: PrivioSpacing.s),
            Expanded(
              child: Text(
                'Hors connexion. Vos messages partiront dès le retour du réseau.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Appui long sur une discussion : épingler / archiver (état personnel).
/// Lot 2.F : glisser à droite = épingler / désépingler ; à gauche = archiver / désarchiver.
class SwipeableConversationTile extends ConsumerWidget {
  const SwipeableConversationTile({super.key, required this.summary});

  final ConversationSummary summary;

  Future<void> _flags(BuildContext context, WidgetRef ref, {bool? pinned, bool? archived}) async {
    // Capturés AVANT l'action : une discussion archivée quitte l'écran, et sa ligne
    // (avec son ref) disparaît ; « Annuler » doit pourtant rester utilisable.
    final notifier = ref.read(conversationsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await notifier.setFlags(summary.id, pinned: pinned, archived: archived);
      if (archived != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(archived ? 'Discussion archivée.' : 'Discussion désarchivée.'),
            action: SnackBarAction(
              label: 'Annuler',
              onPressed: () => notifier.setFlags(summary.id, archived: !archived),
            ),
          ),
        );
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwipeActions(
    key: Key('swipe.${summary.id}'),
    right: SwipeAction(
      icon: summary.pinned ? Icons.push_pin_outlined : Icons.push_pin,
      label: summary.pinned ? 'Désépingler' : 'Épingler',
      onTriggered: () => _flags(context, ref, pinned: !summary.pinned),
    ),
    left: SwipeAction(
      icon: summary.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
      label: summary.archived ? 'Désarchiver' : 'Archiver',
      onTriggered: () => _flags(context, ref, archived: !summary.archived),
    ),
    child: ConversationTile(summary: summary),
  );
}

Future<void> showConversationActions(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary summary,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('conv.pin'),
            leading: Icon(summary.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(summary.pinned ? 'Désépingler' : 'Épingler en haut de la liste'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            key: const Key('conv.archive'),
            leading: Icon(summary.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(summary.archived ? 'Désarchiver' : 'Archiver'),
            subtitle: summary.archived
                ? null
                : const Text('Un nouveau message la fera réapparaître dans la liste.'),
            onTap: () => Navigator.pop(ctx, 'archive'),
          ),
          // Lot 7.2c1 : un groupe se quitte (et disparaît de la liste) ; le créateur et les
          // administrateurs peuvent aussi le supprimer pour tous.
          if (summary.isGroup)
            ListTile(
              key: const Key('conv.leave'),
              leading: Icon(Icons.logout, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Quitter et supprimer',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'leave'),
            ),
          if (summary.isGroup && summary.isAdmin && !summary.isClosed)
            ListTile(
              key: const Key('conv.delete_group'),
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Supprimer le groupe pour tous',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          // Lot 7.2b1 : supprimer une discussion à deux.
          if (!summary.isGroup)
            ListTile(
              key: const Key('conv.delete'),
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Supprimer la discussion',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'delete') {
    await chooseDelete(context, ref, summary);
    return;
  }
  if (action == 'leave') {
    await confirmLeaveGroup(context, ref, summary);
    return;
  }
  try {
    await ref
        .read(conversationsProvider.notifier)
        .setFlags(
          summary.id,
          pinned: action == 'pin' ? !summary.pinned : null,
          archived: action == 'archive' ? !summary.archived : null,
        );
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }
}

class ConversationTile extends ConsumerWidget {
  const ConversationTile({super.key, required this.summary});

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
    // Qui a écrit : « Vous : », ou le nom de l'expéditeur dans un groupe.
    final who = mine
        ? 'Vous\u202F: '
        : (summary.isGroup && summary.lastSenderName != null
              ? '${summary.lastSenderName}\u202F: '
              : '');
    final preview = switch (summary) {
      ConversationSummary(blocked: true) => 'Contact bloqué',
      ConversationSummary(:final clearRequestBy?) when clearRequestBy != me =>
        'Propose de vider la discussion',
      ConversationSummary(lastMessageId: null) =>
        summary.isGroup
            ? '${summary.memberCount} membre${summary.memberCount > 1 ? 's' : ''}'
            : 'Aucun message',
      ConversationSummary(lastDeleted: true) => 'Message supprimé',
      ConversationSummary(lastKind: 'system', :final lastBody)
          when (lastBody ?? '').startsWith('{') =>
        groupEventText(
              ChatMessage(
                id: summary.lastMessageId!,
                kind: 'system',
                senderId: summary.lastSenderId,
                body: lastBody,
                sentAt: summary.sortAt,
                expiresAt: summary.lastExpiresAt ?? summary.sortAt,
                updatedAt: summary.sortAt,
              ),
              me: me,
            ) ??
            '',
      ConversationSummary(lastKind: 'system') =>
        // typo-fr: ignore-next (rappel de durée inchangé, décision du 13/11/2026)
        'Durée des messages : ${formatTtl(summary.ttlSeconds)}',
      ConversationSummary(lastKind: 'voice') => '$who🎤 Message vocal',
      // Lot 7.3a : autocollant (son nom, pas son identifiant).
      ConversationSummary(lastKind: 'sticker', :final lastBody) =>
        '$who🙂 ${stickerOf(lastBody)?.label ?? 'Autocollant'}',
      // Lot 7.3b : GIF.
      ConversationSummary(lastKind: 'gif') => '${who}GIF',
      ConversationSummary(lastKind: 'photo', :final lastBody) =>
        '$who📷 ${lastBody == null || lastBody.isEmpty ? 'Photo' : lastBody}',
      _ => '$who${summary.lastBody ?? ''}',
    };
    final typing = !summary.blocked && ref.watch(typingProvider).contains(summary.id);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      key: Key('conversation.${summary.id}'),
      onTap: () => context.push(Routes.chat(summary.id)),
      onLongPress: () => showConversationActions(context, ref, summary),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              name: summary.title,
              avatarPath: summary.avatarPath,
              seed: summary.peerId ?? summary.id,
              icon: summary.isGroup ? Icons.groups_rounded : null,
            ),
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
                              typing ? 'en train d’écrire…' : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: typing
                                    ? p.accentText
                                    : (unread > 0 ? theme.colorScheme.onSurface : secondary),
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                fontStyle: typing ? FontStyle.italic : FontStyle.normal,
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
                                  // typo-fr: ignore-next (rappel de durée inchangé, décision du 13/11/2026)
                                  's\'efface dans ${formatRemaining(summary.lastExpiresAt!, now: now)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: p.warn,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (summary.isMuted(now)) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.notifications_off_outlined,
                              key: Key('muted.${summary.id}'),
                              size: 16,
                              color: secondary,
                              semanticLabel: 'En sourdine',
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

/// Lot 7.2c1 : recherche dans une liste (discussions ou groupes) : nom, identifiant, dernier
/// message, et messages encore présents sur ce téléphone.
bool matchesSearch(ConversationSummary c, String q, Map<String, List<ChatMessage>> local) {
  if (q.isEmpty) return true;
  final inMessages =
      !c.blocked &&
      (local[c.id] ?? const <ChatMessage>[]).any(
        (m) => !m.isDeleted && !m.isSticker && (m.body ?? '').toLowerCase().contains(q),
      );
  return inMessages ||
      c.title.toLowerCase().contains(q) ||
      (c.peerHandle ?? '').toLowerCase().contains(q) ||
      (!c.blocked && c.lastKind != 'sticker' && (c.lastBody ?? '').toLowerCase().contains(q));
}

/// Champ « Rechercher » des listes (Discussions, Groupes).
class ListSearchField extends StatelessWidget {
  const ListSearchField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final search = controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher',
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
          suffixIcon: search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  onPressed: search.clear,
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
    );
  }
}
