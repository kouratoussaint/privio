import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';

/// Structure de marque (lot 2.D) : en-tête violet profond, contenu sur une feuille
/// claire aux coins supérieurs arrondis.
class BrandScaffold extends StatelessWidget {
  const BrandScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Scaffold(
      backgroundColor: p.header,
      appBar: AppBar(title: title, actions: actions, toolbarHeight: 64),
      floatingActionButton: floatingActionButton,
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(PrivioRadius.large + 4)),
        // Material (et non ColoredBox) : l’effet du toucher reste visible sur les listes.
        child: Material(
          color: p.sheet,
          child: SizedBox.expand(child: body),
        ),
      ),
    );
  }
}

/// Titre de l'écran Discussions : symbole du logo n° 1 + nom.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/privio_symbole.png',
          width: 34,
          height: 34,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: PrivioSpacing.s),
        Text(
          'Privio',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: p.onHeader, letterSpacing: -0.3),
        ),
      ],
    );
  }
}
