import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/feedback_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/success_snack.dart';
import 'new_conversation_screen.dart' show ConnectionRequestSheet;
import 'report_sheet.dart';

/// Lot 8.1a : toucher le nom ou la photo d'une personne.
/// - moi : « Ma fiche » ;
/// - une personne avec qui j'ai une discussion à deux : sa fiche ;
/// - sinon (membre d'un groupe, QR code) : sa carte, en feuille.
/// [onManage] : actions d'administrateur du groupe (la carte s'ouvre toujours, pour les
/// garder accessibles).
Future<void> openPerson(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  String? name,
  String? handle,
  String? avatarPath,
  String? groupId,
  VoidCallback? onManage,
}) async {
  final me = ref.read(currentUserIdProvider);
  if (userId == me) {
    unawaited(context.push(Routes.myProfile));
    return;
  }
  if (onManage == null) {
    final direct = ref
        .read(conversationsProvider)
        .value
        ?.where((c) => !c.isGroup && c.peerId == userId)
        .firstOrNull;
    if (direct != null) {
      unawaited(context.push(Routes.contact(direct.id)));
      return;
    }
  }
  final action = await showModalBottomSheet<PersonCardAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PersonCard(
      userId: userId,
      name: name,
      handle: handle,
      avatarPath: avatarPath,
      groupId: groupId,
      canManage: onManage != null,
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case PersonOpenChat(:final conversationId):
      ref.invalidate(conversationsProvider);
      unawaited(context.push(Routes.chat(conversationId)));
    case PersonManage():
      onManage?.call();
  }
}

sealed class PersonCardAction {
  const PersonCardAction();
}

class PersonOpenChat extends PersonCardAction {
  const PersonOpenChat(this.conversationId);
  final String conversationId;
}

class PersonManage extends PersonCardAction {
  const PersonManage();
}

/// Carte d'une personne : photo et nom en grand, identifiant, « À propos » (selon ses
/// réglages), groupes en commun, écrire ou envoyer une demande, bloquer, signaler.
class PersonCard extends ConsumerStatefulWidget {
  const PersonCard({
    super.key,
    required this.userId,
    this.name,
    this.handle,
    this.avatarPath,
    this.groupId,
    this.canManage = false,
  });

  final String userId;
  final String? name;
  final String? handle;
  final String? avatarPath;
  final String? groupId;
  final bool canManage;

  @override
  ConsumerState<PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends ConsumerState<PersonCard> {
  ContactProfile? _profile;
  List<CommonGroup> _groups = const [];
  ConnectionStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  String get _name =>
      _profile?.displayName.isNotEmpty == true ? _profile!.displayName : (widget.name ?? 'Membre');
  String? get _handle => _profile?.handle ?? widget.handle;

  FoundUser get _user => FoundUser(
    id: widget.userId,
    handle: _handle ?? '',
    displayName: _name,
    avatarPath: _profile?.avatarPath ?? widget.avatarPath,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = ref.read(messagingApiProvider);
    Future<T?> soft<T>(Future<T> Function() f) async {
      try {
        return await f();
      } on Object {
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      soft<ContactProfile?>(() => api.getContactProfile(widget.userId)),
      soft<List<CommonGroup>>(() => api.listCommonGroups(widget.userId)),
      soft<ConnectionStatus>(() => api.connectionStatus(widget.userId)),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as ContactProfile?;
      _groups = (results[1] as List<CommonGroup>?) ?? const [];
      _status = results[2] as ConnectionStatus?;
      _loading = false;
    });
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await ref.read(messagingApiProvider).connectionStatus(widget.userId);
      if (mounted) setState(() => _status = s);
    } on Object catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write() => _run(() async {
    final existing = _status?.conversationId;
    if (existing != null) {
      Navigator.pop(context, PersonOpenChat(existing));
      return;
    }
    final r = await ref.read(messagingApiProvider).sendConnectionRequest(widget.userId);
    if (!mounted) return;
    if (r.connected && r.conversationId != null) {
      Navigator.pop(context, PersonOpenChat(r.conversationId!));
      return;
    }
    await _refreshStatus();
  });

  Future<void> _request() async {
    final note = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConnectionRequestSheet(user: _user),
    );
    if (note == null || !mounted) return;
    await _run(() async {
      final r = await ref
          .read(messagingApiProvider)
          .sendConnectionRequest(widget.userId, note: note.isEmpty ? null : note);
      ref
        ..invalidate(conversationsProvider)
        ..invalidate(connectionRequestsProvider);
      if (!mounted) return;
      if (r.connected && r.conversationId != null) {
        Navigator.pop(context, PersonOpenChat(r.conversationId!));
        return;
      }
      await _refreshStatus();
      if (!mounted) return;
      ref.read(feedbackProvider).sound(PrivioSound.success);
      ScaffoldMessenger.of(context).showSnackBar(successSnack('Demande envoyée à $_name.'));
    });
  }

  Future<void> _cancel() => _run(() async {
    final id = _status?.requestId;
    if (id == null) return;
    await ref.read(messagingApiProvider).cancelConnectionRequest(id);
    ref.invalidate(connectionRequestsProvider);
    await _refreshStatus();
  });

  Future<void> _accept() => _run(() async {
    final id = _status?.requestId;
    if (id == null) return;
    final conv = await respondToConnection(ref, id, ConnectionAction.accept);
    if (conv != null && mounted) Navigator.pop(context, PersonOpenChat(conv));
  });

  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bloquer $_name ?'),
        content: const Text(
          'Vous ne pourrez plus vous écrire, dans un sens comme dans l’autre, et cette '
          'personne ne pourra plus vous trouver. Vous pourrez la débloquer à tout moment.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('card.block.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await setBlocked(ref, widget.userId, blocked: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('$_name est bloqué.')));
    });
  }

  Widget _action(ThemeData theme) {
    final st = _status?.state;
    switch (st) {
      case null:
        return const SizedBox.shrink();
      case LinkState.connected:
        return FilledButton.icon(
          key: const Key('card.write'),
          onPressed: _busy ? null : _write,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Envoyer un message'),
        );
      case LinkState.none:
        return FilledButton.icon(
          key: const Key('card.request'),
          onPressed: _busy || (_handle ?? '').isEmpty ? null : _request,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Envoyer une demande'),
        );
      case LinkState.incoming:
        return FilledButton(
          key: const Key('card.accept'),
          onPressed: _busy ? null : _accept,
          child: const Text('Accepter sa demande'),
        );
      case LinkState.outgoing:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Demande envoyée, en attente de réponse.',
                key: const Key('card.pending'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              key: const Key('card.cancel'),
              onPressed: _busy ? null : _cancel,
              child: const Text('Annuler'),
            ),
          ],
        );
      case LinkState.refused:
        final at = _status?.retryAt?.toLocal();
        final clock = at == null
            ? ''
            : ' à ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        return Text(
          '$_name a refusé votre demande. Nouvel essai possible$clock.',
          key: const Key('card.refused'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final about = _profile?.about;
    final error = theme.colorScheme.error;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('person.card'),
        padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: UserAvatar(
                key: const Key('card.avatar'),
                name: _name,
                avatarPath: _profile?.avatarPath ?? widget.avatarPath,
                seed: widget.userId,
                radius: 48,
              ),
            ),
            const SizedBox(height: PrivioSpacing.m),
            Text(
              _name,
              key: const Key('card.name'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if ((_handle ?? '').isNotEmpty)
              Text(
                '@$_handle',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: p.accentText),
              ),
            if (about != null && about.isNotEmpty) ...[
              const SizedBox(height: PrivioSpacing.m),
              Text(
                about,
                key: const Key('card.about'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: PrivioSpacing.l),
            if (_loading) const LinearProgressIndicator() else _action(theme),
            if (_message != null) ...[
              const SizedBox(height: PrivioSpacing.s),
              Text(
                _message!,
                key: const Key('card.message'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: error),
              ),
            ],
            if (_groups.isNotEmpty) ...[
              const SizedBox(height: PrivioSpacing.l),
              Text(
                '${_groups.length} groupe${_groups.length > 1 ? 's' : ''} en commun',
                style: theme.textTheme.labelLarge?.copyWith(color: p.accentText),
              ),
              for (final g in _groups.take(5))
                ListTile(
                  key: Key('card.group.${g.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(
                    name: g.title,
                    avatarPath: g.avatarPath,
                    seed: g.id,
                    icon: Icons.groups_rounded,
                    radius: 18,
                  ),
                  title: Text(g.title),
                  subtitle: Text('${g.memberCount} membre${g.memberCount > 1 ? 's' : ''}'),
                  onTap: () => Navigator.pop(context, PersonOpenChat(g.id)),
                ),
            ],
            const SizedBox(height: PrivioSpacing.s),
            const Divider(),
            if (widget.canManage)
              ListTile(
                key: const Key('card.manage'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.admin_panel_settings_outlined, color: p.accentText),
                title: const Text('Gérer ce membre'),
                subtitle: const Text('Administrateur, retrait du groupe'),
                onTap: () => Navigator.pop(context, const PersonManage()),
              ),
            ListTile(
              key: const Key('card.block'),
              contentPadding: EdgeInsets.zero,
              enabled: !_busy,
              leading: Icon(Icons.block, color: error),
              title: Text('Bloquer', style: TextStyle(color: error)),
              onTap: _block,
            ),
            ListTile(
              key: const Key('card.report'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined, color: error),
              title: Text('Signaler', style: TextStyle(color: error)),
              onTap: () => showReportSheet(
                context,
                reportedUserId: widget.userId,
                reportedName: _name,
                conversationId: widget.groupId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
