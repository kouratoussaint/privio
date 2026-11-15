import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/avatar.dart';

/// Lot 7.2c2 : messages épinglés, favoris, infos d'un message, « Mentions seulement ».

/// Aperçu court d'un message épinglé ou favori.
String messageRefPreview(MessageRef r) => switch (r.kind) {
  'voice' => '🎤 Message vocal',
  'photo' => r.body == null || r.body!.isEmpty ? '📷 Photo' : '📷 ${r.body}',
  _ => r.body ?? '',
};

/// Heure lisible : « 18:32 » aujourd'hui, sinon « 13 nov. 18:32 ».
String receiptTime(DateTime at, {DateTime? now}) {
  final a = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final sameDay = a.year == n.year && a.month == n.month && a.day == n.day;
  return sameDay ? DateFormat.Hm('fr').format(a) : DateFormat('d MMM HH:mm', 'fr').format(a);
}

/// Bandeau des messages épinglés, sous l'en-tête de la discussion. Toucher montre le
/// message affiché, puis passe au suivant.
class PinnedBanner extends StatelessWidget {
  const PinnedBanner({super.key, required this.pins, required this.index, required this.onTap});

  final List<MessageRef> pins;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final i = index % pins.length;
    final r = pins[i];
    final who = r.senderName == null ? '' : '${r.senderName} : ';
    return Material(
      color: p.sheet,
      elevation: 1,
      child: InkWell(
        key: const Key('chat.pinned_banner'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, 8, PrivioSpacing.m, 8),
          child: Row(
            children: [
              // Un trait par message épinglé ; celui affiché est plein.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var k = 0; k < pins.length; k++)
                    Container(
                      width: 3,
                      height: pins.length == 1 ? 30 : 24 / pins.length + 4,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: k == i ? 1 : 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: PrivioSpacing.s),
              Icon(Icons.push_pin_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: PrivioSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pins.length > 1
                          ? 'Message épinglé ${i + 1}/${pins.length}'
                          : 'Message épinglé',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$who${messageRefPreview(r)}',
                      key: const Key('chat.pinned_text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message épinglé ou favori trop ancien pour être affiché dans la discussion : on le
/// montre ici.
Future<void> showMessageRef(BuildContext context, MessageRef r, {required String title}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          key: const Key('message_ref.sheet'),
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                '${r.senderName ?? 'Vous'} · ${receiptTime(r.sentAt)}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.m),
              Text(messageRefPreview(r), style: Theme.of(ctx).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );

/// Infos d'un de mes messages : envoyé, puis distribué et lu (par membre dans un groupe).
Future<void> showMessageInfo(BuildContext context, ChatMessage m, {required bool group}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _MessageInfoSheet(message: m, group: group),
    );

class _MessageInfoSheet extends ConsumerWidget {
  const _MessageInfoSheet({required this.message, required this.group});

  final ChatMessage message;
  final bool group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final info = ref.watch(messageInfoProvider(message.id));
    String delivered(MessageReceipt r) => !r.delivered
        ? 'Pas encore distribué'
        : r.deliveredAt == null
        ? 'Distribué'
        : 'Distribué à ${receiptTime(r.deliveredAt!)}';
    String read(MessageReceipt r) => r.receiptsHidden
        ? 'Lecture non partagée'
        : !r.read
        ? 'Pas encore lu'
        : r.readAt == null
        ? 'Lu'
        : 'Lu à ${receiptTime(r.readAt!)}';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          key: const Key('message_info.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
              child: Text('Infos du message', style: theme.textTheme.titleMedium),
            ),
            ListTile(
              leading: Icon(Icons.schedule_send_outlined, color: p.accentText),
              title: const Text('Envoyé'),
              subtitle: Text(receiptTime(message.sentAt)),
            ),
            const Divider(height: 1),
            Flexible(
              child: switch (info) {
                AsyncData(:final value) when value.isEmpty => const Padding(
                  padding: EdgeInsets.all(PrivioSpacing.l),
                  child: Text('Aucun destinataire pour l’instant.'),
                ),
                AsyncData(:final value) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in value)
                      ListTile(
                        key: Key('message_info.${r.userId}'),
                        leading: Icon(
                          r.read
                              ? Icons.done_all_rounded
                              : r.delivered
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          color: r.read ? theme.colorScheme.primary : p.accentText,
                        ),
                        title: Text(group ? r.name : delivered(r)),
                        subtitle: Text(group ? '${delivered(r)} · ${read(r)}' : read(r)),
                      ),
                  ],
                ),
                AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.l),
                  child: Text(toAppFailure(error).message),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(PrivioSpacing.l),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
            const SizedBox(height: PrivioSpacing.m),
          ],
        ),
      ),
    );
  }
}

/// Ligne « Messages favoris » d'une fiche.
class FavoritesRow extends ConsumerWidget {
  const FavoritesRow({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final n = ref.watch(favoriteMessagesProvider(conversationId)).value?.length;
    return ListTile(
      key: const Key('fiche.favorites'),
      leading: Icon(Icons.star_outline_rounded, color: p.accentText),
      title: const Text('Messages favoris'),
      subtitle: Text(
        n == null || n == 0
            ? 'Aucun pour l’instant'
            : '$n message${n > 1 ? 's' : ''} · s’effacent avec les messages',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FavoritesScreen(conversationId: conversationId, title: title),
        ),
      ),
    );
  }
}

/// Mes messages favoris d'une discussion. Toucher : retour au message dans la discussion.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final favorites = ref.watch(favoriteMessagesProvider(conversationId));
    return Scaffold(
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: const Text('Messages favoris')),
      body: switch (favorites) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.star_outline_rounded,
          title: 'Aucun message favori',
          message:
              'Appui long sur un message, puis « Ajouter aux favoris ». Un favori '
              's’efface en même temps que le message.',
        ),
        AsyncData(:final value) => ListView.separated(
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = value[i];
            return ListTile(
              key: Key('favorite.${r.id}'),
              title: Text(messageRefPreview(r), maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${r.senderName ?? 'Vous'} · ${receiptTime(r.sentAt)}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: IconButton(
                key: Key('favorite.remove.${r.id}'),
                tooltip: 'Retirer des favoris',
                icon: Icon(Icons.star_rounded, color: theme.colorScheme.primary),
                onPressed: () async {
                  try {
                    await ref.read(messagingApiProvider).setFavorites([r.id], on: false);
                  } on Object catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                    }
                  }
                  ref.invalidate(favoriteMessagesProvider(conversationId));
                },
              ),
              onTap: () {
                ref.read(jumpToMessageProvider.notifier).request(conversationId, r.id);
                context.go(Routes.chat(conversationId));
              },
            );
          },
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(favoriteMessagesProvider(conversationId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

/// Groupe : « Mentions seulement » (notifié seulement quand on vous @mentionne).
class MentionsOnlyTile extends ConsumerWidget {
  const MentionsOnlyTile({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final mode = ref.watch(notifyModeProvider(conversationId)).value;
    return SwitchListTile(
      key: const Key('group.mentions_only'),
      secondary: Icon(Icons.alternate_email_rounded, color: p.accentText),
      title: const Text('Mentions seulement'),
      subtitle: const Text('Notifié seulement quand quelqu’un vous @mentionne'),
      value: mode == 'mentions',
      onChanged: mode == null
          ? null
          : (on) async {
              try {
                await ref
                    .read(messagingApiProvider)
                    .setNotifyMode(conversationId, on ? 'mentions' : 'all');
              } on Object catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                }
              }
              ref.invalidate(notifyModeProvider(conversationId));
            },
    );
  }
}

/// Lot 8.1b : qui a réagi à un message (appui simple sur une réaction). Un onglet
/// « Toutes » puis un onglet par émoji ; toucher ma ligne retire ma réaction.
Future<void> showReactionsSheet(
  BuildContext context, {
  required List<Reaction> reactions,
  required String? me,
  required ({String name, String? path, String seed}) Function(String userId) who,
  required void Function(String emoji) onRemoveMine,
}) {
  final byEmoji = <String, List<Reaction>>{};
  for (final r in reactions) {
    (byEmoji[r.emoji] ??= []).add(r);
  }
  // Ma réaction en tête, puis les autres.
  List<Reaction> ordered(List<Reaction> list) => [
    ...list.where((r) => r.userId == me),
    ...list.where((r) => r.userId != me),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget list(List<Reaction> items) => ListView(
        shrinkWrap: true,
        children: [
          for (final r in ordered(items))
            Builder(
              builder: (_) {
                final w = who(r.userId);
                final mine = r.userId == me;
                return ListTile(
                  key: Key('reactions.row.${r.userId}.${r.emoji}'),
                  leading: UserAvatar(name: w.name, avatarPath: w.path, seed: w.seed, radius: 20),
                  title: Text(mine ? 'Vous' : w.name),
                  subtitle: mine ? const Text('Toucher pour retirer') : null,
                  trailing: Text(r.emoji, style: theme.textTheme.titleLarge),
                  onTap: mine
                      ? () {
                          Navigator.pop(ctx);
                          onRemoveMine(r.emoji);
                        }
                      : null,
                );
              },
            ),
        ],
      );
      return SafeArea(
        child: SizedBox(
          key: const Key('reactions.sheet'),
          height: MediaQuery.sizeOf(ctx).height * 0.5,
          child: DefaultTabController(
            length: byEmoji.length + 1,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: theme.colorScheme.primary,
                  indicatorColor: theme.colorScheme.primary,
                  tabs: [
                    Tab(key: const Key('reactions.tab.all'), text: 'Toutes ${reactions.length}'),
                    for (final e in byEmoji.entries)
                      Tab(key: Key('reactions.tab.${e.key}'), text: '${e.key} ${e.value.length}'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [list(reactions), for (final e in byEmoji.values) list(e)],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
