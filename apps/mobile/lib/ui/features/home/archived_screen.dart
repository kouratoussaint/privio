import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import 'discussions_tab.dart';
import '../../../core/theme/privio_palette.dart';

/// Discussions archivées (état personnel). Appui long : désarchiver.
class ArchivedScreen extends ConsumerWidget {
  const ArchivedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = (ref.watch(conversationsProvider).value ?? const [])
        .where((c) => c.archived)
        .toList();
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: const Text('Archivées')),
      body: archived.isEmpty
          ? const EmptyView(
              icon: Icons.archive_outlined,
              title: 'Aucune discussion archivée',
              message: 'Glissez une discussion vers la gauche pour l’archiver.',
            )
          : ListView(children: [for (final c in archived) SwipeableConversationTile(summary: c)]),
    );
  }
}
