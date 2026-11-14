import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../../core/theme/privio_palette.dart';

/// Paramètres → Personnes bloquées.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: const Text('Personnes bloquées')),
      body: switch (blocked) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.block,
          title: 'Personne n’est bloqué',
          message: 'Vous pouvez bloquer quelqu’un depuis sa fiche contact.',
        ),
        AsyncData(:final value) => ListView(
          children: [
            for (final u in value)
              ListTile(
                leading: InitialAvatar(name: u.displayName),
                title: Text(u.displayName),
                subtitle: Text('@${u.handle}'),
                trailing: TextButton(
                  key: Key('blocked.unblock.${u.id}'),
                  onPressed: () async {
                    try {
                      await setBlocked(ref, u.id, blocked: false);
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                      }
                    }
                  },
                  child: const Text('Débloquer'),
                ),
              ),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(blockedUsersProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}
