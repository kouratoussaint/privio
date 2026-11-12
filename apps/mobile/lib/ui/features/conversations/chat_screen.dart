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

/// Écran 10 — conversation (version de base, lot 2.2) : lecture et envoi de texte.
/// Accusés, réponses, réactions, modification et suppression : lot 2.3.
/// Aucun texte n'est sélectionnable ni copiable (SEC-007/SEC-008).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  Timer? _tick;
  Timer? _poll;

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
      if (mounted) ref.read(chatProvider(widget.conversationId).notifier).reload();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send([String? text, String? clientId]) async {
    final body = text ?? _composer.text;
    if (body.trim().isEmpty) return;
    if (text == null) _composer.clear();
    try {
      await ref.read(chatProvider(widget.conversationId).notifier).send(body, clientId: clientId);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(conversationSummaryProvider(widget.conversationId));
    final chat = ref.watch(chatProvider(widget.conversationId));
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
                onRetry: (p) => _send(p.body, p.clientId),
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
          else
            _Composer(controller: _composer, onSend: _send),
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
    required this.onRetry,
  });

  final List<ChatMessage> messages;
  final List<PendingMessage> pending;
  final String? me;
  final DateTime now;
  final void Function(PendingMessage) onRetry;

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
          meta:
              '${formatMessageTime(m.sentAt, now: now)}'
              '${m.editedAt != null ? ' · modifié' : ''}'
              ' · expire dans ${formatRemaining(m.expiresAt, now: now)}',
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
    this.onTap,
  });

  final bool outgoing;
  final String text;
  final String meta;
  final bool italic;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = outgoing ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = outgoing ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xs),
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PrivioRadius.large),
              side: failed ? BorderSide(color: scheme.error) : BorderSide.none,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(PrivioRadius.large),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PrivioSpacing.l,
                  vertical: PrivioSpacing.s,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: fg,
                        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      meta,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: failed ? scheme.error : fg,
                      ),
                    ),
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

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
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
            tooltip: 'Envoyer',
            onPressed: onSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}
