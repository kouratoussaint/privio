import '../../../l10n/l10n.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/handle/handle_rules.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';
import '../../../data/services/photo_picker.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/join_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../../state/providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ttl_picker.dart';
import '../conversations/conversation_details.dart';
import '../conversations/contact_screen.dart';
import '../conversations/report_sheet.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/success_snack.dart';
import '../../../state/feedback_providers.dart';
import '../conversations/message_extras.dart';
import '../settings/wallpaper.dart';
import '../conversations/person_card.dart';
import '../../core/widgets/privio_menu.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ---------------------------------------------------------------------------
// Choix des personnes à inviter : recherche exacte (identifiant ou numéro autorisé)
// et personnes avec qui l'on a déjà une discussion.
// ---------------------------------------------------------------------------
class MemberPicker extends ConsumerStatefulWidget {
  const MemberPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.exclude = const {},
  });

  final Map<String, FoundUser> selected;
  final ValueChanged<Map<String, FoundUser>> onChanged;

  /// Déjà membres ou invités : non proposés.
  final Set<String> exclude;

  @override
  ConsumerState<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<MemberPicker> {
  final _search = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(FoundUser u) {
    final next = Map<String, FoundUser>.of(widget.selected);
    if (next.remove(u.id) == null) next[u.id] = u;
    widget.onChanged(next);
  }

  Future<void> _find() async {
    final input = _search.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final api = ref.read(messagingApiProvider);
    try {
      FoundUser? user;
      if (PhoneNumber.looksLikePhone(input)) {
        user = await api.findByPhone(PhoneNumber.normalize(input)!);
      } else {
        final handle = HandleRules.normalize(input);
        final issue = HandleRules.validate(handle);
        if (issue != null) {
          setState(() => _message = HandleRules.message(issue));
          return;
        }
        user = await api.findByHandle(handle);
      }
      if (user == null) {
        setState(() => _message = L.t.aucunCompteNeCorrespond);
      } else if (widget.exclude.contains(user.id)) {
        setState(() => _message = L.t.displaynameFaitDejaPartieGroupe(user!.displayName));
      } else {
        _search.clear();
        if (!widget.selected.containsKey(user.id)) _toggle(user);
      }
    } on Object catch (e) {
      setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contacts = [
      for (final c in ref.watch(conversationsProvider).value ?? const <ConversationSummary>[])
        if (!c.isGroup &&
            !c.blocked &&
            !c.peerDeleted &&
            c.peerId != null &&
            !widget.exclude.contains(c.peerId))
          FoundUser(
            id: c.peerId!,
            handle: c.peerHandle ?? '',
            displayName: c.title,
            avatarPath: c.peerAvatarPath,
          ),
    ];
    final extra = widget.selected.values.where((u) => !contacts.any((c) => c.id == u.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('picker.search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _find(),
          decoration: InputDecoration(
            hintText: L.t.identifiantPrivioExAwaOu,
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: IconButton(
              key: const Key('picker.submit'),
              tooltip: L.t.ajouter,
              onPressed: _busy ? null : _find,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: PrivioSpacing.s),
            child: Text(
              _message!,
              key: const Key('picker.message'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: PrivioSpacing.m),
        if (contacts.isNotEmpty || extra.isNotEmpty)
          Text(L.t.vosContacts, style: theme.textTheme.labelLarge),
        for (final u in [...extra, ...contacts])
          CheckboxListTile(
            key: Key('picker.user.${u.id}'),
            value: widget.selected.containsKey(u.id),
            onChanged: (_) => _toggle(u),
            contentPadding: EdgeInsets.zero,
            secondary: UserAvatar(
              name: u.displayName,
              avatarPath: u.avatarPath,
              seed: u.id,
              radius: 20,
            ),
            title: Text(u.displayName),
            subtitle: u.handle.isEmpty ? null : Text('@${u.handle}'),
          ),
        Padding(
          padding: const EdgeInsets.only(top: PrivioSpacing.s),
          child: Text(
            L.t.chaquePersonneRecoitInvitationChoisit,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Confirmation après création (lot 4.8).
String createdGroupMessage(int invited) => switch (invited) {
  0 => L.t.groupeCree,
  1 => L.t.groupeCree1InvitationEnvoyee,
  _ => L.t.groupeCreeInvitedInvitationsEnvoyees(invited),
};

// ---------------------------------------------------------------------------
// Écran 18 — nouveau groupe
// ---------------------------------------------------------------------------
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  Map<String, FoundUser> _selected = {};
  bool _busy = false;

  /// Lot 7.2c1 : photo choisie avant la création (déjà réduite, sans métadonnées).
  Uint8List? _photo;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('new_group.photo.camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(L.t.prendrePhoto),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              key: const Key('new_group.photo.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(L.t.choisirDansGalerie),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_photo != null)
              ListTile(
                key: const Key('new_group.photo.remove'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(L.t.retirerPhoto),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() => _photo = null);
      return;
    }
    try {
      final source = choice == 'camera' ? PhotoSource.camera : PhotoSource.gallery;
      final raw = await ref
          .read(appLockProvider.notifier)
          .runExternal(() => ref.read(photoPickerProvider).pick(source));
      if (raw == null) return;
      final photo = await ref.read(photoPreparerProvider)(raw, avatar: true);
      if (mounted) setState(() => _photo = photo.bytes);
    } on Object catch (e) {
      if (mounted) _toast(context, toAppFailure(e).message);
    }
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) {
      _toast(context, const AppFailure(FailureCode.groupTitleInvalid).message);
      return;
    }
    setState(() => _busy = true);
    final title = _title.text.trim();
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();
    final invited = _selected.length;
    try {
      final id = await ref
          .read(messagingApiProvider)
          .createGroup(title: title, description: description, inviteeIds: _selected.keys.toList());
      // Lot 4.8 : le groupe s'affiche tout de suite (plus d'attente de la liste complète).
      ref
          .read(conversationsProvider.notifier)
          .addCreatedGroup(
            id: id,
            title: title,
            description: description,
            ttlSeconds: ref.read(privacyProvider).value?.defaultTtlSeconds ?? 259200,
          );
      // Lot 7.2c1 : la photo choisie part juste après la création. Un échec n'annule pas
      // le groupe : elle pourra être ajoutée depuis la fiche.
      var photoFailed = false;
      final photo = _photo;
      if (photo != null) {
        try {
          await ref.read(messagingApiProvider).setGroupAvatar(id, photo);
          countDataW(ref, sent: photo.length);
          await ref.read(conversationsProvider.notifier).refresh();
        } on Object catch (_) {
          photoFailed = true;
        }
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      ref.read(feedbackProvider).sound(PrivioSound.success);
      context.pushReplacement(Routes.chat(id));
      messenger.showSnackBar(
        photoFailed
            ? SnackBar(key: const Key('group.created'), content: Text(L.t.groupeCreePhotoNPas))
            : successSnack(createdGroupMessage(invited), key: const Key('group.created')),
      );
    } on Object catch (e) {
      if (mounted) _toast(context, toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
    backgroundColor: PrivioPalette.of(context).sheet,
    appBar: AppBar(title: Text(L.t.nouveauGroupe)),
    body: ListView(
      padding: const EdgeInsets.all(PrivioSpacing.xl),
      children: [
        // Lot 7.2c1 : photo du groupe dès la création (facultative), à côté du nom.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: PrivioSpacing.m),
              child: Semantics(
                button: true,
                label: _photo == null ? L.t.ajouterPhotoGroupe : L.t.changerPhotoGroupe,
                child: InkWell(
                  key: const Key('new_group.photo'),
                  customBorder: const CircleBorder(),
                  onTap: _busy ? null : _pickPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        foregroundImage: _photo == null ? null : MemoryImage(_photo!),
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (_photo != null)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: PrivioPalette.of(context).sheet, width: 2),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 12,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: const Key('group.title'),
                controller: _title,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: L.t.nomGroupe),
              ),
            ),
          ],
        ),
        TextField(
          key: const Key('group.description'),
          controller: _description,
          maxLength: 300,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: L.t.descriptionFacultative),
        ),
        const SizedBox(height: PrivioSpacing.l),
        Text(L.t.inviter, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.s),
        MemberPicker(selected: _selected, onChanged: (s) => setState(() => _selected = s)),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          key: const Key('group.create'),
          onPressed: _busy ? null : _create,
          child: _busy
              ? Row(
                  key: const Key('group.creating'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: PrivioSpacing.m),
                    Flexible(child: Text(L.t.creationGroupe)),
                  ],
                )
              : Text(_selected.isEmpty ? L.t.creerGroupe : L.t.createAndInvite(_selected.length)),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Inviter dans un groupe existant (administrateurs)
// ---------------------------------------------------------------------------
class InviteMembersScreen extends ConsumerStatefulWidget {
  const InviteMembersScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<InviteMembersScreen> createState() => _InviteMembersScreenState();
}

class _InviteMembersScreenState extends ConsumerState<InviteMembersScreen> {
  Map<String, FoundUser> _selected = {};
  bool _busy = false;

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final n = await groupAction(
        ref,
        widget.conversationId,
        (api) => api.inviteToGroup(widget.conversationId, _selected.keys.toList()),
      );
      if (!mounted) return;
      _toast(context, n == 0 ? L.t.aucuneInvitationEnvoyeeDejaMembres : L.t.invitationsSent(n));
      context.pop();
    } on Object catch (e) {
      if (mounted) _toast(context, toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.conversationId)).value ?? const [];
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: Text(L.t.inviter)),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        children: [
          MemberPicker(
            selected: _selected,
            exclude: {for (final m in members) m.userId},
            onChanged: (s) => setState(() => _selected = s),
          ),
          const SizedBox(height: PrivioSpacing.xl),
          FilledButton(
            key: const Key('invite.send'),
            onPressed: _busy || _selected.isEmpty ? null : _invite,
            child: Text(L.t.invitePeople(_selected.length)),
          ),
        ],
      ),
    );
  }
}

/// Fiche d'une discussion : contact (1:1) ou informations du groupe.
class ConversationInfoScreen extends ConsumerWidget {
  const ConversationInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(conversationSummaryProvider(conversationId));
    return summary?.isGroup ?? false
        ? GroupInfoScreen(conversationId: conversationId)
        : ContactScreen(conversationId: conversationId);
  }
}

// ---------------------------------------------------------------------------
// Écran 20 — informations, membres et réglages du groupe
// ---------------------------------------------------------------------------
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? done,
  }) async {
    try {
      await action();
      if (done != null && context.mounted) _toast(context, done);
    } on Object catch (e) {
      if (context.mounted) _toast(context, toAppFailure(e).message);
    }
  }

  Future<void> _editInfo(BuildContext context, WidgetRef ref, ConversationSummary s) async {
    final title = TextEditingController(text: s.groupTitle);
    final description = TextEditingController(text: s.groupDescription ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.modifierGroupe),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('group.edit.title'),
              controller: title,
              maxLength: 60,
              decoration: InputDecoration(labelText: L.t.nomGroupe),
            ),
            TextField(
              key: const Key('group.edit.description'),
              controller: description,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: L.t.description),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('group.edit.save'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.enregistrer),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () => groupAction(
        ref,
        conversationId,
        (api) =>
            api.updateGroupInfo(conversationId, title: title.text, description: description.text),
      ),
    );
  }

  Future<void> _editPhoto(BuildContext context, WidgetRef ref, ConversationSummary s) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('group.photo.camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(L.t.prendrePhoto),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              key: const Key('group.photo.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(L.t.choisirDansGalerie),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (s.groupAvatarPath != null)
              ListTile(
                key: const Key('group.photo.remove'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(L.t.retirerPhoto),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await _run(context, ref, () async {
      if (choice == 'remove') {
        await groupAction(ref, conversationId, (api) => api.removeGroupAvatar(conversationId));
        return;
      }
      final source = choice == 'camera' ? PhotoSource.camera : PhotoSource.gallery;
      final raw = await ref
          .read(appLockProvider.notifier)
          .runExternal(() => ref.read(photoPickerProvider).pick(source));
      if (raw == null) return;
      final photo = await ref.read(photoPreparerProvider)(raw, avatar: true);
      await groupAction(
        ref,
        conversationId,
        (api) => api.setGroupAvatar(conversationId, photo.bytes),
      );
      countDataW(ref, sent: photo.bytes.length);
    });
  }

  Future<void> _memberActions(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary s,
    GroupMember m,
  ) async {
    // Lot 8.5a : carte flottante près du membre appuyé.
    final action = await PrivioMenu.show<String>(
      context,
      title: '${m.displayName} · ${m.roleLabel}',
      items: [
        if (m.role == 'member')
          PrivioMenuItem(
            key: const Key('member.make_admin'),
            value: 'admin',
            icon: Icons.shield_outlined,
            label: L.t.nommerAdministrateur,
            tint: MenuTint.violet,
          ),
        if (m.role == 'admin' && s.isOwner)
          PrivioMenuItem(
            key: const Key('member.remove_admin'),
            value: 'member',
            icon: Icons.remove_moderator_outlined,
            label: L.t.retirerRoleAdministrateur,
            tint: MenuTint.amber,
          ),
        if (s.isOwner)
          PrivioMenuItem(
            key: const Key('member.transfer'),
            value: 'transfer',
            icon: Icons.workspace_premium_outlined,
            label: L.t.nommerProprietaire,
            tint: MenuTint.blue,
          ),
        if (m.role == 'member' || (m.role == 'admin' && s.isOwner))
          PrivioMenuItem(
            key: const Key('member.remove'),
            value: 'remove',
            icon: Icons.person_remove_outlined,
            label: L.t.retirerGroupe,
            danger: true,
          ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'remove' || action == 'transfer') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            action == 'remove'
                ? L.t.retirerDisplayname(m.displayName)
                : L.t.confierGroupeDisplayname(m.displayName),
          ),
          content: Text(
            action == 'remove'
                ? L.t.displaynameNeVerraPlusMessages(m.displayName)
                : L.t.vousResterezAdministrateur,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
            FilledButton(
              key: const Key('member.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t.confirmer),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await _run(
      context,
      ref,
      () => groupAction(ref, conversationId, (api) async {
        switch (action) {
          case 'admin':
            await api.setMemberRole(conversationId, m.userId, admin: true);
          case 'member':
            await api.setMemberRole(conversationId, m.userId, admin: false);
          case 'transfer':
            await api.transferOwnership(conversationId, m.userId);
          case 'remove':
            await api.removeMember(conversationId, m.userId);
        }
      }),
    );
  }

  /// Durée des messages du groupe (lot 4.6) : administrateurs autorisés à modifier le groupe.
  Future<void> _ttl(BuildContext context, WidgetRef ref, ConversationSummary s) async {
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final picked = await showTtlPicker(
      context,
      title: L.t.dureeMessages,
      help: L.t.pourProchainsMessagesGroupe,
      current: s.ttlSeconds,
      min: rules.minTtlSeconds,
      max: rules.maxTtlSeconds,
    );
    if (picked == null || picked == s.ttlSeconds || !context.mounted) return;
    await _run(
      context,
      ref,
      () =>
          groupAction(ref, conversationId, (api) => api.setConversationTtl(conversationId, picked)),
    );
  }

  Future<void> _mute(BuildContext context, WidgetRef ref, ConversationSummary s) async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<Duration?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, d) in [
              (L.t.n8Heures, const Duration(hours: 8)),
              (L.t.n1Semaine, const Duration(days: 7)),
              (L.t.toujours, const Duration(days: 3650)),
            ])
              ListTile(
                key: Key('mute.${d.inHours}'),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, d),
              ),
            if (s.isMuted(now))
              ListTile(
                key: const Key('mute.off'),
                title: Text(L.t.reactiverNotifications),
                onTap: () => Navigator.pop(ctx, Duration.zero),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => groupAction(
        ref,
        conversationId,
        (api) => api.setMute(conversationId, choice == Duration.zero ? null : now.add(choice)),
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, ConversationSummary s) async {
    if (await confirmLeaveGroup(context, ref, s) && context.mounted) context.go(Routes.groups);
  }

  /// Lot 7.1b : accepter (la personne entre, message système) ou refuser une demande.
  Future<void> _answerJoin(
    BuildContext context,
    WidgetRef ref,
    JoinRequest r, {
    required bool approve,
  }) => _run(context, ref, () async {
    try {
      await groupAction(
        ref,
        conversationId,
        (api) => api.respondToJoinRequest(r.id, approve: approve),
      );
    } finally {
      ref
        ..invalidate(groupJoinRequestsProvider(conversationId))
        ..invalidate(groupJoinSettingsProvider(conversationId));
    }
  }, done: approve ? L.t.displaynameRejointGroupe(r.displayName) : L.t.demandeRefusee);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final s = ref.watch(conversationSummaryProvider(conversationId));
    final members = ref.watch(groupMembersProvider(conversationId));
    final me = ref.watch(currentUserIdProvider);
    if (s == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final now = DateTime.now();
    final admin = s.isAdmin && !s.isClosed;
    final joinSettings = admin ? ref.watch(groupJoinSettingsProvider(conversationId)).value : null;
    final requests = admin
        ? ref.watch(groupJoinRequestsProvider(conversationId)).value ?? const <JoinRequest>[]
        : const <JoinRequest>[];
    final active = (members.value ?? const <GroupMember>[]).where((m) => !m.invited).toList();
    final invited = (members.value ?? const <GroupMember>[]).where((m) => m.invited).toList();

    // Lot 7.2a : une carte blanche par partie, comme Paramètres.
    return Scaffold(
      appBar: AppBar(title: Text(L.t.infos)),
      body: SettingsListView(
        children: [
          SettingsCard(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              // Lot 7.1a : toucher la photo l'ouvre en grand ; les administrateurs la changent.
              FicheAvatar(
                key: const Key('group.photo'),
                name: s.title,
                path: s.groupAvatarPath,
                seed: s.id,
                icon: Icons.groups_rounded,
                onEdit: s.canEditInfo ? () => _editPhoto(context, ref, s) : null,
              ),
              // Lot 7.2c1 : ajouter ou changer la photo, sans avoir à deviner le geste.
              if (s.canEditInfo)
                Center(
                  child: TextButton.icon(
                    key: const Key('group.photo.edit'),
                    onPressed: () => _editPhoto(context, ref, s),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(s.groupAvatarPath == null ? L.t.ajouterPhoto : L.t.changerPhoto),
                  ),
                ),
              const SizedBox(height: PrivioSpacing.l),
              Text(s.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              Text(
                L.t.membersCount(s.memberCount),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((s.groupDescription ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.m),
                  child: Text(s.groupDescription!, textAlign: TextAlign.center),
                ),
              if (s.canEditInfo)
                Center(
                  child: TextButton.icon(
                    key: const Key('group.edit'),
                    onPressed: () => _editInfo(context, ref, s),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(L.t.modifierNomOuDescription),
                  ),
                ),
            ],
          ),
          SettingsSectionTitle(L.t.discussion),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('group.ttl'),
                leading: Icon(Icons.timer_outlined, color: p.accentText),
                title: Text(L.t.dureeMessages),
                subtitle: Text(formatTtl(s.ttlSeconds)),
                trailing: s.canEditInfo ? const Icon(Icons.chevron_right) : null,
                onTap: s.canEditInfo ? () => _ttl(context, ref, s) : null,
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('group.mute'),
                leading: Icon(
                  s.isMuted(now) ? Icons.notifications_off_outlined : Icons.notifications_outlined,
                  color: p.accentText,
                ),
                title: Text(L.t.sourdine),
                subtitle: Text(
                  s.isMuted(now) ? L.t.notificationsCoupees : L.t.notificationsActives,
                ),
                onTap: () => _mute(context, ref, s),
              ),
              // Lot 7.2c2 : notifié seulement quand on vous @mentionne.
              const SettingsDivider(),
              MentionsOnlyTile(conversationId: s.id),
              const SettingsDivider(),
              ListTile(
                key: const Key('group.clear'),
                leading: Icon(Icons.cleaning_services_outlined, color: p.accentText),
                title: Text(L.t.viderDiscussion),
                trailing: const Icon(Icons.chevron_right),
                // Lot 7.2a : le choix s'ouvre ici, on reste sur la fiche.
                onTap: () => chooseClear(context, ref, s),
              ),
              // Lot 7.3a : fond d'écran propre à cette discussion.
              const SettingsDivider(),
              ListTile(
                key: const Key('fiche.wallpaper'),
                leading: Icon(Icons.wallpaper_outlined, color: p.accentText),
                title: Text(L.t.fondEcran),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WallpaperScreen(conversationId: s.id, title: s.title),
                  ),
                ),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.medias),
          SettingsCard(
            children: [
              ConversationMediaSection(conversationId: s.id, title: s.title),
              const SettingsDivider(),
              FavoritesRow(conversationId: s.id, title: s.title),
            ],
          ),
          SettingsSectionTitle(L.t.confidentialiteDansCeGroupe),
          SettingsCard(children: [ConversationPrivacySection(summary: s)]),
          // Groupe fermé par Privio (lot 5.3) : plus de réglage d'écriture ni d'invitation.
          if (admin) ...[
            SettingsSectionTitle(L.t.reglagesGroupe),
            SettingsCard(
              children: [
                SwitchListTile(
                  key: const Key('group.posting'),
                  value: s.posting == 'admins',
                  secondary: Icon(Icons.campaign_outlined, color: p.accentText),
                  title: Text(L.t.seulsAdministrateursEcrivent),
                  onChanged: (v) => _run(
                    context,
                    ref,
                    () => groupAction(
                      ref,
                      conversationId,
                      (api) => api.setGroupSettings(conversationId, posting: v ? 'admins' : 'all'),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SwitchListTile(
                  key: const Key('group.info_editing'),
                  value: s.infoEditing == 'admins',
                  secondary: Icon(Icons.edit_note, color: p.accentText),
                  title: Text(L.t.seulsAdministrateursModifientGroupe),
                  subtitle: Text(L.t.nomDescriptionPhotoDureeMessages),
                  onChanged: (v) => _run(
                    context,
                    ref,
                    () => groupAction(
                      ref,
                      conversationId,
                      (api) =>
                          api.setGroupSettings(conversationId, infoEditing: v ? 'admins' : 'all'),
                    ),
                  ),
                ),
                const SettingsDivider(),
                // Lot 7.1b : entrée par code — demande à accepter (par défaut) ou entrée directe.
                SwitchListTile(
                  key: const Key('group.join_approval'),
                  value: joinSettings?.approvalRequired ?? true,
                  secondary: Icon(Icons.how_to_reg_outlined, color: p.accentText),
                  title: Text(L.t.approuverNouveauxMembres),
                  subtitle: Text(
                    joinSettings?.approvalRequired ?? true
                        ? L.t.avecCodeOnEnvoieDemande
                        : L.t.avecCodeOnEntreDirectement,
                  ),
                  onChanged: joinSettings == null
                      ? null
                      : (v) => _run(context, ref, () async {
                          await ref
                              .read(messagingApiProvider)
                              .setGroupJoinApproval(conversationId, required: v);
                          ref.invalidate(groupJoinSettingsProvider(conversationId));
                        }),
                ),
              ],
            ),
          ],
          if (admin && requests.isNotEmpty) ...[
            SettingsSectionTitle(
              L.t.demandesPourRejoindreRequestscount(requests.length),
              key: const Key('group.join_requests'),
            ),
            SettingsCard(
              children: [
                for (final r in requests)
                  ListTile(
                    key: Key('join_request.${r.id}'),
                    leading: UserAvatar(name: r.displayName, seed: r.userId, radius: 20),
                    title: Text(r.displayName),
                    subtitle: Text(
                      [
                        if (r.handle != null) '@${r.handle}',
                        if (r.wasRemoved) L.t.dejaRetireGroupe,
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('join_request.${r.id}.decline'),
                          tooltip: L.t.refuser,
                          onPressed: () => _answerJoin(context, ref, r, approve: false),
                          icon: Icon(Icons.close_rounded, color: theme.colorScheme.error),
                        ),
                        IconButton.filled(
                          key: Key('join_request.${r.id}.approve'),
                          tooltip: L.t.accepter,
                          onPressed: () => _answerJoin(context, ref, r, approve: true),
                          // Couleur explicite : la ligne impose sinon la sienne à l'icône.
                          icon: Icon(Icons.check_rounded, color: theme.colorScheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.xs,
              PrivioSpacing.l,
              0,
              PrivioSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    L.t.membres,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (admin)
                  TextButton.icon(
                    key: const Key('group.invite'),
                    onPressed: () => context.push(Routes.groupInvite(conversationId)),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(L.t.inviter),
                  ),
              ],
            ),
          ),
          SettingsCard(
            children: [
              // Lot 5.5 : code et QR code seulement si la console autorise les liens.
              if (admin && ref.watch(appFeaturesProvider).groupInviteLinks) ...[
                ListTile(
                  key: const Key('group.code'),
                  leading: Icon(Icons.qr_code_2_rounded, color: p.accentText),
                  title: Text(L.t.inviterAvecCodeOuQr),
                  subtitle: Text(L.t.pourPersonnesQuiNeSont),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.groupCode(conversationId)),
                ),
                const SettingsDivider(),
              ],
              if (members.isLoading && !members.hasValue) const LinearProgressIndicator(),
              for (final m in [...active, ...invited])
                ListTile(
                  key: Key('member.${m.userId}'),
                  leading: UserAvatar(
                    name: m.displayName,
                    avatarPath: m.avatarPath,
                    seed: m.userId,
                    radius: 20,
                  ),
                  title: Text(m.userId == me ? L.t.nameYou(m.displayName) : m.displayName),
                  subtitle: m.handle == null ? null : Text('@${m.handle}'),
                  trailing: m.role == 'member'
                      ? null
                      : Text(
                          m.roleLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: m.invited ? theme.colorScheme.onSurfaceVariant : p.accentText,
                          ),
                        ),
                  // Lot 8.1a : la carte de la personne ; les administrateurs y retrouvent
                  // « Gérer ce membre ».
                  onTap: m.invited
                      ? null
                      : () => openPerson(
                          context,
                          ref,
                          userId: m.userId,
                          name: m.displayName,
                          handle: m.handle,
                          avatarPath: m.avatarPath,
                          groupId: conversationId,
                          onManage: s.isAdmin && m.userId != me && m.role != 'owner'
                              ? () => _memberActions(context, ref, s, m)
                              : null,
                        ),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xl),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('group.report'),
                leading: Icon(Icons.flag_outlined, color: theme.colorScheme.error),
                title: Text(
                  L.t.signalerGroupe,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                ),
                onTap: () => showReportSheet(
                  context,
                  reportedUserId: null,
                  reportedName: L.t.groupeTitle(s.title),
                  conversationId: conversationId,
                ),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('group.leave'),
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                // Lot 7.2b1 : quitter retire aussi le groupe de votre liste.
                title: Text(L.t.quitterSupprimer, style: TextStyle(color: theme.colorScheme.error)),
                subtitle: Text(L.t.groupeDisparaitVotreListe),
                onTap: () => _leave(context, ref, s),
              ),
              // Lot 7.2b1 : le créateur et les administrateurs le suppriment pour tous.
              if (admin) ...[
                const SettingsDivider(),
                ListTile(
                  key: const Key('group.delete'),
                  leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                  title: Text(
                    L.t.supprimerGroupePourTous,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => chooseDelete(context, ref, s),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// « Quitter et supprimer » un groupe (fiche, ou appui long dans la liste ; lot 7.2c1).
/// Vrai si la personne a quitté le groupe.
Future<bool> confirmLeaveGroup(BuildContext context, WidgetRef ref, ConversationSummary s) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L.t.quitterTitle(s.title)),
      content: Text(
        s.isOwner ? L.t.groupeSeraConfieAdministrateurOu : L.t.vousNeVerrezPlusMessages,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('group.leave.confirm'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.t.quitter),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await groupAction(ref, s.id, (api) => api.leaveGroup(s.id));
    return true;
  } on Object catch (e) {
    if (context.mounted) _toast(context, toAppFailure(e).message);
    return false;
  }
}
