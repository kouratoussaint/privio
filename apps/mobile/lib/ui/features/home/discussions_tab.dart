import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

/// Écran 08 (état vide). Liste, recherche et nouvelle discussion : étape 2.
class DiscussionsTab extends StatelessWidget {
  const DiscussionsTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privio')),
    body: const EmptyView(
      icon: Icons.chat_bubble_outline,
      title: 'Aucune discussion pour l\'instant',
      message:
          'Vos discussions apparaîtront ici. Chaque message s\'efface '
          'automatiquement 72 heures après son envoi.',
    ),
  );
}
