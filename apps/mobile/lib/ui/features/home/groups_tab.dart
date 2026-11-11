import 'package:flutter/material.dart';

import '../../core/widgets/state_views.dart';

/// Écran 17 (état vide). Création et gestion des groupes : étape 3.
class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Groupes')),
    body: const EmptyView(
      icon: Icons.groups_outlined,
      title: 'Aucun groupe pour l\'instant',
      message: 'Vos groupes apparaîtront ici.',
    ),
  );
}
