import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/push_service.dart'
    show kConsoleTarget, kGroupInfoPrefix, kGroupsTarget, kRequestsTarget, kSupportTarget;
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/push_providers.dart';
import '../../../domain/models/messaging.dart';
import '../../core/motion/motion.dart';

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

  static String get exitHint => L.t.appuyezEncoreSurRetourPour;

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
        SnackBar(
          key: const Key('home.exit_hint'),
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
      // Notification de demande de connexion (lot 4.7) : l'écran des demandes ;
      // d'invitation de groupe (lot 4.8) : l'onglet Groupes, invitations à jour.
      if (id == kGroupsTarget) {
        ref.invalidate(invitationsProvider);
        context.go(Routes.groups);
        return;
      }
      // Demande d'adhésion (lot 7.1b) : le groupe, puis sa fiche (liste des demandes).
      if (id.startsWith(kGroupInfoPrefix)) {
        final group = id.substring(kGroupInfoPrefix.length);
        context.push(Routes.chat(group));
        context.push(Routes.contact(group));
        return;
      }
      context.push(switch (id) {
        kRequestsTarget => Routes.requests,
        kConsoleTarget => Routes.console,
        kSupportTarget => Routes.mySupport,
        _ => Routes.chat(id),
      });
    });
    final shell = widget.shell;
    // Lot 7.2b1 : séparés (par défaut), les groupes non lus comptent dans l'onglet Groupes.
    final together = ref.watch(groupsInDiscussionsProvider).value ?? false;
    final unreadList =
        ref.watch(conversationsProvider).value?.where((c) => !c.archived && c.unreadCount > 0) ??
        const <ConversationSummary>[];
    final unread = unreadList.where((c) => together || !c.isGroup).length;
    final unreadGroups = together ? 0 : unreadList.where((c) => c.isGroup).length;
    // Lot 4.7 : les demandes de connexion reçues comptent dans la pastille Discussions.
    final requests = ref.watch(incomingRequestCountProvider);
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
              label: L.t.discussions,
              badge: unread + requests,
            ),
            PrivioNavItem(
              icon: Icons.groups_outlined,
              selectedIcon: Icons.groups,
              label: L.t.groupes,
              badge: invitations + unreadGroups,
            ),
            PrivioNavItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: L.t.parametres,
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
    final semantics = item.badge > 0 ? L.t.labelBadgeAttente(item.label, item.badge) : item.label;
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
              // Lot 7.2b2 : la pastille saute quand le nombre change ; l'icône de l'onglet
              // choisi rebondit.
              label: PopOnChange(value: badgeText, child: Text(badgeText)),
              backgroundColor: accent,
              child: PopOnChange(
                value: selected,
                pop: selected,
                child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 24),
              ),
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
