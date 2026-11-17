import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/success_snack.dart';

/// Lot 10.5 — sondages éphémères (ADR-049) : création, vote, résultats, fermeture.

/// Brouillon d'un sondage, rendu par [PollComposerScreen].
class PollDraft {
  const PollDraft({
    required this.question,
    required this.options,
    required this.multi,
    required this.anonymous,
  });

  final String question;
  final List<String> options;
  final bool multi;
  final bool anonymous;
}

/// Nettoie un brouillon : choix vides retirés ; null s'il n'est pas valable (question,
/// 2 à 10 choix différents).
PollDraft? cleanPollDraft(
  String question,
  List<String> options, {
  bool multi = false,
  bool anonymous = true,
}) {
  String clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
  final q = clean(question);
  final opts = [
    for (final o in options.map(clean))
      if (o.isNotEmpty) o,
  ];
  final distinct = {for (final o in opts) o.toLowerCase()};
  if (q.isEmpty || q.length > 200 || opts.length < 2 || opts.length > 10) return null;
  if (distinct.length != opts.length || opts.any((o) => o.length > 80)) return null;
  return PollDraft(question: q, options: opts, multi: multi, anonymous: anonymous);
}

/// Ouvre l'écran de création, puis envoie le sondage dans [conversationId].
Future<void> createPoll(
  BuildContext context,
  WidgetRef ref,
  String conversationId, {
  int? ttlSeconds,
}) async {
  final draft = await Navigator.of(context).push<PollDraft>(
    MaterialPageRoute(builder: (_) => const PollComposerScreen(), fullscreenDialog: true),
  );
  if (draft == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(chatProvider(conversationId).notifier)
        .sendPoll(
          question: draft.question,
          options: draft.options,
          multi: draft.multi,
          anonymous: draft.anonymous,
          ttlSeconds: ttlSeconds,
        );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

class PollComposerScreen extends StatefulWidget {
  const PollComposerScreen({super.key});

  @override
  State<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends State<PollComposerScreen> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multi = false;
  bool _anonymous = true;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _send() {
    final draft = cleanPollDraft(
      _question.text,
      [for (final c in _options) c.text],
      multi: _multi,
      anonymous: _anonymous,
    );
    if (draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t.sondageInvalide)));
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L.t.nouveauSondage),
        actions: [
          TextButton(key: const Key('poll.send'), onPressed: _send, child: Text(L.t.envoyer)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        children: [
          TextField(
            key: const Key('poll.question'),
            controller: _question,
            autofocus: true,
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: L.t.sondageQuestion),
          ),
          const SizedBox(height: PrivioSpacing.s),
          for (var i = 0; i < _options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
              child: TextField(
                key: Key('poll.option.$i'),
                controller: _options[i],
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: L.t.sondageChoix(i + 1),
                  counterText: '',
                  suffixIcon: _options.length > 2
                      ? IconButton(
                          key: Key('poll.option.$i.remove'),
                          tooltip: L.t.retirer,
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _options.removeAt(i).dispose()),
                        )
                      : null,
                ),
              ),
            ),
          if (_options.length < 10)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('poll.add_option'),
                onPressed: () => setState(() => _options.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: Text(L.t.sondageAjouterChoix),
              ),
            ),
          const Divider(),
          SwitchListTile(
            key: const Key('poll.multi'),
            contentPadding: EdgeInsets.zero,
            value: _multi,
            onChanged: (v) => setState(() => _multi = v),
            title: Text(L.t.sondagePlusieursReponses),
          ),
          SwitchListTile(
            key: const Key('poll.anonymous'),
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: Text(L.t.sondageVoteAnonyme),
            subtitle: Text(_anonymous ? L.t.sondageVoteAnonymeAide : L.t.sondageVotesVisiblesAide),
          ),
          const SizedBox(height: PrivioSpacing.m),
          Text(
            L.t.sondageEphemereAide,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Contenu d'une bulle de sondage : question, choix, totaux, vote.
class PollContent extends ConsumerStatefulWidget {
  const PollContent({
    super.key,
    required this.message,
    required this.conversationId,
    required this.outgoing,
    required this.nameOf,
  });

  final ChatMessage message;
  final String conversationId;
  final bool outgoing;

  /// Nom d'un votant (votes visibles).
  final String Function(String userId) nameOf;

  @override
  ConsumerState<PollContent> createState() => _PollContentState();
}

class _PollContentState extends ConsumerState<PollContent> {
  bool _busy = false;

  Future<void> _vote(List<int> options) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(chatProvider(widget.conversationId).notifier)
          .votePoll(widget.message.id, options);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(PollState poll, int i) {
    if (poll.closed) return;
    if (poll.multi) {
      final next = {...poll.mine};
      next.contains(i) ? next.remove(i) : next.add(i);
      unawaited(_vote(next.toList()..sort()));
    } else if (!(poll.mine.length == 1 && poll.mine.single == i)) {
      unawaited(_vote([i]));
    }
  }

  void _showVotes(PollState poll) {
    final byOption = poll.byOption;
    if (byOption == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            key: const Key('poll.votes'),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.l,
              0,
              PrivioSpacing.l,
              PrivioSpacing.l,
            ),
            children: [
              Text(widget.message.body ?? '', style: Theme.of(ctx).textTheme.titleMedium),
              for (var i = 0; i < poll.options.length; i++) ...[
                const SizedBox(height: PrivioSpacing.m),
                Text(
                  '${poll.options[i]} · ${L.t.sondageVotes(poll.counts.elementAtOrNull(i) ?? 0)}',
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
                for (final id in byOption.elementAtOrNull(i) ?? const <String>[])
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.nameOf(id)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final poll = widget.message.poll;
    final question = widget.message.body ?? '';
    if (poll == null) return Text(question);
    final total = poll.totalVotes;
    final showResults = poll.voted || poll.closed || widget.outgoing;
    final accent = p.accentText;
    final muted = theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      child: Column(
        key: Key('poll.${widget.message.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.poll_outlined, size: 20, color: accent),
              const SizedBox(width: PrivioSpacing.s),
              Expanded(
                child: Text(
                  question,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              poll.multi ? L.t.sondagePlusieursLabel : L.t.sondageUneReponse,
              poll.anonymous ? L.t.sondageVoteAnonyme : L.t.sondageVotesVisibles,
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
          const SizedBox(height: PrivioSpacing.s),
          for (var i = 0; i < poll.options.length; i++)
            _PollOption(
              key: Key('poll.${widget.message.id}.option.$i'),
              label: poll.options[i],
              count: poll.counts.elementAtOrNull(i) ?? 0,
              total: total,
              selected: poll.mine.contains(i),
              multi: poll.multi,
              showResults: showResults,
              enabled: !poll.closed && !_busy,
              accent: accent,
              onTap: () => _tap(poll, i),
            ),
          const SizedBox(height: PrivioSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: PrivioSpacing.s,
            children: [
              Text(
                poll.closed
                    ? '${L.t.sondageFerme} · ${L.t.sondageVotants(poll.voters)}'
                    : L.t.sondageVotants(poll.voters),
                key: Key('poll.${widget.message.id}.voters'),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              if (poll.voted && !poll.closed)
                TextButton(
                  key: Key('poll.${widget.message.id}.unvote'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: _busy ? null : () => unawaited(_vote(const [])),
                  child: Text(L.t.sondageRetirerVote),
                ),
              if (poll.byOption != null && total > 0)
                TextButton(
                  key: Key('poll.${widget.message.id}.show_votes'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _showVotes(poll),
                  child: Text(L.t.sondageVoirVotes),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    super.key,
    required this.label,
    required this.count,
    required this.total,
    required this.selected,
    required this.multi,
    required this.showResults,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final int count;
  final int total;
  final bool selected;
  final bool multi;
  final bool showResults;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = multi
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return Semantics(
      button: enabled,
      selected: selected,
      label: showResults ? '$label, ${L.t.sondageVotes(count)}' : label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: selected ? accent : theme.colorScheme.outline),
                  const SizedBox(width: PrivioSpacing.s),
                  Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                  if (showResults)
                    Text('$count', style: theme.textTheme.labelMedium?.copyWith(color: accent)),
                ],
              ),
              if (showResults)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : count / total,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.15),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fermer mon sondage, après confirmation.
Future<void> confirmClosePoll(
  BuildContext context,
  WidgetRef ref,
  ChatMessage m,
  String conversationId,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L.t.sondageFermer),
      content: Text(L.t.sondageFermerConfirm),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('poll.close.confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.t.sondageFermer),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(chatProvider(conversationId).notifier).closePoll(m.id);
    messenger.showSnackBar(successSnack(L.t.sondageFerme));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}
