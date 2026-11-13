import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';

/// Sélecteur de durée des messages (lot 4.6) : une feuille compacte avec les durées
/// proposées en puces et « Personnalisé » (heures et minutes, de 5 en 5).
///
/// Renvoie la durée choisie en secondes, ou null si la personne renonce. Les puces hors
/// de [min]..[max] ne sont pas proposées ; une durée personnalisée hors bornes ne peut
/// pas être validée.
Future<int?> showTtlPicker(
  BuildContext context, {
  required String title,
  required String help,
  required int current,
  required int min,
  required int max,
  String keyPrefix = 'ttl',
}) => showModalBottomSheet<int>(
  context: context,
  showDragHandle: true,
  // Défilante : reste utilisable sur un petit écran et avec une grande police.
  isScrollControlled: true,
  builder: (_) => TtlPickerSheet(
    title: title,
    help: help,
    current: current,
    min: min,
    max: max,
    keyPrefix: keyPrefix,
  ),
);

class TtlPickerSheet extends StatefulWidget {
  const TtlPickerSheet({
    super.key,
    required this.title,
    required this.help,
    required this.current,
    required this.min,
    required this.max,
    this.keyPrefix = 'ttl',
  });

  final String title;
  final String help;
  final int current;
  final int min;
  final int max;
  final String keyPrefix;

  /// Pas des minutes dans « Personnalisé ».
  static const minuteStep = 5;

  @override
  State<TtlPickerSheet> createState() => _TtlPickerSheetState();
}

class _TtlPickerSheetState extends State<TtlPickerSheet> {
  bool _custom = false;
  late int _hours;
  late int _minutes;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  List<int> get _presets => [
    for (final s in kTtlChoices)
      if (s >= widget.min && s <= widget.max) s,
  ];

  int get _maxHours => widget.max ~/ 3600;
  int get _total => _hours * 3600 + _minutes * 60;

  String? get _error {
    if (_total < widget.min) return 'Au moins ${formatTtl(widget.min)}.';
    if (_total > widget.max) return 'Au plus ${formatTtl(widget.max)}.';
    return null;
  }

  @override
  void initState() {
    super.initState();
    final start = widget.current.clamp(widget.min, widget.max);
    _hours = (start ~/ 3600).clamp(0, _maxHours);
    _minutes =
        ((start % 3600) / 60 / TtlPickerSheet.minuteStep).round() * TtlPickerSheet.minuteStep;
    if (_minutes >= 60) _minutes = 55;
    _hourCtrl = FixedExtentScrollController(initialItem: _hours);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minutes ~/ TtlPickerSheet.minuteStep);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  String _k(String suffix) => '${widget.keyPrefix}.$suffix';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(PrivioSpacing.xl, 0, PrivioSpacing.xl, PrivioSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _custom ? 'Durée personnalisée' : widget.title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.xs),
            Text(widget.help, style: theme.textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.m),
            if (_custom) _customBody(theme) else _presetsBody(theme),
          ],
        ),
      ),
    );
  }

  /// Puce aux couleurs de Privio (violet quand elle est choisie).
  ChoiceChip _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? avatar,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? PrivioColors.lilac : PrivioColors.purple;
    final onFill = dark ? PrivioColors.navy : Colors.white;
    return ChoiceChip(
      key: key,
      avatar: avatar == null
          ? null
          : IconTheme.merge(
              data: IconThemeData(color: selected ? onFill : null),
              child: avatar,
            ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: fill,
      labelStyle: selected ? TextStyle(color: onFill, fontWeight: FontWeight.w600) : null,
      onSelected: (_) => onTap(),
    );
  }

  Widget _presetsBody(ThemeData theme) {
    final presets = _presets;
    final isPreset = presets.contains(widget.current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: PrivioSpacing.s,
          runSpacing: PrivioSpacing.s,
          children: [
            for (final s in presets)
              _chip(
                key: Key('${widget.keyPrefix}.$s'),
                label: formatTtl(s),
                selected: s == widget.current,
                onTap: () => Navigator.pop(context, s),
              ),
            _chip(
              key: Key(_k('custom')),
              avatar: const Icon(Icons.tune, size: 18),
              label: isPreset ? 'Personnalisé' : 'Personnalisé · ${formatTtl(widget.current)}',
              selected: !isPreset,
              onTap: () => setState(() => _custom = true),
            ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.m),
        Text(
          'Actuellement : ${formatTtl(widget.current)}',
          key: Key(_k('current')),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _customBody(ThemeData theme) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(
                child: _Wheel(
                  key: Key(_k('custom.hours')),
                  controller: _hourCtrl,
                  count: _maxHours + 1,
                  label: (i) => '$i h',
                  semantics: 'Heures',
                  onChanged: (i) => setState(() => _hours = i),
                ),
              ),
              const SizedBox(width: PrivioSpacing.m),
              Expanded(
                child: _Wheel(
                  key: Key(_k('custom.minutes')),
                  controller: _minuteCtrl,
                  count: 60 ~/ TtlPickerSheet.minuteStep,
                  label: (i) => '${i * TtlPickerSheet.minuteStep} min',
                  semantics: 'Minutes',
                  onChanged: (i) => setState(() => _minutes = i * TtlPickerSheet.minuteStep),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PrivioSpacing.s),
        Text(
          error ?? 'Entre ${formatTtl(widget.min)} et ${formatTtl(widget.max)}.',
          key: Key(_k(error == null ? 'custom.range' : 'custom.error')),
          style: theme.textTheme.bodySmall?.copyWith(
            color: error == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: PrivioSpacing.m),
        // Boutons côte à côte, ou l'un sous l'autre si la place manque (grande police).
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: PrivioSpacing.s,
          overflowSpacing: PrivioSpacing.s,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            TextButton(
              key: Key(_k('custom.cancel')),
              onPressed: () => setState(() => _custom = false),
              child: const Text('Retour'),
            ),
            FilledButton(
              key: Key(_k('custom.ok')),
              onPressed: error == null ? () => Navigator.pop(context, _total) : null,
              child: Text('Valider ${error == null ? formatTtl(_total) : ''}'.trim()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Roulette (heures ou minutes) du choix personnalisé.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.count,
    required this.label,
    required this.semantics,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) label;
  final String semantics;
  final ValueChanged<int> onChanged;

  static const itemExtent = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Semantics(
      label: semantics,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: itemExtent,
              decoration: BoxDecoration(
                color: p.notice,
                borderRadius: BorderRadius.circular(PrivioRadius.medium),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: itemExtent,
            physics: const FixedExtentScrollPhysics(),
            diameterRatio: 1.6,
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (_, i) => Center(child: Text(label(i), style: theme.textTheme.titleMedium)),
            ),
          ),
        ],
      ),
    );
  }
}
