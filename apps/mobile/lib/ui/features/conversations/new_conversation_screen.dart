import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/handle/handle_rules.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../../core/theme/privio_palette.dart';
import '../../core/widgets/success_snack.dart';
import '../../../state/feedback_providers.dart';
import 'person_card.dart';
import '../groups/join_group_screen.dart';
import '../../../data/services/share_service.dart';
import '../../../state/session_controller.dart';

/// Écran 09 — trouver une personne par son identifiant Privio (ou son numéro, si elle
/// l'a autorisé). Recherche exacte uniquement, limitée côté serveur. Lot 4.7 : le premier
/// contact est une demande de connexion ; on écrit directement seulement si on est déjà
/// connectés.
class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _controller = TextEditingController();
  FoundUser? _found;
  ConnectionStatus? _status;
  String? _message;
  bool _busy = false;

  /// Lot 8.1c : personne introuvable (proposer de l'inviter).
  bool _notFound = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _found = null;
      _status = null;
      _message = null;
      _notFound = false;
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
      final status = user == null ? null : await api.connectionStatus(user.id);
      setState(() {
        _found = user;
        _status = status;
        _message = user == null ? L.t.aucunCompteTrouveVerifiezOrthographe : null;
        _notFound = user == null;
      });
    } on Object catch (e) {
      setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final handle = await ref.read(profileQrScannerProvider)(context);
    if (handle == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
      _notFound = false;
      _found = null;
    });
    try {
      final user = await ref.read(messagingApiProvider).findByHandle(handle);
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _message = L.t.aucunCompteTrouvePourHandle(handle);
          _notFound = true;
        });
        return;
      }
      setState(() => _busy = false);
      await openPerson(
        context,
        ref,
        userId: user.id,
        name: user.displayName,
        handle: user.handle,
        avatarPath: user.avatarPath,
      );
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ouvre la discussion (déjà connectés), sinon envoie la demande avec le mot.
  Future<void> _send(FoundUser user, {String? note}) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(messagingApiProvider);
      final existing = _status?.conversationId;
      if (existing != null) {
        if (mounted) context.pushReplacement(Routes.chat(existing));
        return;
      }
      final result = await api.sendConnectionRequest(user.id, note: note);
      ref
        ..invalidate(conversationsProvider)
        ..invalidate(connectionRequestsProvider);
      if (result.connected && result.conversationId != null) {
        if (mounted) context.pushReplacement(Routes.chat(result.conversationId!));
        return;
      }
      final status = await api.connectionStatus(user.id);
      if (!mounted) return;
      setState(() => _status = status);
      ref.read(feedbackProvider).sound(PrivioSound.success);
      ScaffoldMessenger.of(context)
          .showSnackBar(successSnack(L.t.demandeEnvoyeeDisplayname(user.displayName)));
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(FoundUser user) async {
    final note = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ConnectionRequestSheet(user: user),
    );
    if (note == null || !mounted) return;
    await _send(user, note: note.isEmpty ? null : note);
  }

  Future<void> _cancel(FoundUser user) async {
    final id = _status?.requestId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(messagingApiProvider);
      await api.cancelConnectionRequest(id);
      ref.invalidate(connectionRequestsProvider);
      final status = await api.connectionStatus(user.id);
      if (mounted) setState(() => _status = status);
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(FoundUser user) async {
    final id = _status?.requestId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final conv = await respondToConnection(ref, id, ConnectionAction.accept);
      if (conv != null && mounted) context.pushReplacement(Routes.chat(conv));
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bouton (ou état) selon la relation avec la personne trouvée.
  Widget _action(FoundUser user, ThemeData theme) {
    final st = _status?.state ?? LinkState.none;
    switch (st) {
      case LinkState.connected:
        return FilledButton(
          key: const Key('search.write'),
          onPressed: _busy ? null : () => _send(user),
          child: Text(L.t.ecrire),
        );
      case LinkState.none:
        return FilledButton.icon(
          key: const Key('search.request'),
          onPressed: _busy ? null : () => _request(user),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(L.t.envoyerDemande2),
        );
      case LinkState.incoming:
        return FilledButton(
          key: const Key('search.accept'),
          onPressed: _busy ? null : () => _accept(user),
          child: Text(L.t.accepterSaDemande),
        );
      case LinkState.outgoing:
        return Row(
          children: [
            Expanded(
              child: Text(
                L.t.demandeEnvoyeeAttenteReponse,
                key: const Key('search.pending'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              key: const Key('search.cancel'),
              onPressed: _busy ? null : () => _cancel(user),
              child: Text(L.t.annuler),
            ),
          ],
        );
      case LinkState.refused:
        final at = _status?.retryAt?.toLocal();
        final clock = at == null
            ? ''
            : L.t.atTime(
                '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
              );
        return Text(
          L.t.displaynameRefuseVotreDemandeNouvel(user.displayName, clock),
          key: const Key('search.refused'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(
        title: Text(L.t.nouvelleDiscussion),
        actions: [
          // Lot 8.1a : QR code d'un identifiant Privio → carte de la personne.
          IconButton(
            key: const Key('search.scan'),
            tooltip: L.t.scannerQrCode,
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: FlowLayout(
        children: [
          TextField(
            key: const Key('search.input'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _busy ? null : _search(),
            decoration: InputDecoration(
              labelText: L.t.identifiantOuNumero,
              hintText: L.t.identifiantOu700000,
              helperText: L.t.identifiantExactExAwaOu,
              suffixIcon: IconButton(
                key: const Key('search.submit'),
                tooltip: L.t.rechercher,
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Text(_message!, key: const Key('search.message'), style: theme.textTheme.bodyMedium),
          // Lot 8.1c : personne introuvable : l'inviter (partage de mon identifiant).
          if (_message != null && _notFound)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('search.invite'),
                onPressed: () => ref.read(shareTextProvider)(
                  inviteText(ref.read(sessionControllerProvider).value?.account?.profile?.handle),
                ),
                icon: const Icon(Icons.share_outlined),
                label: Text(L.t.inviterCettePersonneSurPrivio),
              ),
            ),
          if (found != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      key: const Key('search.result'),
                      leading: UserAvatar(
                        name: found.displayName,
                        avatarPath: found.avatarPath,
                        seed: found.id,
                      ),
                      title: Text(found.displayName),
                      subtitle: Text('@${found.handle}'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                      child: _action(found, theme),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: PrivioSpacing.l),
          Center(
            child: TextButton.icon(
              key: const Key('search.requests'),
              onPressed: () => context.push(Routes.requests),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(L.t.mesDemandesConnexion),
            ),
          ),
        ],
      ),
    );
  }
}

/// Envoi d'une demande : petit mot facultatif (140 caractères), puis « Envoyer ».
class ConnectionRequestSheet extends StatefulWidget {
  const ConnectionRequestSheet({super.key, required this.user});

  final FoundUser user;

  static const maxNote = 140;

  @override
  State<ConnectionRequestSheet> createState() => _ConnectionRequestSheetState();
}

class _ConnectionRequestSheetState extends State<ConnectionRequestSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xl,
            0,
            PrivioSpacing.xl,
            PrivioSpacing.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.t.demandeDisplayname(widget.user.displayName),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                L.t.vousPourrezVousEcrireQuand(widget.user.displayName),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.m),
              TextField(
                key: const Key('request.note'),
                controller: _note,
                maxLength: ConnectionRequestSheet.maxNote,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: L.t.petitMotFacultatif,
                  hintText: L.t.bonjourCEst,
                  helperText: L.t.efface5MinApresAcceptation,
                ),
              ),
              const SizedBox(height: PrivioSpacing.m),
              FilledButton(
                key: const Key('request.send'),
                onPressed: () => Navigator.pop(context, _note.text.trim()),
                child: Text(L.t.envoyerDemande),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
