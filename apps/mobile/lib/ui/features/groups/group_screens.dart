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
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../../state/providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ttl_picker.dart';
import '../conversations/contact_screen.dart';
import '../conversations/report_sheet.dart';

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
        setState(() => _message = 'Aucun compte ne correspond.');
      } else if (widget.exclude.contains(user.id)) {
        setState(() => _message = '${user!.displayName} fait déjà partie du groupe.');
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
            hintText: 'Identifiant Privio (ex. awa_s) ou numéro',
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: IconButton(
              key: const Key('picker.submit'),
              tooltip: 'Ajouter',
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
          Text('Vos contacts', style: theme.textTheme.labelLarge),
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
            'Chaque personne reçoit une invitation et choisit de rejoindre le groupe ou non.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Confirmation après création (lot 4.8).
String createdGroupMessage(int invited) => switch (invited) {
  0 => 'Groupe créé',
  1 => 'Groupe créé · 1 invitation envoyée',
  _ => 'Groupe créé · $invited invitations envoyées',
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

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
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
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pushReplacement(Routes.chat(id));
      messenger.showSnackBar(
        SnackBar(key: const Key('group.created'), content: Text(createdGroupMessage(invited))),
      );
    } on Object catch (e) {
      if (mounted) _toast(context, toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nouveau groupe')),
    body: ListView(
      padding: const EdgeInsets.all(PrivioSpacing.xl),
      children: [
        TextField(
          key: const Key('group.title'),
          controller: _title,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom du groupe'),
        ),
        TextField(
          key: const Key('group.description'),
          controller: _description,
          maxLength: 300,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (facultative)'),
        ),
        const SizedBox(height: PrivioSpacing.l),
        Text('Inviter', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.s),
        MemberPicker(selected: _selected, onChanged: (s) => setState(() => _selected = s)),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          key: const Key('group.create'),
          onPressed: _busy ? null : _create,
          child: _busy
              ? const Row(
                  key: Key('group.creating'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: PrivioSpacing.m),
                    Flexible(child: Text('Création du groupe…')),
                  ],
                )
              : Text(
                  _selected.isEmpty
                      ? 'Créer le groupe'
                      : 'Créer et inviter ${_selected.length} personne${_selected.length > 1 ? 's' : ''}',
                ),
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
      _toast(
        context,
        n == 0
            ? 'Aucune invitation envoyée (déjà membres ou invités).'
            : '$n invitation${n > 1 ? 's' : ''} envoyée${n > 1 ? 's' : ''}.',
      );
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
      appBar: AppBar(title: const Text('Inviter')),
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
            child: Text('Inviter ${_selected.length} personne${_selected.length > 1 ? 's' : ''}'),
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
        title: const Text('Modifier le groupe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('group.edit.title'),
              controller: title,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nom du groupe'),
            ),
            TextField(
              key: const Key('group.edit.description'),
              controller: description,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('group.edit.save'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
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
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              key: const Key('group.photo.gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (s.groupAvatarPath != null)
              ListTile(
                key: const Key('group.photo.remove'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: const Text('Retirer la photo'),
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(m.displayName), subtitle: Text(m.roleLabel)),
            if (m.role == 'member')
              ListTile(
                key: const Key('member.make_admin'),
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Nommer administrateur'),
                onTap: () => Navigator.pop(ctx, 'admin'),
              ),
            if (m.role == 'admin' && s.isOwner)
              ListTile(
                key: const Key('member.remove_admin'),
                leading: const Icon(Icons.remove_moderator_outlined),
                title: const Text('Retirer le rôle d’administrateur'),
                onTap: () => Navigator.pop(ctx, 'member'),
              ),
            if (s.isOwner)
              ListTile(
                key: const Key('member.transfer'),
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Nommer propriétaire'),
                onTap: () => Navigator.pop(ctx, 'transfer'),
              ),
            if (m.role == 'member' || (m.role == 'admin' && s.isOwner))
              ListTile(
                key: const Key('member.remove'),
                leading: Icon(Icons.person_remove_outlined, color: Theme.of(ctx).colorScheme.error),
                title: Text(
                  'Retirer du groupe',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'remove' || action == 'transfer') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            action == 'remove'
                ? 'Retirer ${m.displayName}\u202F?'
                : 'Confier le groupe à ${m.displayName}\u202F?',
          ),
          content: Text(
            action == 'remove'
                ? '${m.displayName} ne verra plus les messages du groupe.'
                : 'Vous resterez administrateur.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              key: const Key('member.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer'),
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
      title: 'Durée des messages',
      help: 'Pour les prochains messages du groupe.',
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
              ('8 heures', const Duration(hours: 8)),
              ('1 semaine', const Duration(days: 7)),
              ('Toujours', const Duration(days: 3650)),
            ])
              ListTile(
                key: Key('mute.${d.inHours}'),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, d),
              ),
            if (s.isMuted(now))
              ListTile(
                key: const Key('mute.off'),
                title: const Text('Réactiver les notifications'),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quitter «\u202F${s.title}\u202F»\u202F?'),
        content: Text(
          s.isOwner
              ? 'Le groupe sera confié à l’administrateur (ou au membre) le plus ancien. '
                    'Vous ne verrez plus ses messages.'
              : 'Vous ne verrez plus les messages de ce groupe.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('group.leave.confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await groupAction(ref, conversationId, (api) => api.leaveGroup(conversationId));
      if (context.mounted) context.go(Routes.groups);
    } on Object catch (e) {
      if (context.mounted) _toast(context, toAppFailure(e).message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final s = ref.watch(conversationSummaryProvider(conversationId));
    final members = ref.watch(groupMembersProvider(conversationId));
    final me = ref.watch(currentUserIdProvider);
    if (s == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final now = DateTime.now();
    final active = (members.value ?? const <GroupMember>[]).where((m) => !m.invited).toList();
    final invited = (members.value ?? const <GroupMember>[]).where((m) => m.invited).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Infos')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xl),
        children: [
          Center(
            child: Semantics(
              button: s.canEditInfo,
              label: s.canEditInfo ? 'Changer la photo du groupe' : 'Photo du groupe',
              child: InkWell(
                key: const Key('group.photo'),
                customBorder: const CircleBorder(),
                onTap: s.canEditInfo ? () => _editPhoto(context, ref, s) : null,
                child: UserAvatar(
                  name: s.title,
                  avatarPath: s.groupAvatarPath,
                  seed: s.id,
                  radius: 48,
                  icon: Icons.groups_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(s.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          Text(
            '${s.memberCount} membre${s.memberCount > 1 ? 's' : ''}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if ((s.groupDescription ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xl,
                PrivioSpacing.m,
                PrivioSpacing.xl,
                0,
              ),
              child: Text(s.groupDescription!, textAlign: TextAlign.center),
            ),
          if (s.canEditInfo)
            Center(
              child: TextButton.icon(
                key: const Key('group.edit'),
                onPressed: () => _editInfo(context, ref, s),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier le nom ou la description'),
              ),
            ),
          const Divider(height: PrivioSpacing.xxl),
          ListTile(
            key: const Key('group.ttl'),
            leading: Icon(Icons.timer_outlined, color: p.accentText),
            title: const Text('Durée des messages'),
            subtitle: Text(formatTtl(s.ttlSeconds)),
            trailing: s.canEditInfo ? const Icon(Icons.chevron_right) : null,
            onTap: s.canEditInfo ? () => _ttl(context, ref, s) : null,
          ),
          ListTile(
            key: const Key('group.mute'),
            leading: Icon(
              s.isMuted(now) ? Icons.notifications_off_outlined : Icons.notifications_outlined,
              color: p.accentText,
            ),
            title: const Text('Sourdine'),
            subtitle: Text(s.isMuted(now) ? 'Notifications coupées' : 'Notifications actives'),
            onTap: () => _mute(context, ref, s),
          ),
          // Groupe fermé par Privio (lot 5.3) : plus de réglage d'écriture ni d'invitation.
          if (s.isAdmin && !s.isClosed) ...[
            SwitchListTile(
              key: const Key('group.posting'),
              value: s.posting == 'admins',
              secondary: Icon(Icons.campaign_outlined, color: p.accentText),
              title: const Text('Seuls les administrateurs écrivent'),
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
            SwitchListTile(
              key: const Key('group.info_editing'),
              value: s.infoEditing == 'admins',
              secondary: Icon(Icons.edit_note, color: p.accentText),
              title: const Text('Seuls les administrateurs modifient le groupe'),
              subtitle: const Text('Nom, description, photo et durée des messages'),
              onChanged: (v) => _run(
                context,
                ref,
                () => groupAction(
                  ref,
                  conversationId,
                  (api) => api.setGroupSettings(conversationId, infoEditing: v ? 'admins' : 'all'),
                ),
              ),
            ),
          ],
          const Divider(height: PrivioSpacing.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Row(
              children: [
                Expanded(child: Text('Membres', style: theme.textTheme.titleMedium)),
                if (s.isAdmin && !s.isClosed)
                  TextButton.icon(
                    key: const Key('group.invite'),
                    onPressed: () => context.push(Routes.groupInvite(conversationId)),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Inviter'),
                  ),
              ],
            ),
          ),
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
              title: Text(m.userId == me ? '${m.displayName} (vous)' : m.displayName),
              subtitle: m.handle == null ? null : Text('@${m.handle}'),
              trailing: m.role == 'member'
                  ? null
                  : Text(
                      m.roleLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: m.invited ? theme.colorScheme.onSurfaceVariant : p.accentText,
                      ),
                    ),
              onTap: s.isAdmin && m.userId != me && !m.invited && m.role != 'owner'
                  ? () => _memberActions(context, ref, s, m)
                  : null,
            ),
          const Divider(height: PrivioSpacing.xxl),
          ListTile(
            key: const Key('group.report'),
            leading: Icon(Icons.flag_outlined, color: theme.colorScheme.error),
            title: const Text('Signaler le groupe'),
            onTap: () => showReportSheet(
              context,
              reportedUserId: null,
              reportedName: 'le groupe «\u202F${s.title}\u202F»',
              conversationId: conversationId,
            ),
          ),
          ListTile(
            key: const Key('group.leave'),
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Quitter le groupe', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _leave(context, ref, s),
          ),
        ],
      ),
    );
  }
}
