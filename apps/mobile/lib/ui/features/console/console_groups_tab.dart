import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console_team.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import 'console_accounts_tab.dart' show ConsolePager;
import 'console_moderation_tab.dart' show TemplatePicker;
import 'console_pilot_tab.dart' show OverridesCard;
import 'console_ui.dart';
import 'console_screen.dart' show ConsoleBackHandler;

/// Lot 5.8 — « Groupes » (propriétaire et modérateurs) : titre, type, membres, création,
/// signalements. Jamais les messages. Fermer, rouvrir ou supprimer, motif obligatoire.
class ConsoleGroupsTab extends ConsumerStatefulWidget {
  const ConsoleGroupsTab({super.key});

  @override
  ConsumerState<ConsoleGroupsTab> createState() => _ConsoleGroupsTabState();
}

class _ConsoleGroupsTabState extends ConsumerState<ConsoleGroupsTab> with ConsoleBackHandler {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'all';
  int _page = 1;
  String? _open;

  @override
  bool handleBack() {
    if (_open == null) return false;
    setState(() => _open = null);
    return true;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(consoleGroupsPageProvider);

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return _GroupView(
        id: open,
        onBack: () {
          setState(() => _open = null);
          _refresh();
        },
      );
    }
    final page = ref.watch(consoleGroupsPageProvider((_query, _filter, _page)));
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.m, PrivioSpacing.m, 0),
          child: TextField(
            key: const Key('groups.search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() {
              _query = v.trim();
              _page = 1;
            }),
            decoration: InputDecoration(
              hintText: 'Rechercher un groupe par son nom',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _page = 1;
                      }),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
          child: ConsoleFilterRow(
            children: [
              for (final e in kGroupFilters.entries)
                consoleChip(
                  context,
                  key: Key('groups.filter.${e.key}'),
                  label: e.value,
                  selected: _filter == e.key,
                  onTap: () => setState(() {
                    _filter = e.key;
                    _page = 1;
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (page) {
            AsyncData(:final value) when value.rows.isEmpty => ListView(
              children: const [
                SizedBox(height: 60),
                EmptyView(
                  icon: Icons.groups_outlined,
                  title: 'Aucun groupe',
                  message: 'Aucun groupe ne correspond à cette recherche.',
                ),
              ],
            ),
            AsyncData(:final value) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${value.total} groupe${value.total > 1 ? 's' : ''}',
                      key: const Key('groups.total'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const Key('groups.list'),
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.m,
                      PrivioSpacing.s,
                      PrivioSpacing.m,
                      PrivioSpacing.l,
                    ),
                    children: [
                      // Lot 5.10 : liste dans une carte, comme les comptes.
                      SettingsCard(
                        children: [
                          for (final (i, g) in value.rows.indexed) ...[
                            if (i > 0) const SettingsDivider(),
                            ListTile(
                              key: Key('group.${g.id}'),
                              leading: CircleAvatar(
                                child: Icon(
                                  g.announcement ? Icons.campaign_outlined : Icons.groups_outlined,
                                ),
                              ),
                              title: Text(g.title),
                              subtitle: Text(
                                [
                                  '${g.members} membre${g.members > 1 ? 's' : ''}'
                                      '${g.announcement ? ' · Annonces' : ''}'
                                      '${g.closed ? ' · fermé' : ''}',
                                  if (g.reportsOpen > 0)
                                    '${g.reportsOpen} signalement${g.reportsOpen > 1 ? 's' : ''} en attente',
                                ].join('\n'),
                              ),
                              trailing: g.reportsOpen > 0
                                  ? Icon(Icons.flag, color: theme.colorScheme.error)
                                  : const Icon(Icons.chevron_right),
                              onTap: () => setState(() => _open = g.id),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                ConsolePager(
                  page: value.page,
                  pages: value.pages,
                  color: theme.colorScheme.primary,
                  onPage: (p) => setState(() => _page = p),
                ),
              ],
            ),
            AsyncError(:final error) => ErrorView(
              message: toAppFailure(error).message,
              onRetry: _refresh,
            ),
            _ => const LoadingView(),
          },
        ),
      ],
    );
  }
}

final _groupProvider = FutureProvider.autoDispose.family<ConsoleGroup, String>(
  (ref, id) => ref.watch(adminApiProvider).group(id),
);

class _GroupView extends ConsumerStatefulWidget {
  const _GroupView({required this.id, required this.onBack});

  final String id;
  final VoidCallback onBack;

  @override
  ConsumerState<_GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends ConsumerState<_GroupView> {
  bool _busy = false;

  Future<void> _act(ConsoleGroup g, String action) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _GroupActionDialog(group: g, action: action),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).groupAction(g.id, action, note);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            'close' => 'Groupe fermé.',
            'reopen' => 'Groupe rouvert.',
            _ => 'Groupe supprimé.',
          }),
        ),
      );
      if (action == 'delete') {
        widget.onBack();
        return;
      }
      ref.invalidate(_groupProvider(g.id));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(_groupProvider(widget.id));
    final theme = Theme.of(context);
    return switch (group) {
      AsyncData(value: final g) => ListView(
        key: const Key('group.view'),
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
        children: [
          ListTile(
            key: const Key('group.back'),
            leading: const Icon(Icons.arrow_back),
            title: const Text('Retour à la liste'),
            onTap: widget.onBack,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, key: const Key('group.title'), style: theme.textTheme.titleLarge),
                const SizedBox(height: PrivioSpacing.s),
                Text(g.announcement ? 'Groupe «\u202FAnnonces\u202F»' : 'Groupe'),
                Text(
                  '${g.members} membres, dont ${g.admins} administrateur${g.admins > 1 ? 's' : ''}',
                ),
                if (g.ownerHandle != null) Text('Propriétaire\u202F: @${g.ownerHandle}'),
                if (g.createdAt != null) Text('Créé le ${_day(g.createdAt!)}'),
                if (g.lastActivity != null) Text('Dernier message le ${_day(g.lastActivity!)}'),
                Text(
                  '${g.reportsOpen} signalement${g.reportsOpen > 1 ? 's' : ''} en attente · '
                  '${g.reports90d} en 90 jours',
                  key: const Key('group.reports'),
                ),
                if (g.closed)
                  Padding(
                    padding: const EdgeInsets.only(top: PrivioSpacing.s),
                    child: Text(
                      'Groupe fermé\u202F: plus personne n’y écrit.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: PrivioSpacing.m),
                Text(
                  'Les messages du groupe ne sont jamais visibles ici\u202F; seuls les messages '
                  'signalés le sont, dans «\u202FSignalements\u202F».',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Wrap(
              spacing: PrivioSpacing.s,
              runSpacing: PrivioSpacing.s,
              children: [
                if (g.closed)
                  OutlinedButton.icon(
                    key: const Key('group.reopen'),
                    onPressed: _busy ? null : () => _act(g, 'reopen'),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Rouvrir'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('group.close'),
                    onPressed: _busy ? null : () => _act(g, 'close'),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Fermer le groupe'),
                  ),
                FilledButton.icon(
                  key: const Key('group.delete'),
                  style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                  onPressed: _busy ? null : () => _act(g, 'delete'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer…'),
                ),
              ],
            ),
          ),
          // Lot 5.9 : exceptions (propriétaire).
          if (ref.watch(consoleMeProvider).value?.role.isOwner ?? false)
            OverridesCard(scope: 'group', id: g.id),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: widget.onBack,
      ),
      _ => const LoadingView(),
    };
  }
}

class _GroupActionDialog extends StatefulWidget {
  const _GroupActionDialog({required this.group, required this.action});

  final ConsoleGroup group;
  final String action;

  @override
  State<_GroupActionDialog> createState() => _GroupActionDialogState();
}

class _GroupActionDialogState extends State<_GroupActionDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (title, effect) = switch (widget.action) {
      'close' => (
        'Fermer le groupe',
        'Plus personne n’y écrit\u202F; les invitations en attente sont annulées. Les membres '
            'voient «\u202FCe groupe a été fermé par Privio\u202F». Ses signalements en attente sont traités.',
      ),
      'reopen' => ('Rouvrir le groupe', 'Les membres peuvent de nouveau écrire.'),
      _ => (
        'Supprimer le groupe',
        'Le groupe et ses messages disparaissent pour tous les membres, tout de suite. '
            'C’est définitif.',
      ),
    };
    return AlertDialog(
      key: Key('group.action.${widget.action}'),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: PrivioSpacing.s),
            Text(effect, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.m),
            TemplatePicker(
              kind: 'decision',
              onPick: (t) => setState(() {
                _note.text = t;
                _note.selection = TextSelection.collapsed(offset: t.length);
              }),
            ),
            TextField(
              key: const Key('group.action.note'),
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Motif (interne, jamais montré)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('group.action.confirm'),
          onPressed: _note.text.trim().length < 3
              ? null
              : () => Navigator.pop(context, _note.text.trim()),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

String _day(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
