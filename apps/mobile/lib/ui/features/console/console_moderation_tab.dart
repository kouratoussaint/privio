import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console_team.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/state_views.dart';
import 'console_reports_tab.dart' show consoleChip;

/// Lot 5.8 — suivi de la modération, réponses types, sites sans aperçu.

// ---------------------------------------------------------------------------
// Réponses types : choisir un texte (réponse d'assistance, motif de décision)
// ---------------------------------------------------------------------------
class TemplatePicker extends ConsumerWidget {
  const TemplatePicker({super.key, required this.kind, required this.onPick});

  /// « support » ou « decision ».
  final String kind;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = [
      for (final t in ref.watch(consoleTemplatesProvider).value ?? const <ConsoleTemplate>[])
        if (t.kind == kind) t,
    ];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Réponses types', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: PrivioSpacing.xs),
          Wrap(
            spacing: PrivioSpacing.s,
            runSpacing: PrivioSpacing.xs,
            children: [
              for (final t in list)
                ActionChip(
                  key: Key('template.pick.${t.id}'),
                  label: Text(t.title),
                  tooltip: t.body,
                  onPressed: () => onPick(t.body),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suivi de la modération
// ---------------------------------------------------------------------------
class ConsoleModerationStatsTab extends ConsumerStatefulWidget {
  const ConsoleModerationStatsTab({super.key});

  @override
  ConsumerState<ConsoleModerationStatsTab> createState() => _ModerationStatsState();
}

class _ModerationStatsState extends ConsumerState<ConsoleModerationStatsTab> {
  int _days = 7;

  static const _decisions = {
    'dismissed': 'Classés sans suite',
    'warned': 'Avertissements',
    'suspended': 'Suspensions',
    'message_deleted': 'Messages supprimés',
    'group_closed': 'Groupes fermés',
    'group_deleted': 'Groupes supprimés',
  };

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(moderationStatsProvider(_days));
    final theme = Theme.of(context);
    return ListView(
      key: const Key('modstats.view'),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        Wrap(
          spacing: PrivioSpacing.s,
          children: [
            for (final d in [7, 30])
              consoleChip(
                context,
                key: Key('modstats.days.$d'),
                label: '$d jours',
                selected: _days == d,
                onTap: () => setState(() => _days = d),
              ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.m),
        switch (stats) {
          AsyncData(value: final s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Figures(
                items: [
                  ('modstats.received', 'Signalements reçus', '${s.received}'),
                  ('modstats.decided', 'Dossiers traités', '${s.decided}'),
                  ('modstats.open', 'En attente', '${s.openNow}'),
                  ('modstats.avg', 'Délai moyen', s.avgHours == null ? '—' : _hours(s.avgHours!)),
                  (
                    'modstats.oldest',
                    'Plus ancien en attente',
                    s.oldestOpenHours == null ? '—' : _hours(s.oldestOpenHours!.toDouble()),
                  ),
                  ('modstats.appeals', 'Contestations', '${s.appeals}'),
                  ('modstats.support', 'Demandes d’assistance', '${s.supportReceived}'),
                  ('modstats.answered', 'Réponses envoyées', '${s.supportAnswered}'),
                ],
              ),
              if (s.byReason.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.l),
                Text('Par motif', style: theme.textTheme.titleMedium),
                for (final e in s.byReason.entries)
                  _Row(label: reasonLabel(e.key), value: '${e.value}'),
              ],
              if (s.byDecision.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.l),
                Text('Par décision', style: theme.textTheme.titleMedium),
                for (final e in s.byDecision.entries)
                  _Row(label: _decisions[e.key] ?? e.key, value: '${e.value}'),
              ],
              const SizedBox(height: PrivioSpacing.l),
              Text('Par personne', style: theme.textTheme.titleMedium),
              if (s.byPerson.isEmpty)
                const Text('Aucune décision sur la période.')
              else
                for (final p in s.byPerson)
                  _Row(
                    key: Key('modstats.person.${p.name}'),
                    label: '${p.name}${p.role == null ? '' : ' · ${p.role!.label.toLowerCase()}'}',
                    value: '${p.decided}${p.avgHours == null ? '' : ' · ${_hours(p.avgHours!)}'}',
                  ),
            ],
          ),
          AsyncError(:final error) => ErrorView(
            message: toAppFailure(error).message,
            onRetry: () => ref.invalidate(moderationStatsProvider(_days)),
          ),
          _ => const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
        },
      ],
    );
  }

  static String _hours(double h) =>
      h < 1 ? '${(h * 60).round()} min' : (h < 48 ? '${h.round()} h' : '${(h / 24).round()} j');
}

class _Figures extends StatelessWidget {
  const _Figures({required this.items});

  final List<(String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - PrivioSpacing.m) / 2;
        return Wrap(
          spacing: PrivioSpacing.m,
          runSpacing: PrivioSpacing.m,
          children: [
            for (final (id, label, value) in items)
              SizedBox(
                width: w,
                child: Column(
                  key: Key(id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Réponses types
// ---------------------------------------------------------------------------
class ConsoleTemplatesTab extends ConsumerWidget {
  const ConsoleTemplatesTab({super.key, required this.owner});

  /// Seul le propriétaire écrit les réponses types ; l'équipe les lit.
  final bool owner;

  static const _kinds = {'support': 'Réponses d’assistance', 'decision': 'Motifs de décision'};

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    ConsoleTemplate? t,
    String? kind,
  }) async {
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _TemplateDialog(template: t, kind: kind ?? t?.kind ?? 'support'),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminApiProvider)
          .saveTemplate(id: t?.id, kind: result.$1, title: result.$2, body: result.$3);
      ref.invalidate(consoleTemplatesProvider);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ConsoleTemplate t) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).deleteTemplate(t.id);
      ref.invalidate(consoleTemplatesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Réponse type retirée.')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(consoleTemplatesProvider);
    final theme = Theme.of(context);
    return switch (list) {
      AsyncData(:final value) => ListView(
        key: const Key('templates.list'),
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.m,
          PrivioSpacing.m,
          PrivioSpacing.m,
          PrivioSpacing.xxl,
        ),
        children: [
          Text(
            owner
                ? 'Textes proposés à l’équipe pour répondre aux demandes d’assistance et pour '
                      'motiver les décisions. Toujours modifiables avant l’envoi.'
                : 'Textes proposés quand vous répondez ou décidez. Seul le propriétaire les modifie.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final k in _kinds.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: PrivioSpacing.l, bottom: PrivioSpacing.s),
              child: Row(
                children: [
                  Expanded(child: Text(k.value, style: theme.textTheme.titleMedium)),
                  if (owner)
                    IconButton(
                      key: Key('templates.add.${k.key}'),
                      tooltip: 'Ajouter',
                      icon: const Icon(Icons.add),
                      onPressed: () => _edit(context, ref, kind: k.key),
                    ),
                ],
              ),
            ),
            for (final t in value)
              if (t.kind == k.key)
                Card(
                  key: Key('template.${t.id}'),
                  margin: const EdgeInsets.only(bottom: PrivioSpacing.s),
                  child: ListTile(
                    title: Text(t.title),
                    subtitle: Text(t.body),
                    onTap: owner ? () => _edit(context, ref, t: t) : null,
                    trailing: owner
                        ? IconButton(
                            key: Key('template.delete.${t.id}'),
                            tooltip: 'Retirer',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, ref, t),
                          )
                        : null,
                  ),
                ),
          ],
        ],
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleTemplatesProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.kind, this.template});

  final String kind;
  final ConsoleTemplate? template;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _title = TextEditingController(text: widget.template?.title);
  late final _body = TextEditingController(text: widget.template?.body);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.kind == 'decision' ? 500 : 1000;
    final ok = _title.text.trim().isNotEmpty && _body.text.trim().length >= 2;
    return AlertDialog(
      key: const Key('template.dialog'),
      title: Text(widget.template == null ? 'Nouvelle réponse type' : 'Modifier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('template.title'),
              controller: _title,
              maxLength: 60,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Titre court'),
            ),
            TextField(
              key: const Key('template.body'),
              controller: _body,
              maxLength: max,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Texte'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('template.save'),
          onPressed: ok
              ? () => Navigator.pop(context, (widget.kind, _title.text.trim(), _body.text.trim()))
              : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sites sans aperçu
// ---------------------------------------------------------------------------
class ConsoleSitesTab extends ConsumerStatefulWidget {
  const ConsoleSitesTab({super.key});

  @override
  ConsumerState<ConsoleSitesTab> createState() => _ConsoleSitesTabState();
}

class _ConsoleSitesTabState extends ConsumerState<ConsoleSitesTab> {
  final _site = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _site.dispose();
    super.dispose();
  }

  Future<void> _set(String site, bool blocked) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final domain = await ref.read(adminApiProvider).blockSite(site, blocked: blocked);
      if (blocked) _site.clear();
      ref.invalidate(blockedSitesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            blocked ? '$domain\u202F: plus d’aperçu.' : '$domain\u202F: aperçus rétablis.',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(blockedSitesProvider);
    final theme = Theme.of(context);
    return ListView(
      key: const Key('sites.view'),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.m,
        PrivioSpacing.m,
        PrivioSpacing.m,
        PrivioSpacing.xxl,
      ),
      children: [
        Text(
          'Un lien vers ces sites (et leurs sous-domaines) est envoyé normalement, mais sans '
          'aperçu\u202F: Privio ne lit pas la page.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: PrivioSpacing.m),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('sites.input'),
                controller: _site,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Site ou adresse',
                  hintText: 'exemple.com',
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.s),
            FilledButton(
              key: const Key('sites.add'),
              onPressed: _busy || _site.text.trim().length < 4
                  ? null
                  : () => _set(_site.text.trim(), true),
              child: const Text('Bloquer'),
            ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.m),
        switch (list) {
          AsyncData(:final value) when value.isEmpty => const Padding(
            padding: EdgeInsets.all(PrivioSpacing.l),
            child: Text('Aucun site pour l’instant.'),
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final d in value)
                ListTile(
                  key: Key('site.$d'),
                  leading: const Icon(Icons.link_off_rounded),
                  title: Text(d),
                  trailing: IconButton(
                    key: Key('site.remove.$d'),
                    tooltip: 'Rétablir les aperçus',
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => _set(d, false),
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => ErrorView(
            message: toAppFailure(error).message,
            onRetry: () => ref.invalidate(blockedSitesProvider),
          ),
          _ => const LoadingView(),
        },
      ],
    );
  }
}
