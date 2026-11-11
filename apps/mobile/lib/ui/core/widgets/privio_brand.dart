import 'package:flutter/material.dart';

/// Symbole Privio (recréation vectorielle provisoire du logo n° 1, rendue en PNG).
class PrivioSymbol extends StatelessWidget {
  const PrivioSymbol({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/privio_symbole.png',
    width: size,
    height: size,
    semanticLabel: 'Logo Privio',
    filterQuality: FilterQuality.medium,
  );
}

/// Nom « Privio » dans la typographie du thème.
class PrivioWordmark extends StatelessWidget {
  const PrivioWordmark({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('Privio', style: Theme.of(context).textTheme.headlineMedium, semanticsLabel: 'Privio');
}
