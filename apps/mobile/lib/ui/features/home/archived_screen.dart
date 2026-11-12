import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import 'discussions_tab.dart';

/// Discussions archivées (état personnel). Appui long : désarchiver.
class ArchivedScreen extends ConsumerWidget {
  const ArchivedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = (ref.watch(conversationsProvider).value ?? const [])
        .where((c) => c.archived)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Archivées')),
      body: archived.isEmpty
          ? const EmptyView(
              icon: Icons.archive_outlined,
              title: 'Aucune discussion archivée',
              message: 'Appui long sur une discussion pour l’archiver.',
            )
          : ListView(children: [for (final c in archived) ConversationTile(summary: c)]),
    );
  }
}
