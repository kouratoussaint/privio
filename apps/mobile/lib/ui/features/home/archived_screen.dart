import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import 'discussions_tab.dart';
import '../../../core/theme/privio_palette.dart';

/// Discussions archivées (état personnel). Appui long : désarchiver.
class ArchivedScreen extends ConsumerWidget {
  const ArchivedScreen({super.key, this.kind});

  /// Lot 7.2c1 : « groupes » ou « discussions » (groupes séparés) ; null : tout.
  final String? kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = kind == 'groupes';
    final archived = (ref.watch(conversationsProvider).value ?? const [])
        .where((c) => c.archived && (kind == null || c.isGroup == groups))
        .toList();
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: Text(groups ? L.t.groupesArchives : L.t.archivees)),
      body: archived.isEmpty
          ? EmptyView(
              icon: Icons.archive_outlined,
              title: groups ? L.t.aucunGroupeArchive : L.t.aucuneDiscussionArchivee,
              message: groups
                  ? L.t.glissezGroupeVersGauchePour
                  : L.t.glissezDiscussionVersGauchePour,
            )
          : ListView(children: [for (final c in archived) SwipeableConversationTile(summary: c)]),
    );
  }
}
