import 'package:flutter/material.dart';

import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/state_views.dart';

/// Écran 17 (état vide). Création et gestion des groupes : lot 3.3.
class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context) => const BrandScaffold(
    title: Text('Groupes'),
    body: EmptyView(
      icon: Icons.groups_outlined,
      title: 'Aucun groupe pour l\'instant',
      message: 'Vos groupes apparaîtront ici.',
    ),
  );
}
