import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/join_providers.dart';
import '../../../state/messaging_providers.dart';
import '../conversations/person_card.dart';
import '../../../ui/features/groups/join_group_screen.dart';

/// Lot 8.3a : menu ⋮ en haut des listes Discussions et Groupes.
enum ListMenuKind { discussions, groups }

enum _Action { newConversation, scan, requests, join, sent, archived, favorites, readAll, lock }

class ListMenuButton extends ConsumerWidget {
  const ListMenuButton({super.key, required this.kind});

  final ListMenuKind kind;

  bool get _groups => kind == ListMenuKind.groups;

  /// Discussions de cette liste (les groupes en font partie s'ils sont réunis).
  bool Function(ConversationSummary) _belongs(bool together) =>
      _groups ? (c) => c.isGroup : (c) => together || !c.isGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final together = ref.watch(groupsInDiscussionsProvider).value ?? false;
    final belongs = _belongs(together);
    final list = (ref.watch(conversationsProvider).value ?? const <ConversationSummary>[])
        .where(belongs)
        .toList();
    final archived = list.where((c) => c.archived).length;
    final unread = list.where((c) => !c.archived && c.unreadCount > 0).length;
    final requests = _groups ? 0 : ref.watch(incomingRequestCountProvider);
    final sent = _groups ? (ref.watch(myJoinRequestsProvider).value?.length ?? 0) : 0;
    final lockOn = ref.watch(appLockProvider).value?.enabled ?? false;
    final prefix = _groups ? 'groups' : 'discussions';
    // Couleur explicite : le menu hérite sinon des icônes blanches de la barre du haut.
    final iconColor = PrivioPalette.of(context).accentText;

    PopupMenuItem<_Action> item(
      _Action a,
      String key,
      IconData icon,
      String label, {
      bool enabled = true,
    }) => PopupMenuItem(
      key: Key('$prefix.menu.$key'),
      value: a,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 14),
          Flexible(child: Text(label)),
        ],
      ),
    );

    return PopupMenuButton<_Action>(
      key: Key('$prefix.menu'),
      tooltip: L.t.plusOptions,
      icon: const Icon(Icons.more_vert),
      onSelected: (a) => _run(context, ref, a, together: together, unread: unread),
      itemBuilder: (_) => [
        if (!_groups) ...[
          // Correction du 15/11/2026 : « Nouvelle discussion » (le groupe a son onglet).
          item(
            _Action.newConversation,
            'new_conversation',
            Icons.edit_outlined,
            L.t.nouvelleDiscussion,
          ),
          item(_Action.scan, 'scan', Icons.qr_code_scanner_rounded, L.t.scannerQrCode),
          item(
            _Action.requests,
            'requests',
            Icons.person_add_alt_1_outlined,
            requests > 0 ? L.t.demandesConnexionCount(requests) : L.t.demandesConnexion,
          ),
        ] else ...[
          item(_Action.join, 'join', Icons.qr_code_scanner_rounded, L.t.rejoindreGroupe),
          item(
            _Action.sent,
            'sent',
            Icons.hourglass_top_rounded,
            sent > 0 ? L.t.demandesEnvoyeesCount(sent) : L.t.demandesEnvoyees,
          ),
        ],
        item(
          _Action.archived,
          'archived',
          Icons.archive_outlined,
          _groups
              ? (archived > 0 ? L.t.archivesArchivedcount(archived) : L.t.archivesTitle)
              : (archived > 0 ? L.t.archiveesArchivedcount(archived) : L.t.archivees),
        ),
        if (!_groups)
          item(_Action.favorites, 'favorites', Icons.star_outline_rounded, L.t.messagesFavoris),
        item(
          _Action.readAll,
          'read_all',
          Icons.mark_chat_read_outlined,
          L.t.toutMarquerCommeLu,
          enabled: unread > 0,
        ),
        if (lockOn) item(_Action.lock, 'lock', Icons.lock_outline, L.t.verrouillerMaintenant),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _Action a, {
    required bool together,
    required int unread,
  }) async {
    switch (a) {
      case _Action.newConversation:
        await context.push(Routes.newConversation);
      case _Action.scan:
        await _scan(context, ref);
      case _Action.requests:
        await context.push(Routes.requests);
      case _Action.join:
        await context.push(Routes.joinGroup);
      case _Action.sent:
        await _showSent(context);
      case _Action.archived:
        await context.push(
          _groups
              ? Routes.archivedOf('groupes')
              : together
              ? Routes.archived
              : Routes.archivedOf('discussions'),
        );
      case _Action.favorites:
        await context.push(Routes.favorites);
      case _Action.readAll:
        await _readAll(context, ref, together: together, unread: unread);
      case _Action.lock:
        ref.read(appLockProvider.notifier).lockNow();
    }
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final handle = await ref.read(profileQrScannerProvider)(context);
    if (handle == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await ref.read(messagingApiProvider).findByHandle(handle);
      if (!context.mounted) return;
      if (user == null) {
        messenger.showSnackBar(SnackBar(content: Text(L.t.aucunCompteTrouvePourHandle(handle))));
        return;
      }
      await openPerson(
        context,
        ref,
        userId: user.id,
        name: user.displayName,
        handle: user.handle,
        avatarPath: user.avatarPath,
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  Future<void> _readAll(
    BuildContext context,
    WidgetRef ref, {
    required bool together,
    required int unread,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.markAllReadTitle),
        content: Text(L.t.markAllReadBody(unread)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('menu.read_all.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.marquerCommeLu),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref
          .read(conversationsProvider.notifier)
          .markAllRead(where: _belongs(together));
      messenger.showSnackBar(SnackBar(content: Text(L.t.markAllReadDone(n))));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  Future<void> _showSent(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SentRequestsSheet(),
  );
}

/// Mes demandes pour rejoindre un groupe, en attente (annulables).
class _SentRequestsSheet extends ConsumerWidget {
  const _SentRequestsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requests = ref.watch(myJoinRequestsProvider).value ?? const <MyJoinRequest>[];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(L.t.demandesEnvoyees, style: theme.textTheme.titleMedium),
          ),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(L.t.aucuneDemandeEnvoyee, style: theme.textTheme.bodyMedium),
            ),
          for (final r in requests)
            ListTile(
              key: Key('sent.${r.conversationId}'),
              leading: const Icon(Icons.hourglass_top_rounded),
              title: Text(r.title),
              subtitle: Text(L.t.attenteAdministrateur),
              trailing: TextButton(
                key: Key('sent.cancel.${r.conversationId}'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(messagingApiProvider).cancelJoinRequest(r.conversationId);
                  } on Object catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                  } finally {
                    ref.invalidate(myJoinRequestsProvider);
                  }
                },
                child: Text(L.t.annuler),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
