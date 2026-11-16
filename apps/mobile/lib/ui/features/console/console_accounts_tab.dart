import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/console_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../../domain/models/console.dart';
import '../../core/widgets/settings_card.dart';
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
  int _page = 1;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    setState(() => _submitted = q.isEmpty ? null : q);
  }

  void _clear() {
    _query.clear();
    setState(() => _submitted = null);
  }

  Widget _row(AccountHit a) => _AccountRow(a: a, onTap: () => setState(() => _open = a.userId));

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return AccountView(userId: open, onBack: () => setState(() => _open = null));
    }
    final q = _submitted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.m,
            PrivioSpacing.m,
            PrivioSpacing.m,
            PrivioSpacing.s,
          ),
          child: TextField(
            key: const Key('accounts.query'),
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '@identifiant, nom ou numéro complet',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (q != null)
                    IconButton(
                      key: const Key('accounts.clear'),
                      tooltip: 'Revenir à la liste',
                      icon: const Icon(Icons.close),
                      onPressed: _clear,
                    ),
                  IconButton(
                    key: const Key('accounts.search'),
                    tooltip: 'Rechercher',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _search,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: q != null
              ? switch (ref.watch(accountSearchProvider(q))) {
                  AsyncData(:final value) when value.isEmpty => const EmptyView(
                    icon: Icons.person_search_outlined,
                    title: 'Aucun compte trouvé',
                    message: 'Vérifiez l’identifiant, le nom ou le numéro complet.',
                  ),
                  AsyncData(:final value) => ListView(
                    key: const Key('accounts.results'),
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.m,
                      0,
                      PrivioSpacing.m,
                      PrivioSpacing.xl,
                    ),
                    children: [
                      SettingsCard(
                        children: [
                          for (final (i, a) in value.indexed) ...[
                            if (i > 0) const SettingsDivider(),
                            _row(a),
                          ],
                        ],
                      ),
                    ],
                  ),
                  AsyncError(:final error) => ErrorView(
                    message: toAppFailure(error).message,
                    onRetry: () => ref.invalidate(accountSearchProvider(q)),
                  ),
                  _ => const LoadingView(),
                }
              // Lot 5.5 : tous les comptes, A–Z, pages numérotées, lettres à droite.
              : switch (ref.watch(consoleAccountsPageProvider(_page))) {
                  AsyncData(:final value) => _AlphabetList(
                    page: value,
                    row: _row,
                    onPage: (p) => setState(() => _page = p),
                  ),
                  AsyncError(:final error) => ErrorView(
                    message: toAppFailure(error).message,
                    onRetry: () => ref.invalidate(consoleAccountsPageProvider(_page)),
                  ),
                  _ => const LoadingView(),
                },
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.a, required this.onTap});

  final AccountHit a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const blue = Color(0xFF2A73C9);
    final initial = a.displayName.trim().isEmpty ? '?' : a.displayName.trim()[0].toUpperCase();
    return ListTile(
      key: Key('account.${a.userId}'),
      leading: CircleAvatar(
        backgroundColor: (a.deleted || a.suspended ? theme.colorScheme.error : blue).withValues(
          alpha: 0.14,
        ),
        foregroundColor: a.deleted || a.suspended ? theme.colorScheme.error : blue,
        child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(a.displayName.isEmpty ? '@${a.handle}' : a.displayName),
      subtitle: Text(
        ['@${a.handle}', if (a.deleted) 'compte supprimé', if (a.suspended) 'suspendu'].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Lot 5.5 : liste A–Z d'une page, index des lettres à droite, pages numérotées en bas.
class _AlphabetList extends StatelessWidget {
  const _AlphabetList({required this.page, required this.row, required this.onPage});

  final ConsolePage<AccountHit> page;
  final Widget Function(AccountHit) row;
  final ValueChanged<int> onPage;

  static const _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const blue = Color(0xFF2A73C9);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${page.total} comptes · page ${page.page} sur ${page.pages}',
              key: const Key('accounts.count'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  key: const Key('accounts.list'),
                  padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.s, 0, 16),
                  children: [
                    if (page.rows.isEmpty)
                      const EmptyView(
                        icon: Icons.people_outline,
                        title: 'Aucun compte',
                        message: 'Les comptes créés apparaîtront ici.',
                      )
                    else
                      SettingsCard(
                        children: [
                          for (final (i, a) in page.rows.indexed) ...[
                            if (i > 0) const SettingsDivider(),
                            row(a),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              // Index A–Z : toucher une lettre ouvre la page où elle commence.
              SizedBox(
                width: 28,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = (c.maxHeight / _letters.length).clamp(10.0, 22.0);
                    return Column(
                      key: const Key('accounts.index'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final l in _letters)
                          SizedBox(
                            height: h,
                            child: InkWell(
                              key: Key('accounts.letter.$l'),
                              onTap: page.pageOf(l) == null ? null : () => onPage(page.pageOf(l)!),
                              child: Center(
                                child: Text(
                                  l,
                                  style: TextStyle(
                                    fontSize: (h * 0.62).clamp(8.0, 12.0),
                                    fontWeight: FontWeight.w700,
                                    color: page.pageOf(l) == null
                                        ? theme.colorScheme.outlineVariant
                                        : blue,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ConsolePager(page: page.page, pages: page.pages, onPage: onPage, color: blue),
      ],
    );
  }
}

/// Lot 5.5 : pages numérotées ‹ 1 2 3 … › (comptes, journal).
class ConsolePager extends StatelessWidget {
  const ConsolePager({
    super.key,
    required this.page,
    required this.pages,
    required this.onPage,
    required this.color,
  });

  final int page;
  final int pages;
  final ValueChanged<int> onPage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) return const SizedBox(height: PrivioSpacing.s);
    // Au plus 5 numéros autour de la page courante.
    final start = (page - 2).clamp(1, (pages - 4).clamp(1, pages));
    final end = (start + 4).clamp(1, pages);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
        child: Row(
          key: const Key('pager'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('pager.previous'),
              tooltip: 'Page précédente',
              onPressed: page > 1 ? () => onPage(page - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            for (var p = start; p <= end; p++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  key: Key('pager.$p'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: p == page ? null : () => onPage(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p == page ? color : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$p',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p == page ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              key: const Key('pager.next'),
              tooltip: 'Page suivante',
              onPressed: page < pages ? () => onPage(page + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
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
        case 'two_step_reset':
          await admin.resetTwoStep(a.userId, r.$1);
          ref.invalidate(consoleTwoStepProvider(a.userId));
        default:
          await admin.disconnectDevice(a.userId, r.$1);
      }
      _refresh();
      refreshModeration(ref);
      _toast(switch (action) {
        'warn' => 'Avertissement envoyé.',
        'suspend' => 'Compte suspendu.',
        'lift' => 'Compte réactivé.',
        'two_step_reset' => 'Vérification en deux étapes réinitialisée.',
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
              // Lot 8.4a : vérification en deux étapes (et demande « code oublié »).
              if (ref.watch(consoleTwoStepProvider(a.userId)).value case final ts?)
                line(
                  'Deux étapes',
                  !ts.enabled
                      ? 'Désactivée'
                      : ts.resetRequestedAt == null
                      ? 'Activée'
                      : 'Activée · code oublié, demande du ${_time(ts.resetRequestedAt!)}',
                  key: const Key('account.two_step'),
                ),
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
                if (ref.watch(consoleTwoStepProvider(a.userId)).value?.enabled ?? false)
                  OutlinedButton.icon(
                    key: const Key('account.two_step_reset'),
                    onPressed: _busy ? null : () => _act(a, 'two_step_reset'),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Réinitialiser les deux étapes'),
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
