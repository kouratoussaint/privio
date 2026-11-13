import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/push_providers.dart';

/// Navigation MVP validée : Discussions / Groupes / Paramètres, et rien d'autre.
/// Active aussi les notifications (lot 4.1) et ouvre la discussion d'une notification touchée.
///
/// Lot 4.5 : barre « piste C » (trait violet sur l'onglet actif, pastilles) et double
/// appui sur Retour pour quitter ; depuis Groupes ou Paramètres, Retour ramène à Discussions.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Délai entre les deux appuis sur Retour.
  static const exitWindow = Duration(seconds: 2);

  static const exitHint = 'Appuyez encore sur Retour pour quitter';

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Armé par un premier appui sur Retour, désarmé après [HomeShell.exitWindow].
  Timer? _exitArmed;

  @override
  void dispose() {
    _exitArmed?.cancel();
    super.dispose();
  }

  void _onBack() {
    final shell = widget.shell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    if (_exitArmed?.isActive ?? false) {
      _exitArmed!.cancel();
      unawaited(SystemNavigator.pop());
      return;
    }
    _exitArmed = Timer(HomeShell.exitWindow, () {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: Key('home.exit_hint'),
          content: Text(HomeShell.exitHint),
          duration: HomeShell.exitWindow,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pushProvider);
    ref.listen(openConversationRequestProvider, (_, id) {
      if (id == null) return;
      ref.read(openConversationRequestProvider.notifier).consume();
      context.push(Routes.chat(id));
    });
    final shell = widget.shell;
    final unread =
        ref
            .watch(conversationsProvider)
            .value
            ?.where((c) => !c.archived && c.unreadCount > 0)
            .length ??
        0;
    final invitations = ref.watch(invitationsProvider).value?.length ?? 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: PrivioNavBar(
          currentIndex: shell.currentIndex,
          onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          items: [
            PrivioNavItem(
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble,
              label: 'Discussions',
              badge: unread,
            ),
            PrivioNavItem(
              icon: Icons.groups_outlined,
              selectedIcon: Icons.groups,
              label: 'Groupes',
              badge: invitations,
            ),
            const PrivioNavItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: 'Paramètres',
            ),
          ],
        ),
      ),
    );
  }
}

class PrivioNavItem {
  const PrivioNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Pastille (0 : aucune).
  final int badge;
}

/// Barre de navigation « piste C » : basse, trait violet au-dessus de l'onglet actif,
/// pastilles de non-lus et d'invitations.
class PrivioNavBar extends StatelessWidget {
  const PrivioNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<PrivioNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Material(
      color: p.navigation,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (final (i, item) in items.indexed)
                  Expanded(
                    child: _NavButton(
                      item: item,
                      selected: i == currentIndex,
                      accent: p.accentText,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final PrivioNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? accent : theme.colorScheme.onSurfaceVariant;
    final badgeText = item.badge > 99 ? '99+' : '${item.badge}';
    final semantics = item.badge > 0 ? '${item.label}, ${item.badge} en attente' : item.label;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        key: Key('nav.${item.label}'),
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 32 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
            const Spacer(),
            Badge(
              isLabelVisible: item.badge > 0,
              label: Text(badgeText),
              backgroundColor: accent,
              child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 24),
            ),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
