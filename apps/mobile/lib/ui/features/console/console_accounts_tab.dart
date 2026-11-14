import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/console_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../core/widgets/state_views.dart';
import 'console_reports_tab.dart';

/// Onglet « Comptes » de la console (lot 5.4) : recherche par @identifiant, nom ou numéro
/// complet (jamais affiché) ; fiche sans numéro, contact, discussion ni message.
class ConsoleAccountsTab extends ConsumerStatefulWidget {
  const ConsoleAccountsTab({super.key});

  @override
  ConsumerState<ConsoleAccountsTab> createState() => _ConsoleAccountsTabState();
}

class _ConsoleAccountsTabState extends ConsumerState<ConsoleAccountsTab> {
  final _query = TextEditingController();
  String? _submitted;
  String? _open;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _submitted = q);
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return AccountView(userId: open, onBack: () => setState(() => _open = null));
    }
    final theme = Theme.of(context);
    final q = _submitted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(PrivioSpacing.m),
          child: TextField(
            key: const Key('accounts.query'),
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '@identifiant, nom ou numéro complet',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                key: const Key('accounts.search'),
                tooltip: 'Rechercher',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
            ),
          ),
        ),
        Expanded(
          child: q == null
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.l),
                      child: Text(
                        'Le numéro n’est jamais affiché : il sert seulement à retrouver un '
                        'compte, s’il est saisi en entier. Chaque recherche est inscrite au journal.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                )
              : switch (ref.watch(accountSearchProvider(q))) {
                  AsyncData(:final value) when value.isEmpty => const EmptyView(
                    icon: Icons.person_search_outlined,
                    title: 'Aucun compte trouvé',
                    message: 'Vérifiez l’identifiant, le nom ou le numéro complet.',
                  ),
                  AsyncData(:final value) => ListView.separated(
                    key: const Key('accounts.results'),
                    itemCount: value.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = value[i];
                      return ListTile(
                        key: Key('account.${a.userId}'),
                        leading: const Icon(Icons.person_outline),
                        title: Text('@${a.handle}'),
                        subtitle: Text(
                          [
                            a.displayName,
                            if (a.deleted) 'compte supprimé',
                            if (a.suspended) 'suspendu',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _open = a.userId),
                      );
                    },
                  ),
                  AsyncError(:final error) => ErrorView(
                    message: toAppFailure(error).message,
                    onRetry: () => ref.invalidate(accountSearchProvider(q)),
                  ),
                  _ => const LoadingView(),
                },
        ),
      ],
    );
  }
}

String _day(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

String _time(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_day(t)} à ${two(l.hour)}:${two(l.minute)}';
}

/// Fiche d'un compte et ses actions.
class AccountView extends ConsumerStatefulWidget {
  const AccountView({super.key, required this.userId, required this.onBack});

  final String userId;
  final VoidCallback onBack;

  @override
  ConsumerState<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends ConsumerState<AccountView> {
  bool _busy = false;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refresh() {
    ref
      ..invalidate(consoleAccountProvider(widget.userId))
      ..invalidate(userSanctionsProvider(widget.userId))
      ..invalidate(consoleJournalProvider);
  }

  Future<void> _act(ConsoleAccount a, String action) async {
    final r = await showDialog<(String, int?, String?)>(
      context: context,
      builder: (_) => DecisionDialog(
        action: action,
        target: '@${a.handle} · ${a.displayName}',
        askReason: action == 'warn' || action == 'suspend',
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    final admin = ref.read(adminApiProvider);
    try {
      switch (action) {
        case 'warn' || 'suspend':
          await admin.sanctionUser(
            a.userId,
            action,
            reason: r.$3 ?? 'other',
            note: r.$1,
            days: r.$2,
          );
        case 'lift':
          await admin.liftSuspension(a.userId, r.$1);
        default:
          await admin.disconnectDevice(a.userId, r.$1);
      }
      _refresh();
      refreshModeration(ref);
      _toast(switch (action) {
        'warn' => 'Avertissement envoyé.',
        'suspend' => 'Compte suspendu.',
        'lift' => 'Compte réactivé.',
        _ => 'Téléphone déconnecté.',
      });
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(consoleAccountProvider(widget.userId));
    return switch (account) {
      AsyncData(:final value) => _body(context, value),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleAccountProvider(widget.userId)),
      ),
      _ => const LoadingView(),
    };
  }

  Widget _body(BuildContext context, ConsoleAccount a) {
    final theme = Theme.of(context);
    final sanctions = ref.watch(userSanctionsProvider(a.userId)).value ?? const <Sanction>[];
    Widget line(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(child: Text(value, key: key)),
        ],
      ),
    );
    return ListView(
      key: const Key('account.view'),
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
      children: [
        ListTile(
          key: const Key('account.back'),
          leading: const Icon(Icons.arrow_back),
          title: const Text('Retour à la recherche'),
          onTap: widget.onBack,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(path: a.avatarPath, name: a.displayName),
                  const SizedBox(width: PrivioSpacing.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${a.handle}', style: theme.textTheme.titleLarge),
                        Text(a.displayName),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.l),
              line(
                'État',
                a.deleted
                    ? 'Compte supprimé'
                    : a.suspended
                    ? (a.suspendedUntil == null
                          ? 'Suspendu sans limite'
                          : 'Suspendu jusqu’au ${_time(a.suspendedUntil!)}')
                    : 'Actif',
                key: const Key('account.state'),
              ),
              line('Inscription', _day(a.createdAt)),
              line('Dernier passage', a.lastSeenDay == null ? '—' : _day(a.lastSeenDay!)),
              line(
                'Téléphone',
                a.hasDevice
                    ? '${a.platform == 'ios' ? 'iPhone' : 'Android'} · version ${a.appVersion ?? '?'}'
                    : 'Aucun téléphone connecté',
                key: const Key('account.device'),
              ),
              if (a.hasDevice) line('Notifications', a.pushEnabled ? 'Activées' : 'Désactivées'),
              line('Discussions', '${a.directs} · groupes : ${a.groups}'),
              line(
                'Signalements (90 j)',
                'reçus : ${a.reportsReceived90d} · faits : ${a.reportsMade90d}',
              ),
              if (a.protected)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.s),
                  child: Text(
                    'Compte de l’administration : aucune action possible.',
                    key: const Key('account.protected'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        if (!a.protected && !a.deleted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Wrap(
              spacing: PrivioSpacing.s,
              runSpacing: PrivioSpacing.s,
              children: [
                FilledButton(
                  key: const Key('account.warn'),
                  onPressed: _busy ? null : () => _act(a, 'warn'),
                  child: const Text('Avertir'),
                ),
                if (a.suspended)
                  OutlinedButton.icon(
                    key: const Key('account.lift'),
                    onPressed: _busy ? null : () => _act(a, 'lift'),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Réactiver'),
                  )
                else
                  FilledButton(
                    key: const Key('account.suspend'),
                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                    onPressed: _busy ? null : () => _act(a, 'suspend'),
                    child: const Text('Suspendre…'),
                  ),
                if (a.hasDevice)
                  OutlinedButton.icon(
                    key: const Key('account.disconnect'),
                    onPressed: _busy ? null : () => _act(a, 'disconnect'),
                    icon: const Icon(Icons.phonelink_erase),
                    label: const Text('Déconnecter le téléphone'),
                  ),
              ],
            ),
          ),
        if (sanctions.isNotEmpty) ...[
          const SizedBox(height: PrivioSpacing.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text('Sanctions', style: theme.textTheme.titleSmall),
          ),
          for (final s in sanctions)
            ListTile(
              dense: true,
              leading: Icon(s.kind == 'warning' ? Icons.report_outlined : Icons.block),
              title: Text(
                '${s.kind == 'warning' ? 'Avertissement' : 'Suspension'} · '
                '${reasonLabel(s.reason).toLowerCase()}${s.liftedAt != null ? ' · levée' : ''}',
              ),
              subtitle: Text('Le ${_time(s.createdAt)}${s.note == null ? '' : ' · ${s.note}'}'),
            ),
        ],
        if (a.support.isNotEmpty) ...[
          const SizedBox(height: PrivioSpacing.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text('Demandes d’assistance', style: theme.textTheme.titleSmall),
          ),
          for (final r in a.support)
            ListTile(
              dense: true,
              leading: const Icon(Icons.support_agent),
              title: Text(r.details ?? ''),
              subtitle: Text(
                'Le ${_time(r.createdAt)} · ${r.answered ? 'répondue' : 'en attente'}',
              ),
            ),
        ],
      ],
    );
  }
}

/// Photo de profil (lisible par l'administration) ou initiale.
class _Avatar extends ConsumerWidget {
  const _Avatar({required this.path, required this.name});

  final String? path;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final p = path;
    if (p == null) return CircleAvatar(radius: 28, child: Text(initial));
    return FutureBuilder<Uint8List>(
      future: ref.read(messagingApiProvider).downloadAvatar(p),
      builder: (_, snap) => CircleAvatar(
        radius: 28,
        backgroundImage: snap.hasData ? MemoryImage(snap.data!) : null,
        child: snap.hasData ? null : Text(initial),
      ),
    );
  }
}
