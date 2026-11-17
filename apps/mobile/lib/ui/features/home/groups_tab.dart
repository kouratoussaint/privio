import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/join_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/brand_scaffold.dart';
import '../../core/widgets/state_views.dart';
import 'discussions_tab.dart'
    show
        AnimatedOfflineBanner,
        FilterBar,
        FilterPill,
        ListSearchField,
        SwipeableConversationTile,
        matchesSearch;
import '../../core/motion/illustrations.dart';
import '../../../state/providers.dart';
import 'list_menu.dart';
import '../../core/motion/motion.dart';
import '../../core/widgets/announcement_banner.dart';
import '../../core/widgets/update_banner.dart';

/// Écran 17 — groupes : invitations reçues (à accepter ou refuser), puis ses groupes.
/// Un groupe est simplement une discussion à plusieurs, rien de plus.
class GroupsTab extends ConsumerStatefulWidget {
  const GroupsTab({super.key});

  @override
  ConsumerState<GroupsTab> createState() => _GroupsTabState();
}

/// Lot 7.2c1 : filtres de l'onglet Groupes (comme ceux de Discussions).
enum GroupFilter { all, unread, pinned }

class _GroupsTabState extends ConsumerState<GroupsTab> {
  final _search = TextEditingController();
  GroupFilter _filter = GroupFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  /// Recherche ou filtre en cours : seuls les groupes correspondants sont montrés.
  bool get _narrowed => _query.isNotEmpty || _filter != GroupFilter.all;

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    GroupInvitation invitation, {
    required bool accept,
  }) async {
    try {
      final id = await ref
          .read(messagingApiProvider)
          .respondToInvitation(invitation.id, accept: accept);
      ref
        ..invalidate(invitationsProvider)
        ..invalidate(conversationsProvider);
      if (id != null && context.mounted) unawaited(context.push(Routes.chat(id)));
    } on Object catch (e) {
      ref.invalidate(invitationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  Future<void> _cancelRequest(BuildContext context, WidgetRef ref, MyJoinRequest r) async {
    try {
      await ref.read(messagingApiProvider).cancelJoinRequest(r.conversationId);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    } finally {
      ref.invalidate(myJoinRequestsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(appFeaturesProvider);
    final invitations = ref.watch(invitationsProvider).value ?? const <GroupInvitation>[];
    final myRequests = ref.watch(myJoinRequestsProvider).value ?? const <MyJoinRequest>[];
    final notices = ref.watch(groupDeletionNoticesProvider).value ?? const <GroupDeletionNotice>[];
    final conversations = ref.watch(listedConversationsProvider);
    final all = (conversations.value ?? const <ConversationSummary>[])
        .where((c) => c.isGroup)
        .toList();
    final local = ref.read(localCacheProvider).allMessages;
    final groups = all
        .where((c) => !c.archived && matchesSearch(c, _query, local))
        .where(
          (c) => switch (_filter) {
            GroupFilter.all => true,
            GroupFilter.unread => c.unreadCount > 0,
            GroupFilter.pinned => c.pinned,
          },
        )
        .toList();
    final unreadCount = all.where((c) => !c.archived && c.unreadCount > 0).length;
    final archivedCount = all.where((c) => c.archived).length;
    final offline = ref.watch(offlineProvider);

    return BrandScaffold(
      title: Text(L.t.groupes),
      // Lot 7.1b : entrer dans un groupe avec un code ou un QR code.
      actions: [
        if (features.groupInviteLinks)
          IconButton(
            key: const Key('groups.join'),
            tooltip: L.t.rejoindreGroupe,
            onPressed: () => context.push(Routes.joinGroup),
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        // Lot 8.3a : menu ⋮ (rejoindre, demandes envoyées, archivés, tout marquer lu…).
        const ListMenuButton(kind: ListMenuKind.groups),
      ],
      // Lot 5.5 : création de groupes coupée dans la console → pas de bouton.
      floatingActionButton: !features.groupCreate
          ? null
          : FloatingActionButton.extended(
              key: const Key('groups.new'),
              // Chaque onglet garde son bouton : étiquettes Hero distinctes.
              heroTag: 'fab.groups',
              onPressed: () => context.push(Routes.newGroup),
              icon: const Icon(Icons.group_add_outlined),
              label: Text(L.t.nouveauGroupe),
            ),
      // Lot 7.2a : fond blanc, comme la liste des discussions.
      // (Material : les lignes touchables y dessinent leur effet d'appui.)
      body: Material(
        color: PrivioPalette.of(context).sheet,
        child: Column(
          children: [
            // Lot 5.5 : message d'information de la console.
            const AnnouncementBanner(),
            // Lot 5.7 : nouvelle version conseillée.
            const UpdateBanner(),
            // Lot 7.2c1 : recherche et filtres, comme dans Discussions.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.l,
                PrivioSpacing.l,
                PrivioSpacing.l,
                PrivioSpacing.m,
              ),
              child: ListSearchField(key: const Key('groups.search'), controller: _search),
            ),
            SizedBox(
              height: 48,
              child: FilterBar(
                chips: [
                  FilterPill(
                    key: const Key('groups.filter.all'),
                    label: L.t.tous,
                    selected: _filter == GroupFilter.all,
                    onTap: () => setState(() => _filter = GroupFilter.all),
                  ),
                  FilterPill(
                    key: const Key('groups.filter.unread'),
                    label: L.t.nonLus,
                    count: unreadCount,
                    selected: _filter == GroupFilter.unread,
                    onTap: () => setState(() => _filter = GroupFilter.unread),
                  ),
                  FilterPill(
                    key: const Key('groups.filter.pinned'),
                    label: L.t.epingles,
                    selected: _filter == GroupFilter.pinned,
                    onTap: () => setState(() => _filter = GroupFilter.pinned),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PrivioSpacing.s),
            AnimatedOfflineBanner(offline: offline),
            if (archivedCount > 0 && !_narrowed)
              ListTile(
                key: const Key('groups.archived'),
                leading: const Icon(Icons.archive_outlined),
                title: Text(L.t.archivesArchivedcount(archivedCount)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.archivedOf('groupes')),
              ),
            Expanded(
              child: _body(
                context,
                ref,
                conversations,
                _narrowed ? const [] : invitations,
                groups,
                _narrowed ? const [] : myRequests,
                _narrowed ? const [] : notices,
                hasArchived: archivedCount > 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ConversationSummary>> conversations,
    List<GroupInvitation> invitations,
    List<ConversationSummary> groups,
    List<MyJoinRequest> myRequests,
    List<GroupDeletionNotice> notices, {
    bool hasArchived = false,
  }) {
    final theme = Theme.of(context);
    if (!conversations.hasValue && conversations.isLoading) return const SkeletonList();
    if (conversations case AsyncError(:final error)) {
      return ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref
          ..invalidate(conversationsProvider)
          ..invalidate(invitationsProvider),
      );
    }
    // Lot 4.8 : tirer vers le bas recharge les groupes ET les invitations.
    Future<void> reload() async {
      await Future.wait([
        ref.read(conversationsProvider.notifier).refresh(),
        ref.refresh(invitationsProvider.future).then((_) {}, onError: (Object _) {}),
        ref.refresh(myJoinRequestsProvider.future).then((_) {}, onError: (Object _) {}),
        ref.refresh(groupDeletionNoticesProvider.future).then((_) {}, onError: (Object _) {}),
      ]);
    }

    return RefreshIndicator(
      key: const Key('groups.refresh'),
      onRefresh: reload,
      child: _narrowed && groups.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: EmptyView(
                    key: const Key('groups.no_match'),
                    icon: Icons.search_off_rounded,
                    title: L.t.aucunGroupeTrouve,
                    message: _query.isNotEmpty
                        ? L.t.aucunGroupeNeCorrespondText(_search.text.trim())
                        : L.t.aucunGroupeDansCeFiltre,
                  ),
                ),
              ),
            )
          : invitations.isEmpty &&
                groups.isEmpty &&
                myRequests.isEmpty &&
                notices.isEmpty &&
                !hasArchived
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: EmptyView(
                    icon: Icons.groups_outlined,
                    title: L.t.aucunGroupePourInstant,
                    message: L.t.creezGroupeInvitezVosContacts,
                  ),
                ),
              ),
            )
          : EntranceScope(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: PrivioSpacing.s, bottom: 96),
                children: [
                  // Lot 7.2b1 : groupes supprimés par un administrateur (avis à fermer).
                  for (final n in notices)
                    ListTile(
                      key: Key('notice.${n.id}'),
                      leading: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(L.t.groupeTitleEteSupprime(n.title)),
                      subtitle: Text(L.t.parAdministrateurGroupe),
                      trailing: IconButton(
                        key: Key('notice.dismiss.${n.id}'),
                        tooltip: L.t.fermer,
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          try {
                            await ref.read(messagingApiProvider).dismissGroupDeletionNotice(n.id);
                          } on Object catch (_) {
                            // Hors connexion : l'avis reviendra et pourra être fermé plus tard.
                          }
                          ref.invalidate(groupDeletionNoticesProvider);
                        },
                      ),
                    ),
                  if (invitations.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                      child: Text(L.t.invitations, style: theme.textTheme.titleSmall),
                    ),
                    for (final i in invitations)
                      _InvitationCard(invitation: i, onRespond: _respond),
                    const SizedBox(height: PrivioSpacing.m),
                  ],
                  // Lot 7.1b : mes demandes pour rejoindre un groupe, en attente.
                  if (myRequests.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                      child: Text(L.t.demandesEnvoyees, style: theme.textTheme.titleSmall),
                    ),
                    for (final r in myRequests)
                      ListTile(
                        key: Key('my_join.${r.conversationId}'),
                        leading: const Icon(Icons.hourglass_top_rounded),
                        title: Text(r.title),
                        subtitle: Text(L.t.attenteAdministrateur),
                        trailing: TextButton(
                          key: Key('my_join.cancel.${r.conversationId}'),
                          onPressed: () => _cancelRequest(context, ref, r),
                          child: Text(L.t.annuler),
                        ),
                      ),
                    const SizedBox(height: PrivioSpacing.m),
                  ],
                  // Lot 7.2c1 : glisser pour épingler ou archiver, appui long pour plus.
                  for (final (i, g) in groups.indexed)
                    Entrance(
                      index: i,
                      child: SwipeableConversationTile(summary: g),
                    ),
                ],
              ),
            ),
    );
  }
}

class _InvitationCard extends ConsumerWidget {
  const _InvitationCard({required this.invitation, required this.onRespond});

  final GroupInvitation invitation;
  final Future<void> Function(
    BuildContext context,
    WidgetRef ref,
    GroupInvitation invitation, {
    required bool accept,
  })
  onRespond;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final i = invitation;
    return Card(
      key: Key('invitation.${i.id}'),
      margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l, vertical: PrivioSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: i.title,
                  avatarPath: i.avatarPath,
                  seed: i.conversationId,
                  icon: Icons.groups_rounded,
                  radius: 22,
                ),
                const SizedBox(width: PrivioSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.title, style: theme.textTheme.titleSmall),
                      Text(
                        L.t.groupInviteLine(i.inviterName ?? L.t.someone, i.memberCount),
                        style: theme.textTheme.bodySmall?.copyWith(color: p.accentText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((i.description ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: PrivioSpacing.s),
                child: Text(i.description!, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: PrivioSpacing.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('invitation.decline.${i.id}'),
                  onPressed: () => onRespond(context, ref, i, accept: false),
                  child: Text(L.t.refuser),
                ),
                const SizedBox(width: PrivioSpacing.s),
                FilledButton(
                  key: Key('invitation.accept.${i.id}'),
                  onPressed: () => onRespond(context, ref, i, accept: true),
                  child: Text(L.t.rejoindre),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
