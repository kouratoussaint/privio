import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/routes.dart';
import '../../../state/push_providers.dart';

/// Navigation MVP validée : Discussions / Groupes / Paramètres, et rien d'autre.
/// Active aussi les notifications (lot 4.1) et ouvre la discussion d'une notification touchée.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: 'Discussions',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: 'Groupes',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Paramètres',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pushProvider);
    ref.listen(openConversationRequestProvider, (_, id) {
      if (id == null) return;
      ref.read(openConversationRequestProvider.notifier).consume();
      context.push(Routes.chat(id));
    });
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: destinations,
      ),
    );
  }
}
