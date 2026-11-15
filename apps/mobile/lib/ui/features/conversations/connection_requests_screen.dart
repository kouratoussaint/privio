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
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/success_snack.dart';
import '../../../state/feedback_providers.dart';
import 'impersonation.dart';

/// Demandes de connexion (lot 4.7) : reçues (accepter, refuser, bloquer) et envoyées
/// (en attente, refusées, expirées).
class ConnectionRequestsScreen extends ConsumerWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(connectionRequestsProvider);
    return Scaffold(
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: Text(L.t.demandesConnexion)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: toAppFailure(e).message,
          onRetry: () => ref.invalidate(connectionRequestsProvider),
        ),
        data: (all) {
          final incoming = [
            for (final r in all)
              if (r.incoming && r.pending) r,
          ];
          final outgoing = [
            for (final r in all)
              if (!r.incoming) r,
          ];
          if (incoming.isEmpty && outgoing.isEmpty) {
            return EmptyView(
              icon: Icons.person_add_alt_1_outlined,
              title: L.t.aucuneDemande,
              message: L.t.pourEcrireQuelquPourPremiere,
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
            children: [
              if (incoming.isNotEmpty) ...[
                _Header(L.t.recues),
                for (final r in incoming) _IncomingTile(request: r),
              ],
              if (outgoing.isNotEmpty) ...[
                _Header(L.t.envoyees),
                for (final r in outgoing) _OutgoingTile(request: r),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Temps restant : « expire dans 23 h », « expire dans 12 min ».
String _expiresIn(DateTime at) {
  final left = at.difference(DateTime.now());
  if (left.inMinutes < 1) return L.t.expireBientot;
  if (left.inHours < 1) return L.t.expireDansInminutesMin(left.inMinutes);
  return L.t.expireDansInhoursH(left.inHours);
}

String _clock(DateTime at) {
  final l = at.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class _IncomingTile extends ConsumerStatefulWidget {
  const _IncomingTile({required this.request});

  final ConnectionRequest request;

  @override
  ConsumerState<_IncomingTile> createState() => _IncomingTileState();
}

class _IncomingTileState extends ConsumerState<_IncomingTile> {
  bool _busy = false;

  Future<void> _act(ConnectionAction action) async {
    final r = widget.request;
    if (action == ConnectionAction.block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L.t.bloquerDisplayname(r.displayName)),
          content: Text(L.t.demandeEstRefuseeCettePersonne),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
            FilledButton(
              key: const Key('request.block.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t.bloquer),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final conv = await respondToConnection(ref, r.id, action);
      final done = switch (action) {
        ConnectionAction.accept => L.t.vousEtesConnecteAvecDisplayname(r.displayName),
        ConnectionAction.refuse => L.t.demandeRefusee,
        ConnectionAction.block => L.t.displaynameEstBloque(r.displayName),
      };
      if (action == ConnectionAction.accept) {
        ref.read(feedbackProvider).sound(PrivioSound.success);
        messenger.showSnackBar(successSnack(done));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
      if (conv != null) unawaited(router.push(Routes.chat(conv)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Card(
      key: Key('request.${r.id}'),
      margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l, vertical: PrivioSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: r.displayName, avatarPath: r.avatarPath, seed: r.userId),
                const SizedBox(width: PrivioSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.displayName, style: theme.textTheme.titleMedium),
                      Text(
                        '@${r.handle} · ${_expiresIn(r.expiresAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('request.${r.id}.menu'),
                  tooltip: L.t.plusOptions,
                  enabled: !_busy,
                  onSelected: (_) => _act(ConnectionAction.block),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: const Key('request.block'),
                      value: 'block',
                      child: Text(L.t.bloquer),
                    ),
                  ],
                ),
              ],
            ),
            // Lot 8.4c : nom identique ou très proche de celui d'un de mes contacts.
            ImpersonationWarning(userId: r.userId, name: r.displayName, handle: r.handle),
            if (r.note != null) ...[
              const SizedBox(height: PrivioSpacing.s),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(PrivioSpacing.m),
                decoration: BoxDecoration(
                  color: p.notice,
                  borderRadius: BorderRadius.circular(PrivioRadius.medium),
                ),
                child: Text(r.note!, key: Key('request.${r.id}.note')),
              ),
            ],
            const SizedBox(height: PrivioSpacing.m),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('request.${r.id}.refuse'),
                    onPressed: _busy ? null : () => _act(ConnectionAction.refuse),
                    child: Text(L.t.refuser),
                  ),
                ),
                const SizedBox(width: PrivioSpacing.m),
                Expanded(
                  child: FilledButton(
                    key: Key('request.${r.id}.accept'),
                    onPressed: _busy ? null : () => _act(ConnectionAction.accept),
                    child: Text(L.t.accepter),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutgoingTile extends ConsumerWidget {
  const _OutgoingTile({required this.request});

  final ConnectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final theme = Theme.of(context);
    final (status, color) = switch (r.status) {
      'refused' => (
        r.retryAt != null && r.retryAt!.isAfter(DateTime.now())
            ? L.t.refuseVotreDemandeNouvelEssai(_clock(r.retryAt!))
            : L.t.refuseVotreDemande,
        theme.colorScheme.error,
      ),
      'expired' => (L.t.demandeExpireeSansReponse, theme.colorScheme.onSurfaceVariant),
      _ => (L.t.attenteExpiresat(_expiresIn(r.expiresAt)), theme.colorScheme.onSurfaceVariant),
    };
    return ListTile(
      key: Key('request.${r.id}'),
      leading: UserAvatar(name: r.displayName, avatarPath: r.avatarPath, seed: r.userId),
      title: Text(r.displayName),
      subtitle: Text(
        status,
        key: Key('request.${r.id}.status'),
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
      trailing: r.pending
          ? TextButton(
              key: Key('request.${r.id}.cancel'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(messagingApiProvider).cancelConnectionRequest(r.id);
                  messenger.showSnackBar(SnackBar(content: Text(L.t.demandeAnnulee)));
                } on Object catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
                } finally {
                  ref.invalidate(connectionRequestsProvider);
                }
              },
              child: Text(L.t.annuler),
            )
          : null,
    );
  }
}

/// Encart en tête de la liste des discussions : demandes reçues ou envoyées en cours.
class ConnectionRequestsBanner extends ConsumerWidget {
  const ConnectionRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(connectionRequestsProvider).value ?? const [];
    final incoming = all.where((r) => r.incoming && r.pending).length;
    final refused = all.where((r) => !r.incoming && r.status == 'refused').length;
    if (incoming == 0 && refused == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final label = incoming > 0
        ? (incoming == 1 ? L.t.n1DemandeConnexion : L.t.incomingDemandesConnexion(incoming))
        : (refused == 1 ? L.t.n1DemandeRefusee : L.t.refusedDemandesRefusees(refused));
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, PrivioSpacing.xs, PrivioSpacing.l, 0),
      child: Material(
        color: p.notice,
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        child: InkWell(
          key: const Key('requests.banner'),
          borderRadius: BorderRadius.circular(PrivioRadius.medium),
          onTap: () => context.push(Routes.requests),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PrivioSpacing.m,
              vertical: PrivioSpacing.m,
            ),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1_outlined, color: p.accentText),
                const SizedBox(width: PrivioSpacing.m),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (incoming > 0) Badge(label: Text('$incoming'), backgroundColor: p.accentText),
                const SizedBox(width: PrivioSpacing.s),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
