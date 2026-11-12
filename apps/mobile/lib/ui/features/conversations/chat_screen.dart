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

/// Réactions proposées (une seule par personne et par message).
const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// État d'un message envoyé, déduit des pointeurs d'accusés du correspondant.
enum Delivery { sent, delivered, read }

Delivery deliveryOf(ChatMessage m, ConversationSummary? s) {
  if (s?.peerReadUpTo != null && !s!.peerReadUpTo!.isBefore(m.sentAt)) return Delivery.read;
  if (s?.peerDeliveredUpTo != null && !s!.peerDeliveredUpTo!.isBefore(m.sentAt)) {
    return Delivery.delivered;
  }
  return Delivery.sent;
}

/// Écran 10 — conversation. Appui long sur un message : réagir, répondre, modifier
/// (60 min), supprimer pour moi ou pour tout le monde. Volontairement AUCUNE action
/// « copier » ni « transférer » (SEC-007/SEC-008) et aucun texte sélectionnable.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;
  Timer? _poll;
  ChatMessage? _replyTo;
  ChatMessage? _editing;

  ChatController get _chat => ref.read(chatProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    // Expiration à la seconde près côté affichage, même sans réseau.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    // Filet de sécurité si la connexion temps réel est coupée (réseaux instables) :
    // une conversation ouverte reste à jour à 5 secondes près.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _chat.reload();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    }
  }

  Future<void> _submit() async {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    final editing = _editing;
    final replyTo = _replyTo;
    _composer.clear();
    setState(() {
      _editing = null;
      _replyTo = null;
    });
    if (editing != null) {
      await _guard(() => _chat.edit(editing.id, text));
    } else {
      await _guard(() => _chat.send(text, replyToId: replyTo?.id));
    }
  }

  Future<void> _retry(PendingMessage p) =>
      _guard(() => _chat.send(p.body, clientId: p.clientId, replyToId: p.replyToId));

  Future<void> _showActions(ChatMessage m, {required bool mine}) async {
    if (m.isDeleted) return;
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final now = DateTime.now();
    final me = ref.read(currentUserIdProvider);
    final myReaction = m.reactions.where((r) => r.userId == me).firstOrNull?.emoji;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in kQuickReactions)
                    IconButton(
                      key: Key('react.$e'),
                      tooltip: e == myReaction ? 'Retirer $e' : 'Réagir $e',
                      isSelected: e == myReaction,
                      onPressed: () => Navigator.pop(ctx, 'react:$e'),
                      icon: Text(e, style: Theme.of(ctx).textTheme.headlineSmall),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              key: const Key('action.reply'),
              leading: const Icon(Icons.reply),
              title: const Text('Répondre'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (mine && rules.canEdit(m, now))
              ListTile(
                key: const Key('action.edit'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Modifier'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            ListTile(
              key: const Key('action.delete_me'),
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Supprimer pour moi'),
              onTap: () => Navigator.pop(ctx, 'delete_me'),
            ),
            if (mine && rules.canDeleteForAll(m, now))
              ListTile(
                key: const Key('action.delete_all'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(
                  'Supprimer pour tout le monde',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'delete_all'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      await _guard(() => _chat.toggleReaction(m.id, action.substring(6)));
    } else if (action == 'reply') {
      setState(() {
        _editing = null;
        _replyTo = m;
      });
      _focus.requestFocus();
    } else if (action == 'edit') {
      setState(() {
        _replyTo = null;
        _editing = m;
        _composer.text = m.body ?? '';
      });
      _focus.requestFocus();
    } else if (action == 'delete_me') {
      await _guard(() => _chat.deleteForMe(m.id));
    } else if (action == 'delete_all') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Supprimer pour tout le monde ?'),
          content: const Text('Le message sera effacé chez vous et chez votre correspondant.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              key: const Key('action.delete_all.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (ok == true) await _guard(() => _chat.deleteForEveryone(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(conversationSummaryProvider(widget.conversationId));
    final chat = ref.watch(chatProvider(widget.conversationId));
    ref.watch(messagingRulesProvider);
    final me = ref.watch(currentUserIdProvider);
    final now = DateTime.now();
    final title = summary?.title ?? 'Discussion';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          key: const Key('chat.contact'),
          onTap: summary?.peerId == null
              ? null
              : () => context.push(Routes.contact(widget.conversationId)),
          child: Row(
            children: [
              InitialAvatar(name: title, radius: 18),
              const SizedBox(width: PrivioSpacing.m),
              Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (chat) {
              AsyncData(:final value) => _MessageList(
                messages: value.messages.where((m) => m.isVisibleAt(now)).toList(),
                pending: value.pending,
                me: me,
                now: now,
                summary: summary,
                onRetry: _retry,
                onLongPress: (m) => _showActions(m, mine: m.senderId == me),
                onReactionTap: (m, emoji) => _guard(() => _chat.toggleReaction(m.id, emoji)),
              ),
              AsyncError(:final error) => ErrorView(
                message: toAppFailure(error).message,
                onRetry: () => ref.invalidate(chatProvider(widget.conversationId)),
              ),
              _ => const LoadingView(),
            },
          ),
          if (summary?.blocked ?? false)
            const Padding(
              padding: EdgeInsets.all(PrivioSpacing.l),
              child: NoticeBanner(
                message:
                    'Vous ne pouvez pas échanger de messages avec ce contact '
                    '(blocage). Gérez les blocages depuis la fiche du contact.',
              ),
            )
          else ...[
            if (_replyTo != null || _editing != null)
              _ComposerContext(
                label: _editing != null ? 'Modifier le message' : 'Répondre à',
                text: (_editing ?? _replyTo)!.body ?? '',
                onCancel: () => setState(() {
                  if (_editing != null) _composer.clear();
                  _editing = null;
                  _replyTo = null;
                }),
              ),
            _Composer(
              controller: _composer,
              focusNode: _focus,
              editing: _editing != null,
              onSend: _submit,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.pending,
    required this.me,
    required this.now,
    required this.summary,
    required this.onRetry,
    required this.onLongPress,
    required this.onReactionTap,
  });

  final List<ChatMessage> messages;
  final List<PendingMessage> pending;
  final String? me;
  final DateTime now;
  final ConversationSummary? summary;
  final void Function(PendingMessage) onRetry;
  final void Function(ChatMessage) onLongPress;
  final void Function(ChatMessage, String) onReactionTap;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && pending.isEmpty) {
      return const EmptyView(
        icon: Icons.timer_outlined,
        title: 'Aucun message',
        message: 'Les messages de cette discussion s\'effacent 72 heures après leur envoi.',
      );
    }
    final items = <Widget>[
      for (final m in messages)
        _Bubble(
          key: Key('message.${m.id}'),
          outgoing: m.senderId == me,
          text: m.isDeleted ? 'Message supprimé' : (m.body ?? ''),
          italic: m.isDeleted,
          quote: m.isDeleted ? null : m.replyPreview,
          meta:
              '${formatMessageTime(m.sentAt, now: now)}'
              '${m.editedAt != null && !m.isDeleted ? ' · modifié' : ''}'
              ' · expire dans ${formatRemaining(m.expiresAt, now: now)}',
          delivery: m.senderId == me && !m.isDeleted ? deliveryOf(m, summary) : null,
          reactions: m.reactions,
          me: me,
          onLongPress: () => onLongPress(m),
          onReactionTap: (emoji) => onReactionTap(m, emoji),
        ),
      for (final p in pending)
        _Bubble(
          key: Key('pending.${p.clientId}'),
          outgoing: true,
          text: p.body,
          meta: p.failed ? 'Échec de l\'envoi · toucher pour réessayer' : 'Envoi…',
          failed: p.failed,
          onTap: p.failed ? () => onRetry(p) : null,
        ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(PrivioSpacing.m),
      children: items.reversed.toList(),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.outgoing,
    required this.text,
    required this.meta,
    this.italic = false,
    this.failed = false,
    this.quote,
    this.delivery,
    this.reactions = const [],
    this.me,
    this.onTap,
    this.onLongPress,
    this.onReactionTap,
  });

  final bool outgoing;
  final String text;
  final String meta;
  final bool italic;
  final bool failed;
  final String? quote;
  final Delivery? delivery;
  final List<Reaction> reactions;
  final String? me;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReactionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = outgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = outgoing ? scheme.onPrimaryContainer : scheme.onSurface;
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final mine = reactions.where((r) => r.userId == me).firstOrNull?.emoji;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xs),
          child: Column(
            crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Material(
                color: bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PrivioRadius.large),
                  side: failed ? BorderSide(color: scheme.error) : BorderSide.none,
                ),
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: BorderRadius.circular(PrivioRadius.large),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PrivioSpacing.l,
                      vertical: PrivioSpacing.s,
                    ),
                    // Une bulle = une annonce TalkBack complète (texte, heure, état).
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (quote != null)
                            Container(
                              key: const Key('bubble.quote'),
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: PrivioSpacing.s),
                              padding: const EdgeInsets.all(PrivioSpacing.s),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(PrivioRadius.small),
                                border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                              ),
                              child: Text(
                                quote!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          Text(
                            text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: fg,
                              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(height: PrivioSpacing.xs),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  meta,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: failed ? scheme.error : fg,
                                  ),
                                ),
                              ),
                              if (delivery != null) ...[
                                const SizedBox(width: PrivioSpacing.xs),
                                _DeliveryIcon(delivery: delivery!, color: fg),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (counts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.xs),
                  child: Wrap(
                    spacing: PrivioSpacing.xs,
                    children: [
                      for (final e in counts.entries)
                        ActionChip(
                          key: Key('reaction.${e.key}'),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: e.key == mine ? scheme.primary : scheme.outlineVariant,
                          ),
                          label: Text(e.value > 1 ? '${e.key} ${e.value}' : e.key),
                          tooltip: e.key == mine ? 'Retirer ma réaction' : 'Réagir ${e.key}',
                          onPressed: onReactionTap == null ? null : () => onReactionTap!(e.key),
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

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.delivery, required this.color});

  final Delivery delivery;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, tint) = switch (delivery) {
      Delivery.sent => (Icons.done, 'Envoyé', color),
      Delivery.delivered => (Icons.done_all, 'Reçu', color),
      Delivery.read => (Icons.done_all, 'Lu', scheme.primary),
    };
    return Semantics(
      label: label,
      child: Icon(icon, key: Key('delivery.${delivery.name}'), size: 16, color: tint),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({required this.label, required this.text, required this.onCancel});

  final String label;
  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('composer.context'),
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.only(left: PrivioSpacing.l),
      child: Row(
        children: [
          Icon(Icons.reply, color: theme.colorScheme.primary),
          const SizedBox(width: PrivioSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('composer.cancel'),
            tooltip: 'Annuler',
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(PrivioSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat.input'),
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Écrire un message', counterText: ''),
            ),
          ),
          const SizedBox(width: PrivioSpacing.s),
          IconButton.filled(
            key: const Key('chat.send'),
            tooltip: editing ? 'Enregistrer la modification' : 'Envoyer',
            onPressed: onSend,
            icon: Icon(editing ? Icons.check : Icons.send),
          ),
        ],
      ),
    ),
  );
}
