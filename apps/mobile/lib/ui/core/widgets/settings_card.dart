import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';

/// Lot 7.2a : présentation commune des écrans de réglages et des fiches (comme
/// Paramètres) : fond clair, une carte blanche arrondie par section.

/// Liste d'un écran de réglages : fond clair, marges latérales pour les cartes.
class SettingsListView extends StatelessWidget {
  const SettingsListView({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: children,
    ),
  );
}

/// Titre de section, au-dessus d'une carte.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key, this.first = false});

  final String text;

  /// Premier titre de l'écran : moins d'espace au-dessus.
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      PrivioSpacing.xs,
      first ? PrivioSpacing.xs : PrivioSpacing.xl,
      PrivioSpacing.xs,
      PrivioSpacing.s,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
    ),
  );
}

/// Carte blanche d'une section ; les lignes gardent l'effet du toucher.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? p.field : p.sheet,
        borderRadius: BorderRadius.circular(PrivioRadius.large),
        border: Border.all(color: p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// Séparateur entre deux lignes d'une carte (aligné sur le texte, après l'icône).
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(indent: 56, height: 1);
}

/// Note discrète sous une carte.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.xs, PrivioSpacing.s, PrivioSpacing.xs, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
