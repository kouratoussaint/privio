import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';

/// Lot 5.10 — présentation commune de la console (revue du 19/11/2026) : chaque rubrique
/// garde sa couleur (menu, tuiles) et l'applique à ses commandes ; une seule façon de
/// présenter un texte d'introduction, un titre de section, une rangée de filtres et une
/// liste vide. Les cartes et notes sont celles des Paramètres (SettingsCard, SettingsNote).

/// Couleur d'une rubrique adaptée au thème (éclaircie en thème sombre, pour rester lisible
/// sur fond foncé).
Color consoleAccent(BuildContext context, Color color) =>
    Theme.of(context).brightness == Brightness.dark ? Color.lerp(color, Colors.white, 0.4)! : color;

/// Thème d'une rubrique : boutons, puces, barres, champs et icônes à sa couleur.
ThemeData consoleSectionTheme(ThemeData base, Color color) {
  final dark = base.brightness == Brightness.dark;
  final accent = dark ? Color.lerp(color, Colors.white, 0.4)! : color;
  final onAccent = dark ? const Color(0xFF121735) : Colors.white;
  final container = Color.alphaBlend(
    accent.withValues(alpha: dark ? 0.24 : 0.14),
    base.colorScheme.surface,
  );
  final onContainer = dark ? Colors.white : Color.lerp(color, Colors.black, 0.35)!;
  final scheme = base.colorScheme.copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: container,
    onPrimaryContainer: onContainer,
    secondaryContainer: container,
    onSecondaryContainer: onContainer,
  );
  final palette = base.extension<PrivioPalette>();
  return base.copyWith(
    colorScheme: scheme,
    extensions: [if (palette != null) palette.withAccent(accent)],
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? base.colorScheme.onSurface.withValues(alpha: 0.12)
              : accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? base.colorScheme.onSurface.withValues(alpha: 0.38)
              : onAccent,
        ),
      ),
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(color: accent),
    switchTheme: base.switchTheme.copyWith(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : null,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
  );
}

/// Texte d'introduction en haut d'une rubrique.
class ConsoleIntro extends StatelessWidget {
  const ConsoleIntro(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.xs, 0, PrivioSpacing.xs, PrivioSpacing.s),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Titre de section d'une rubrique (même style que les Paramètres), avec une action
/// facultative à droite (ajouter…).
class ConsoleHeading extends StatelessWidget {
  const ConsoleHeading(this.text, {super.key, this.first = false, this.trailing, this.icon});

  final String text;

  /// Premier titre de la rubrique : moins d'espace au-dessus.
  final bool first;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        PrivioSpacing.xs,
        first ? PrivioSpacing.xs : PrivioSpacing.xl,
        0,
        trailing == null ? PrivioSpacing.s : 0,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: PrivioSpacing.s),
            ],
            Expanded(child: Text(text.toUpperCase(), style: style)),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Puce de filtre de la console, à la couleur de la rubrique quand elle est choisie.
Widget consoleChip(
  BuildContext context, {
  required Key key,
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    selectedColor: scheme.primary,
    side: selected ? BorderSide(color: scheme.primary) : null,
    labelStyle: selected ? TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600) : null,
    onSelected: (_) => onTap(),
  );
}

/// Rangée de filtres : une ligne qui défile, alignée sur le contenu de la rubrique.
class ConsoleFilterRow extends StatelessWidget {
  const ConsoleFilterRow({super.key, required this.children, this.leading});

  final List<Widget> children;

  /// Icône devant la rangée (période…).
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m),
      child: Row(
        children: [
          if (leading != null) ...[
            Icon(leading, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: PrivioSpacing.s),
          ],
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: PrivioSpacing.s),
            c,
          ],
        ],
      ),
    );
  }
}

/// Liste vide dans une section (ligne discrète dans une carte).
class ConsoleEmptyLine extends StatelessWidget {
  const ConsoleEmptyLine(this.text, {super.key, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(icon, color: muted),
      title: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
    );
  }
}
