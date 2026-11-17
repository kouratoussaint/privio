import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';

/// Onglet « Réglages » de la console (lot 5.2) : tous les réglages globaux, par thème.
/// Les invariants et les fonctions non développées sont affichés avec un cadenas.
class ConsolePoliciesTab extends ConsumerWidget {
  const ConsolePoliciesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(consolePoliciesProvider);
    return switch (policies) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consolePoliciesProvider.future),
        child: _PolicyList(policies: value),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consolePoliciesProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

/// Lot 5.5 : icône et couleur de chaque thème.
(IconData, Color) policyCategoryStyle(String c) => switch (c) {
  'messages' => (Icons.chat_bubble_outline_rounded, const Color(0xFF6A3FD0)),
  'media' => (Icons.perm_media_outlined, const Color(0xFF138A6E)),
  'groups' => (Icons.groups_2_outlined, const Color(0xFF2A73C9)),
  'requests' => (Icons.person_add_alt_1_outlined, const Color(0xFFB7700F)),
  'abuse' => (Icons.shield_outlined, const Color(0xFFD85A30)),
  'retention' => (Icons.inventory_2_outlined, const Color(0xFF5A6B85)),
  'advanced' => (Icons.memory_rounded, const Color(0xFF6B6A66)),
  _ => (Icons.tune_rounded, const Color(0xFF3E8B1A)),
};

/// Lot 5.5 : réglages sur fond blanc, en tuiles par thème, avec icônes. Les
/// fonctionnalités, engagements et fonctions à venir sont dans « Fonctionnalités ».
class _PolicyList extends StatelessWidget {
  const _PolicyList({required this.policies});

  final List<ConsolePolicy> policies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<ConsolePolicy> of(String c) =>
        policies.where((p) => p.category == c).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    const elsewhere = {'features', 'locked', 'future'};
    return ListView(
      key: const Key('console.policies'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        Text(
          'Réglages appliqués à tous les comptes. Chaque changement est vérifié par le serveur '
          'et inscrit au journal.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        for (final entry in kPolicyCategories.entries)
          if (!elsewhere.contains(entry.key) && of(entry.key).isNotEmpty)
            Column(
              key: Key('console.category.${entry.key}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, PrivioSpacing.l, 4, PrivioSpacing.s),
                  child: Row(
                    children: [
                      Icon(
                        policyCategoryStyle(entry.key).$1,
                        size: 18,
                        color: policyCategoryStyle(entry.key).$2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.value,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: policyCategoryStyle(entry.key).$2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsCard(
                  children: [
                    for (final (i, p) in of(entry.key).indexed) ...[
                      if (i > 0) const SettingsDivider(),
                      _PolicyTile(policy: p),
                    ],
                  ],
                ),
              ],
            ),
      ],
    );
  }
}

String _date(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} à ${two(l.hour)}:${two(l.minute)}';
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({required this.policy});

  final ConsolePolicy policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final changed = !policy.isDefault;
    final subtitle = policy.locked
        ? (policy.category == 'future' ? 'Pas encore développé' : 'Fixé')
        : [
            policy.format(policy.value),
            if (changed) 'par défaut : ${policy.format(policy.defaultValue)}',
            if (changed && policy.updatedAt != null) 'modifié le ${_date(policy.updatedAt!)}',
          ].join(' · ');
    final (icon, color) = policyCategoryStyle(policy.category);
    return ListTile(
      key: Key('policy.${policy.key}'),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(policy.label),
      subtitle: Text(
        subtitle,
        style: changed && !policy.locked
            ? theme.textTheme.bodyMedium?.copyWith(color: p.accentText)
            : null,
      ),
      trailing: Icon(
        policy.locked ? Icons.lock_outline : Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: policy.locked
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => PolicyEditorSheet(policy: policy),
            ),
    );
  }
}

/// Modification d'un réglage : valeur, limites, effet, confirmation « avant → après »,
/// valeur par défaut et historique (« Rétablir »).
class PolicyEditorSheet extends ConsumerStatefulWidget {
  const PolicyEditorSheet({super.key, required this.policy, this.initialValue});

  final ConsolePolicy policy;

  /// Lot 5.7 : valeur proposée à l'ouverture (version choisie dans la liste, interrupteur
  /// basculé) ; toujours confirmée « avant → après ».
  final Object? initialValue;

  @override
  ConsumerState<PolicyEditorSheet> createState() => _PolicyEditorSheetState();
}

class _PolicyEditorSheetState extends ConsumerState<PolicyEditorSheet> {
  late Object? _value = widget.initialValue ?? widget.policy.value;
  bool _saving = false;

  ConsolePolicy get _p => widget.policy;

  int get _int => (_value as num?)?.toInt() ?? (_p.min ?? 0);

  void _setInt(int v) {
    final lo = _p.min ?? v;
    final hi = _p.max ?? v;
    setState(() => _value = v.clamp(lo, hi));
  }

  /// Pas du curseur : au plus ~200 positions.
  int get _sliderStep {
    final range = (_p.max ?? 0) - (_p.min ?? 0);
    var s = _p.step;
    while (range / s > 200) {
      s *= s == 1 ? 5 : 2;
    }
    return s;
  }

  Future<void> _save([Object? value]) async {
    final next = value ?? _value;
    if (next == null || next == _p.value) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('policy.confirm'),
        title: Text(_p.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_p.format(_p.value)}  →  ${_p.format(next)}',
              key: const Key('policy.confirm.change'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.m),
            Text(_p.effectText),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('policy.confirm.ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await savePolicy(ref, _p, next);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          key: const Key('policy.saved'),
          content: Text('Réglage enregistré : ${_p.label} = ${_p.format(next)}'),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(policyHistoryProvider(_p.key)).value ?? const <PolicyChange>[];
    final changed = _value != _p.value;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          PrivioSpacing.xl,
          0,
          PrivioSpacing.xl,
          PrivioSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: Key('policy.editor.${_p.key}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_p.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: PrivioSpacing.s),
            Text(
              _p.isInt
                  ? 'Entre ${_p.format(_p.min)} et ${_p.format(_p.max)} · par défaut '
                        '${_p.format(_p.defaultValue)}'
                  : 'Par défaut : ${_p.format(_p.defaultValue)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: PrivioSpacing.l),
            if (_p.isBool)
              SwitchListTile(
                key: const Key('policy.switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(_value == true ? 'Activé' : 'Désactivé'),
                value: _value == true,
                onChanged: _saving ? null : (v) => setState(() => _value = v),
              )
            else if (_p.isInt) ...[
              Row(
                children: [
                  IconButton.filled(
                    key: const Key('policy.minus'),
                    tooltip: 'Diminuer',
                    onPressed: _saving || _int <= (_p.min ?? _int - 1)
                        ? null
                        : () => _setInt(_int - _p.step),
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Text(
                      _p.format(_value),
                      key: const Key('policy.value'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton.filled(
                    key: const Key('policy.plus'),
                    tooltip: 'Augmenter',
                    onPressed: _saving || _int >= (_p.max ?? _int + 1)
                        ? null
                        : () => _setInt(_int + _p.step),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_p.min != null && _p.max != null && _p.max! > _p.min!)
                Slider(
                  key: const Key('policy.slider'),
                  min: _p.min!.toDouble(),
                  max: _p.max!.toDouble(),
                  divisions: ((_p.max! - _p.min!) / _sliderStep).ceil().clamp(1, 1000),
                  value: _int.clamp(_p.min!, _p.max!).toDouble(),
                  label: _p.format(_value),
                  onChanged: _saving ? null : (v) => _setInt(v.round()),
                ),
            ],
            const SizedBox(height: PrivioSpacing.s),
            Text(_p.effectText, style: theme.textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.l),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('policy.default'),
                    onPressed: _saving || _value == _p.defaultValue
                        ? null
                        : () => setState(() => _value = _p.defaultValue),
                    child: const Text('Valeur par défaut', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: PrivioSpacing.m),
                Expanded(
                  child: FilledButton(
                    key: const Key('policy.save'),
                    onPressed: _saving || !changed ? null : _save,
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: PrivioSpacing.xl),
              Text('Historique', style: theme.textTheme.titleSmall),
              for (final (i, h) in history.take(6).indexed)
                ListTile(
                  key: Key('policy.history.$i'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${h.before == null ? 'Défaut' : _p.format(h.before)} → ${_p.format(h.after)}',
                  ),
                  subtitle: Text(
                    'Le ${_date(h.at)}${h.byConsole ? ' · console' : ' · mise à jour du serveur'}',
                  ),
                  trailing: i == 0 || h.after == _p.value || h.after == null
                      ? null
                      : TextButton(
                          key: Key('policy.restore.$i'),
                          onPressed: _saving ? null : () => _save(h.after),
                          child: const Text('Rétablir'),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
