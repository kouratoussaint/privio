import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console_team.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/state_views.dart';
import 'console_reports_tab.dart' show consoleChip;

// Lot 5.9 — pilotage (propriétaire) : inscriptions, préréglages, message programmé,
// exceptions par compte et par groupe.

Future<void> _guarded(BuildContext context, Future<void> Function() f, {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await f();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

String _dmyHm(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)} h ${two(l.minute)}';
}

String _dmy(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

const _padding = EdgeInsets.fromLTRB(
  PrivioSpacing.m,
  PrivioSpacing.m,
  PrivioSpacing.m,
  PrivioSpacing.xxl,
);

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: PrivioSpacing.l, bottom: PrivioSpacing.s),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

// ---------------------------------------------------------------------------
// A. Inscriptions
// ---------------------------------------------------------------------------
class ConsoleSignupsTab extends ConsumerStatefulWidget {
  const ConsoleSignupsTab({super.key});

  @override
  ConsumerState<ConsoleSignupsTab> createState() => _ConsoleSignupsTabState();
}

class _ConsoleSignupsTabState extends ConsumerState<ConsoleSignupsTab> {
  final _phones = TextEditingController();

  @override
  void dispose() {
    _phones.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(signupsProvider);

  Future<void> _addPhones(bool add) async {
    final api = ref.read(adminApiProvider);
    await _guarded(context, () async {
      final (n, bad) = await api.signupPhones(_phones.text, add: add);
      if (!mounted) return;
      _phones.clear();
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${add ? 'Ajoutés' : 'Retirés'}\u202F: $n numéro${n > 1 ? 's' : ''}'
            '${bad.isEmpty ? '' : '. Refusés\u202F: ${bad.join(', ')}'}',
          ),
        ),
      );
    });
  }

  Future<void> _newCode() async {
    final r = await showDialog<(String, int, int)>(
      context: context,
      builder: (_) => const _CodeDialog(),
    );
    if (r == null || !mounted) return;
    final api = ref.read(adminApiProvider);
    await _guarded(context, () async {
      final code = await api.createSignupCode(
        label: r.$1.isEmpty ? null : r.$1,
        maxUses: r.$2,
        days: r.$3,
      );
      _refresh();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          key: const Key('signups.code.created'),
          title: const Text('Code d’invitation'),
          content: SelectableText(
            code,
            style: Theme.of(c).textTheme.headlineMedium?.copyWith(letterSpacing: 4),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              child: const Text('Copier'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signupsProvider);
    final theme = Theme.of(context);
    return switch (state) {
      AsyncData(value: final s) => ListView(
        key: const Key('signups.view'),
        padding: _padding,
        children: [
          Wrap(
            spacing: PrivioSpacing.s,
            children: [
              for (final m in kSignupModes.entries)
                consoleChip(
                  context,
                  key: Key('signups.mode.${m.key}'),
                  label: m.value,
                  selected: s.mode == m.key,
                  onTap: () => _guarded(context, () async {
                    await ref.read(adminApiProvider).setSignups(m.key);
                    _refresh();
                  }, done: 'Inscriptions\u202F: ${m.value.toLowerCase()}.'),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            switch (s.mode) {
              'list' =>
                'Seuls les numéros de la liste et les personnes qui ont un code d’invitation '
                    'peuvent créer un compte.',
              'closed' => 'Personne ne peut créer de compte.',
              _ => 'Tout le monde peut créer un compte.',
            },
            key: const Key('signups.explain'),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            'Les comptes déjà créés ne sont jamais touchés.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          _Title('Numéros autorisés (${s.phones.length})'),
          TextField(
            key: const Key('signups.phones'),
            controller: _phones,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Un numéro par ligne\u202F: 70 00 00 00 ou +226…',
            ),
          ),
          const SizedBox(height: PrivioSpacing.s),
          Wrap(
            spacing: PrivioSpacing.s,
            children: [
              FilledButton(
                key: const Key('signups.phones.add'),
                onPressed: _phones.text.trim().isEmpty ? null : () => _addPhones(true),
                child: const Text('Ajouter'),
              ),
              OutlinedButton(
                key: const Key('signups.phones.remove'),
                onPressed: _phones.text.trim().isEmpty ? null : () => _addPhones(false),
                child: const Text('Retirer'),
              ),
            ],
          ),
          if (s.phones.isNotEmpty)
            ExpansionTile(
              key: const Key('signups.phones.list'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Voir la liste'),
              children: [
                for (final p in s.phones.take(200))
                  Align(alignment: Alignment.centerLeft, child: SelectableText(p)),
              ],
            ),
          const _Title('Codes d’invitation'),
          for (final c in s.codes)
            Card(
              key: Key('signups.code.${c.code}'),
              margin: const EdgeInsets.only(bottom: PrivioSpacing.s),
              child: ListTile(
                title: Text(
                  c.code,
                  style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${c.label == null ? '' : '${c.label} · '}${c.uses}/${c.maxUses} utilisé'
                  '${c.uses > 1 ? 's' : ''}'
                  '${c.expiresAt == null ? '' : ' · jusqu’au ${_dmy(c.expiresAt!)}'}'
                  '${c.active ? '' : ' · épuisé ou expiré'}',
                ),
                trailing: IconButton(
                  key: Key('signups.code.revoke.${c.code}'),
                  tooltip: 'Annuler ce code',
                  icon: const Icon(Icons.block),
                  onPressed: () => _guarded(context, () async {
                    await ref.read(adminApiProvider).revokeSignupCode(c.code);
                    _refresh();
                  }, done: 'Code annulé.'),
                ),
              ),
            ),
          OutlinedButton.icon(
            key: const Key('signups.code.new'),
            onPressed: _newCode,
            icon: const Icon(Icons.add),
            label: const Text('Créer un code'),
          ),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: _refresh,
      ),
      _ => const LoadingView(),
    };
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _label = TextEditingController();
  int _uses = 10;
  int _days = 14;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('signups.code.dialog'),
    title: const Text('Nouveau code d’invitation'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('signups.code.label'),
            controller: _label,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Pour qui\u202F? (facultatif)'),
          ),
          const Text('Utilisations'),
          Wrap(
            spacing: PrivioSpacing.s,
            children: [
              for (final n in [1, 10, 50, 200])
                consoleChip(
                  context,
                  key: Key('signups.code.uses.$n'),
                  label: '$n',
                  selected: _uses == n,
                  onTap: () => setState(() => _uses = n),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.s),
          const Text('Valable'),
          Wrap(
            spacing: PrivioSpacing.s,
            children: [
              for (final d in [1, 7, 14, 30, 90])
                consoleChip(
                  context,
                  key: Key('signups.code.days.$d'),
                  label: '$d j',
                  selected: _days == d,
                  onTap: () => setState(() => _days = d),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(
        key: const Key('signups.code.create'),
        onPressed: () => Navigator.pop(context, (_label.text.trim(), _uses, _days)),
        child: const Text('Créer'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// C, D, B. Préréglages, message programmé, exceptions en cours
// ---------------------------------------------------------------------------
class ConsolePilotTab extends ConsumerWidget {
  const ConsolePilotTab({super.key});

  Future<void> _preset(BuildContext context, WidgetRef ref, String name) async {
    final api = ref.read(adminApiProvider);
    List<PresetChange> changes;
    try {
      changes = await api.preset(name);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: Key('preset.dialog.$name'),
        title: Text(kPresets[name]!),
        content: changes.isEmpty
            ? const Text('Les réglages sont déjà ceux de ce mode.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ces réglages vont changer\u202F:'),
                    const SizedBox(height: PrivioSpacing.s),
                    for (final ch in changes)
                      Padding(
                        key: Key('preset.change.${ch.key}'),
                        padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
                        child: Text(
                          '• ${ch.label}\u202F: ${_presetValue(ch.before)} → ${_presetValue(ch.after)}',
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          if (changes.isNotEmpty)
            FilledButton(
              key: const Key('preset.apply'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Appliquer'),
            ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guarded(context, () async {
      await api.preset(name, apply: true);
      ref
        ..invalidate(signupsProvider)
        ..invalidate(consolePoliciesProvider);
    }, done: '${kPresets[name]} appliqué.');
  }

  static String _presetValue(Object? v) => switch (v) {
    'open' => 'ouvertes',
    'list' => 'sur liste',
    _ => overrideValueText(v),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheduled = ref.watch(scheduledAnnouncementProvider);
    final overrides = ref.watch(overridesProvider((null, null)));
    return ListView(
      key: const Key('pilot.view'),
      padding: _padding,
      children: [
        Text('Préréglages', style: theme.textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.s),
        Text(
          'Mode pilote\u202F: inscriptions sur liste, groupes de 25, Annonces de 200, liens '
          'd’invitation coupés. Mode normal\u202F: inscriptions ouvertes, groupes de 50, Annonces '
          'de 500, liens d’invitation. Les changements sont montrés avant d’appliquer.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.s),
        Wrap(
          spacing: PrivioSpacing.s,
          children: [
            for (final p in kPresets.entries)
              OutlinedButton(
                key: Key('preset.${p.key}'),
                onPressed: () => _preset(context, ref, p.key),
                child: Text(p.value),
              ),
          ],
        ),
        const _Title('Message d’information programmé'),
        switch (scheduled) {
          AsyncData(value: final a?) => Card(
            key: const Key('scheduled.current'),
            child: ListTile(
              title: Text(a.text),
              subtitle: Text(
                '${a.live ? 'Affiché maintenant · ' : ''}Du ${_dmyHm(a.startsAt)} '
                'au ${_dmyHm(a.endsAt)}',
              ),
              trailing: IconButton(
                key: const Key('scheduled.remove'),
                tooltip: 'Retirer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _guarded(context, () async {
                  await ref.read(adminApiProvider).setScheduledAnnouncement('');
                  ref.invalidate(scheduledAnnouncementProvider);
                }, done: 'Message programmé retiré.'),
              ),
            ),
          ),
          AsyncData() => Text(
            'Aucun. Pendant sa période, il remplace le message d’information immédiat.',
            style: theme.textTheme.bodySmall,
          ),
          _ => const SizedBox.shrink(),
        },
        const SizedBox(height: PrivioSpacing.s),
        OutlinedButton.icon(
          key: const Key('scheduled.new'),
          onPressed: () async {
            final r = await showDialog<(String, DateTime, DateTime)>(
              context: context,
              builder: (_) => const _ScheduleDialog(),
            );
            if (r == null || !context.mounted) return;
            await _guarded(context, () async {
              await ref
                  .read(adminApiProvider)
                  .setScheduledAnnouncement(r.$1, startsAt: r.$2, endsAt: r.$3);
              ref.invalidate(scheduledAnnouncementProvider);
            }, done: 'Message programmé.');
          },
          icon: const Icon(Icons.schedule),
          label: const Text('Programmer un message'),
        ),
        const _Title('Exceptions en cours'),
        Text(
          'Posées depuis la fiche d’un compte (Comptes) ou d’un groupe (Groupes).',
          style: theme.textTheme.bodySmall,
        ),
        switch (overrides) {
          AsyncData(:final value) when value.isEmpty => const Padding(
            padding: EdgeInsets.all(PrivioSpacing.m),
            child: Text('Aucune exception.'),
          ),
          AsyncData(:final value) => Column(
            children: [for (final o in value) _OverrideTile(o: o, showTarget: true)],
          ),
          AsyncError(:final error) => Text(toAppFailure(error).message),
          _ => const LoadingView(),
        },
      ],
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _text = TextEditingController();
  late DateTime _start = DateTime.now().add(const Duration(hours: 1));
  late DateTime _end = _start.add(const Duration(hours: 2));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final ok =
        _text.text.trim().isNotEmpty &&
        _end.isAfter(_start) &&
        _end.isAfter(DateTime.now()) &&
        _end.difference(_start).inDays <= 30;
    return AlertDialog(
      key: const Key('scheduled.dialog'),
      title: const Text('Message programmé'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('scheduled.text'),
              controller: _text,
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Texte affiché à tous'),
            ),
            ListTile(
              key: const Key('scheduled.start'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Début'),
              subtitle: Text(_dmyHm(_start)),
              onTap: () async {
                final d = await _pick(_start);
                if (d != null) setState(() => _start = d);
              },
            ),
            ListTile(
              key: const Key('scheduled.end'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Fin'),
              subtitle: Text(_dmyHm(_end)),
              onTap: () async {
                final d = await _pick(_end);
                if (d != null) setState(() => _end = d);
              },
            ),
            const Text('Heure de ce téléphone\u202F; 30 jours au plus.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('scheduled.save'),
          onPressed: ok ? () => Navigator.pop(context, (_text.text.trim(), _start, _end)) : null,
          child: const Text('Programmer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// B. Exceptions d'un compte ou d'un groupe (fiches)
// ---------------------------------------------------------------------------
class _OverrideTile extends ConsumerWidget {
  const _OverrideTile({required this.o, this.showTarget = false});

  final PolicyOverride o;
  final bool showTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: Key('override.${o.scope}.${o.key}'),
    contentPadding: EdgeInsets.zero,
    leading: Icon(o.scope == 'user' ? Icons.person_outline : Icons.groups_outlined),
    title: Text(
      '${showTarget && o.target != null ? '${o.target} · ' : ''}${o.label}\u202F: '
      '${overrideValueText(o.value)}',
    ),
    subtitle: Text(
      [
        'Réglage général\u202F: ${overrideValueText(o.globalValue)}',
        o.expiresAt == null ? 'sans date de fin' : 'jusqu’au ${_dmy(o.expiresAt!)}',
        if (o.note != null) o.note!,
      ].join(' · '),
    ),
    trailing: IconButton(
      key: Key('override.remove.${o.scope}.${o.key}'),
      tooltip: 'Retirer l’exception',
      icon: const Icon(Icons.close),
      onPressed: () => _guarded(context, () async {
        await ref.read(adminApiProvider).setOverride(scope: o.scope, id: o.id, key: o.key);
        ref.invalidate(overridesProvider);
      }, done: 'Exception retirée.'),
    ),
  );
}

/// Fiche d'un compte ([scope] 'user') ou d'un groupe ('group') : exceptions en cours et
/// ajout. Propriétaire seulement.
class OverridesCard extends ConsumerWidget {
  const OverridesCard({super.key, required this.scope, required this.id});

  final String scope;
  final String id;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final r = await showDialog<(String, Object, int?, String)>(
      context: context,
      builder: (_) => _OverrideDialog(scope: scope),
    );
    if (r == null || !context.mounted) return;
    await _guarded(context, () async {
      await ref
          .read(adminApiProvider)
          .setOverride(scope: scope, id: id, key: r.$1, value: r.$2, days: r.$3, note: r.$4);
      ref.invalidate(overridesProvider);
    }, done: 'Exception enregistrée.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(overridesProvider(scope == 'user' ? (id, null) : (null, id)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
      child: Column(
        key: Key('overrides.$scope'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Exceptions'),
          for (final o in list.value ?? const <PolicyOverride>[]) _OverrideTile(o: o),
          TextButton.icon(
            key: Key('overrides.add.$scope'),
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.tune),
            label: const Text('Ajouter une exception'),
          ),
        ],
      ),
    );
  }
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.scope});

  final String scope;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late final Map<String, (String, bool)> _keys = widget.scope == 'user'
      ? kUserOverrideKeys
      : kGroupOverrideKeys;
  late String _key = _keys.keys.first;
  bool _on = false;
  final _number = TextEditingController();
  final _note = TextEditingController();
  int? _days = 30;

  @override
  void dispose() {
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _bool => _keys[_key]!.$2;

  Object? get _value {
    if (_bool) return _on;
    final n = int.tryParse(_number.text.trim());
    if (n == null) return null;
    final max = _key == 'group_max_members' ? 500 : 10;
    final min = _key == 'group_max_members' ? 2 : 0;
    return n < min || n > max ? null : n;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('override.dialog'),
    title: Text(widget.scope == 'user' ? 'Exception pour ce compte' : 'Exception pour ce groupe'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: PrivioSpacing.s,
            runSpacing: PrivioSpacing.xs,
            children: [
              for (final k in _keys.entries)
                consoleChip(
                  context,
                  key: Key('override.key.${k.key}'),
                  label: k.value.$1,
                  selected: _key == k.key,
                  onTap: () => setState(() => _key = k.key),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.s),
          if (_bool)
            SwitchListTile(
              key: const Key('override.on'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Autorisé'),
              value: _on,
              onChanged: (v) => setState(() => _on = v),
            )
          else
            TextField(
              key: const Key('override.number'),
              controller: _number,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _key == 'group_max_members' ? 'Membres (2 à 500)' : 'Photos (0 à 10)',
              ),
            ),
          const SizedBox(height: PrivioSpacing.s),
          const Text('Durée'),
          Wrap(
            spacing: PrivioSpacing.s,
            children: [
              for (final (d, label) in const [
                (7, '7 j'),
                (30, '30 j'),
                (90, '90 j'),
                (null, 'Sans fin'),
              ])
                consoleChip(
                  context,
                  key: Key('override.days.${d ?? 'none'}'),
                  label: label,
                  selected: _days == d,
                  onTap: () => setState(() => _days = d),
                ),
            ],
          ),
          TextField(
            key: const Key('override.note'),
            controller: _note,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Motif (interne, facultatif)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(
        key: const Key('override.save'),
        onPressed: _value == null
            ? null
            : () => Navigator.pop(context, (_key, _value!, _days, _note.text.trim())),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
