import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/console_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../core/motion/motion.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import 'console_reports_tab.dart';
import 'console_screen.dart' show ConsoleBackHandler;

const _blue = Color(0xFF2A73C9);
const _green = Color(0xFF2E9D5B);
const _amber = Color(0xFFB7791F);
const _red = Color(0xFFD14343);
const _violet = Color(0xFF6B5BD2);

/// Onglet « Comptes » de la console (lot 5.4) : recherche par @identifiant, nom ou numéro.
/// Lot 5.5 : liste A–Z paginée. Lot 5.6 : numéro et photo (console seulement), filtres,
/// fiche repensée, identifiants réservés.
class ConsoleAccountsTab extends ConsumerStatefulWidget {
  const ConsoleAccountsTab({super.key});

  @override
  ConsumerState<ConsoleAccountsTab> createState() => _ConsoleAccountsTabState();
}

class _ConsoleAccountsTabState extends ConsumerState<ConsoleAccountsTab> with ConsoleBackHandler {
  @override
  bool handleBack() {
    if (_open == null && !_reserved) return false;
    setState(() {
      _open = null;
      _reserved = false;
    });
    return true;
  }

  final _query = TextEditingController();
  String? _submitted;
  String? _open;
  bool _reserved = false;
  String _filter = 'all';
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
    if (_reserved) {
      return ReservedHandlesView(onBack: () => setState(() => _reserved = false));
    }
    final q = _submitted;
    final page = q == null ? ref.watch(consoleAccountsPageProvider((_filter, _page))) : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.m,
            PrivioSpacing.m,
            PrivioSpacing.s,
            PrivioSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('accounts.query'),
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '@identifiant, nom ou numéro',
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
              IconButton(
                key: const Key('accounts.reserved'),
                tooltip: 'Identifiants réservés',
                icon: const Icon(Icons.alternate_email, color: _blue),
                onPressed: () => setState(() => _reserved = true),
              ),
            ],
          ),
        ),
        if (q == null)
          SizedBox(
            height: 48,
            child: ListView(
              key: const Key('accounts.filters'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m),
              children: [
                for (final e in kAccountFilters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: PrivioSpacing.s),
                    child: ChoiceChip(
                      key: Key('accounts.filter.${e.key}'),
                      label: Text(switch (page?.value?.counts[e.key]) {
                        final n? => '${e.value} · $n',
                        _ => e.value,
                      }),
                      selected: _filter == e.key,
                      selectedColor: _blue.withValues(alpha: 0.16),
                      checkmarkColor: _blue,
                      labelStyle: _filter == e.key
                          ? const TextStyle(color: _blue, fontWeight: FontWeight.w700)
                          : null,
                      onSelected: (_) => setState(() {
                        _filter = e.key;
                        _page = 1;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: q != null
              ? switch (ref.watch(accountSearchProvider(q))) {
                  AsyncData(:final value) when value.isEmpty => const EmptyView(
                    icon: Icons.person_search_outlined,
                    title: 'Aucun compte trouvé',
                    message: 'Vérifiez l’identifiant, le nom ou le numéro.',
                  ),
                  AsyncData(:final value) => ListView(
                    key: const Key('accounts.results'),
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.m,
                      PrivioSpacing.s,
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
              : switch (page!) {
                  AsyncData(:final value) => _AlphabetList(
                    page: value,
                    filtered: _filter != 'all',
                    row: _row,
                    onPage: (p) => setState(() => _page = p),
                  ),
                  AsyncError(:final error) => ErrorView(
                    message: toAppFailure(error).message,
                    onRetry: () => ref.invalidate(consoleAccountsPageProvider((_filter, _page))),
                  ),
                  _ => const LoadingView(),
                },
        ),
      ],
    );
  }
}

/// Numéro lisible (« +226 70 00 00 02 »), ou rien.
String? _phone(String? e164) => e164 == null ? null : PhoneNumber.format(e164);

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.a, required this.onTap});

  final AccountHit a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = _phone(a.phoneE164);
    final flagged = a.deleted || a.suspended;
    return ListTile(
      key: Key('account.${a.userId}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m, vertical: 2),
      leading: UserAvatar(
        name: a.displayName.isEmpty ? a.handle : a.displayName,
        seed: a.userId,
        avatarPath: a.avatarPath,
        radius: 22,
        ring: flagged ? theme.colorScheme.error : null,
      ),
      title: Text(
        a.displayName.isEmpty ? '@${a.handle}' : a.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              '@${a.handle}',
              if (a.deleted) 'compte supprimé',
              if (a.suspended) 'suspendu',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (phone != null)
            Text(
              phone,
              key: Key('account.phone.${a.userId}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Lot 5.5 : liste A–Z d'une page, index des lettres à droite, pages numérotées en bas.
class _AlphabetList extends StatelessWidget {
  const _AlphabetList({
    required this.page,
    required this.row,
    required this.onPage,
    this.filtered = false,
  });

  final ConsolePage<AccountHit> page;
  final Widget Function(AccountHit) row;
  final ValueChanged<int> onPage;
  final bool filtered;

  static const _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      EmptyView(
                        icon: Icons.people_outline,
                        title: 'Aucun compte',
                        message: filtered
                            ? 'Aucun compte ne correspond à ce filtre.'
                            : 'Les comptes créés apparaîtront ici.',
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
                                        : _blue,
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
        ConsolePager(page: page.page, pages: page.pages, onPage: onPage, color: _blue),
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

/// « Aujourd’hui », « Hier », « Il y a 5 j », puis la date.
String _ago(DateTime t, DateTime now) {
  final a = DateUtils.dateOnly(t.toLocal());
  final b = DateUtils.dateOnly(now.toLocal());
  final days = b.difference(a).inDays;
  if (days <= 0) return 'Aujourd’hui';
  if (days == 1) return 'Hier';
  if (days < 30) return 'Il y a $days j';
  return _day(t);
}

/// Fiche d'un compte (lot 5.6) : en-tête avec photo, état et numéro ; chiffres clés ;
/// téléphones ; actions en couleur ; historique.
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _refresh() {
    ref
      ..invalidate(consoleAccountProvider(widget.userId))
      ..invalidate(userSanctionsProvider(widget.userId))
      ..invalidate(consoleAccountsPageProvider)
      ..invalidate(consoleJournalProvider);
  }

  Future<void> _act(ConsoleAccount a, String action, {ConsoleDevice? device}) async {
    final r = await showDialog<(String, int?, String?)>(
      context: context,
      builder: (_) => DecisionDialog(
        action: action,
        target: device == null
            ? '@${a.handle} · ${a.displayName}'
            : '@${a.handle} · ${device.model ?? 'Android'}',
        askReason: action == 'warn' || action == 'suspend',
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    final admin = ref.read(adminApiProvider);
    try {
      String? done;
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
        case 'remove_avatar':
          await admin.removeAvatar(a.userId, r.$1);
        case 'reset_handle':
          final tmp = await admin.resetHandle(a.userId, r.$1);
          done = 'Identifiant remplacé par @$tmp. La personne en choisira un nouveau.';
        case 'disconnect_device':
          await admin.disconnectOneDevice(a.userId, device!.id, r.$1);
        default:
          await admin.disconnectDevice(a.userId, r.$1);
      }
      _refresh();
      refreshModeration(ref);
      _toast(
        done ??
            switch (action) {
              'warn' => 'Avertissement envoyé.',
              'suspend' => 'Compte suspendu.',
              'lift' => 'Compte réactivé.',
              'two_step_reset' => 'Vérification en deux étapes réinitialisée.',
              'remove_avatar' => 'Photo de profil retirée.',
              'disconnect_device' => 'Appareil déconnecté.',
              _ => 'Téléphone déconnecté.',
            },
      );
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
      AsyncData(:final value) => EntranceScope(child: _body(context, value)),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleAccountProvider(widget.userId)),
      ),
      _ => const LoadingView(),
    };
  }

  Widget _body(BuildContext context, ConsoleAccount a) {
    final sanctions = ref.watch(userSanctionsProvider(a.userId)).value ?? const <Sanction>[];
    final twoStep = ref.watch(consoleTwoStepProvider(a.userId)).value;
    final now = DateTime.now();
    // Anciennes réponses du serveur (sans liste) : le téléphone actif seul.
    final devices = a.devices.isNotEmpty
        ? a.devices
        : [
            if (a.hasDevice)
              ConsoleDevice(
                id: '',
                platform: a.platform!,
                appVersion: a.appVersion ?? '?',
                createdAt: a.deviceSince ?? a.createdAt,
                lastSeenAt: a.lastSeenAt ?? a.deviceSince ?? a.createdAt,
                push: a.pushEnabled,
              ),
          ];
    final canAct = !a.protected && !a.deleted;
    return ListView(
      key: const Key('account.view'),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.m,
        PrivioSpacing.xs,
        PrivioSpacing.m,
        PrivioSpacing.xxl,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('account.back'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour à la liste'),
          ),
        ),
        ...cascade([
          _Header(a: a, twoStep: twoStep?.enabled ?? a.twoStep, now: now),
          const SizedBox(height: PrivioSpacing.m),
          _Figures(a: a, now: now),
          const SizedBox(height: PrivioSpacing.m),
          _Section(
            title: 'Téléphones',
            child: SettingsCard(
              children: [
                if (devices.isEmpty)
                  const ListTile(
                    key: Key('account.device'),
                    leading: Icon(Icons.phonelink_off_outlined),
                    title: Text('Aucun téléphone connecté'),
                  )
                else
                  for (final (i, d) in devices.indexed) ...[
                    if (i > 0) const SettingsDivider(),
                    _DeviceTile(
                      d: d,
                      first: i == 0,
                      onDisconnect: canAct && d.active && d.id.isNotEmpty && !_busy
                          ? () => _act(a, 'disconnect_device', device: d)
                          : null,
                    ),
                  ],
              ],
            ),
          ),
          _Section(
            title: 'Compte',
            child: SettingsCard(
              children: [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Inscription',
                  value: _day(a.createdAt),
                ),
                const SettingsDivider(),
                _InfoRow(
                  icon: Icons.notifications_none,
                  label: 'Notifications',
                  value: devices.any((d) => d.active && d.push) ? 'Activées' : 'Désactivées',
                ),
                if (twoStep != null) ...[
                  const SettingsDivider(),
                  _InfoRow(
                    key: const Key('account.two_step'),
                    icon: Icons.verified_user_outlined,
                    label: 'Deux étapes',
                    value: !twoStep.enabled
                        ? 'Désactivée'
                        : twoStep.resetRequestedAt == null
                        ? 'Activée'
                        : 'Activée · code oublié, demande du ${_time(twoStep.resetRequestedAt!)}',
                  ),
                ],
              ],
            ),
          ),
          if (a.protected)
            Padding(
              padding: const EdgeInsets.only(top: PrivioSpacing.m),
              child: Text(
                'Compte de l’administration\u202F: aucune action possible.',
                key: const Key('account.protected'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (canAct)
            _Section(
              title: 'Actions',
              child: _ActionGrid(
                key: const Key('account.actions'),
                actions: [
                  const _Action(
                    'account.warn',
                    'Avertir',
                    Icons.warning_amber_rounded,
                    _amber,
                    'warn',
                  ),
                  if (a.suspended)
                    const _Action('account.lift', 'Réactiver', Icons.lock_open, _green, 'lift')
                  else
                    const _Action('account.suspend', 'Suspendre…', Icons.block, _red, 'suspend'),
                  if (a.hasDevice || devices.any((d) => d.active))
                    const _Action(
                      'account.disconnect',
                      'Déconnecter le téléphone',
                      Icons.phonelink_erase,
                      _blue,
                      'disconnect',
                    ),
                  if (twoStep?.enabled ?? false)
                    const _Action(
                      'account.two_step_reset',
                      'Réinitialiser les deux étapes',
                      Icons.lock_reset,
                      _violet,
                      'two_step_reset',
                    ),
                  if (a.avatarPath != null)
                    const _Action(
                      'account.remove_avatar',
                      'Retirer la photo',
                      Icons.hide_image_outlined,
                      null,
                      'remove_avatar',
                    ),
                  if (!a.handleReset)
                    const _Action(
                      'account.reset_handle',
                      'Changer l’identifiant',
                      Icons.alternate_email,
                      null,
                      'reset_handle',
                    ),
                ],
                onTap: _busy ? null : (action) => _act(a, action),
              ),
            ),
          _History(a: a, sanctions: sanctions),
        ]),
      ],
    );
  }
}

/// En-tête : photo, nom, @identifiant, pastilles d'état, numéro.
class _Header extends StatelessWidget {
  const _Header({required this.a, required this.twoStep, required this.now});

  final ConsoleAccount a;
  final bool twoStep;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = _phone(a.phoneE164);
    final (stateLabel, stateColor) = a.deleted
        ? ('Compte supprimé', theme.colorScheme.outline)
        : a.suspended
        ? (
            a.suspendedUntil == null
                ? 'Suspendu sans limite'
                : 'Suspendu jusqu’au ${_time(a.suspendedUntil!)}',
            _red,
          )
        : ('Actif', _green);
    return Container(
      key: const Key('account.header'),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.l,
        PrivioSpacing.m,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_blue.withValues(alpha: 0.16), _blue.withValues(alpha: 0.05)],
        ),
      ),
      child: Column(
        children: [
          UserAvatar(
            key: const Key('account.avatar'),
            name: a.displayName.isEmpty ? a.handle : a.displayName,
            seed: a.userId,
            avatarPath: a.avatarPath,
            radius: 40,
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            a.displayName.isEmpty ? '—' : a.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            '@${a.handle}',
            key: const Key('account.handle'),
            style: theme.textTheme.bodyMedium?.copyWith(color: _blue),
          ),
          const SizedBox(height: PrivioSpacing.s),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill(key: const Key('account.state'), label: stateLabel, color: stateColor),
              if (twoStep) const _Pill(label: 'Deux étapes', color: _violet),
              if (now.difference(a.createdAt).inDays < 7)
                const _Pill(label: 'Nouveau', color: _blue),
              if (a.handleReset) const _Pill(label: 'Identifiant à changer', color: _amber),
              if (a.protected) const _Pill(label: 'Administration', color: _blue),
            ],
          ),
          const SizedBox(height: PrivioSpacing.m),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.phone_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: PrivioSpacing.s),
                Expanded(
                  child: Text(
                    phone ?? 'Numéro inconnu',
                    key: const Key('account.phone'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );
}

/// Quatre chiffres clés en tuiles.
class _Figures extends StatelessWidget {
  const _Figures({required this.a, required this.now});

  final ConsoleAccount a;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final seen = a.lastSeenAt ?? a.lastSeenDay;
    Widget tile(Key key, String value, String label, {Color? tint, String? sub}) {
      final theme = Theme.of(context);
      final c = tint;
      return Expanded(
        child: Container(
          key: key,
          padding: const EdgeInsets.all(PrivioSpacing.m),
          decoration: BoxDecoration(
            color: c == null
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: c),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    const gap = SizedBox(width: PrivioSpacing.s, height: PrivioSpacing.s);
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(const Key('account.directs'), '${a.directs}', 'Discussions'),
              gap,
              tile(const Key('account.groups'), '${a.groups}', 'Groupes'),
            ],
          ),
        ),
        gap,
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                const Key('account.reports'),
                '${a.reportsReceived90d}',
                'Signalé (90 j)',
                tint: a.reportsReceived90d > 0 ? _red : null,
                sub: 'A signalé : ${a.reportsMade90d}',
              ),
              gap,
              tile(
                const Key('account.last_seen'),
                seen == null ? '—' : _ago(seen, now),
                'Dernière activité',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: PrivioSpacing.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, PrivioSpacing.s),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        child,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon),
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Text(value, textAlign: TextAlign.end),
    ),
  );
}

String _revoked(String? reason) => switch (reason) {
  'new_device' => 'remplacé par un autre téléphone',
  'logout' => 'déconnexion par la personne',
  'admin' => 'déconnecté par l’équipe',
  'account_deleted' => 'compte supprimé',
  _ => 'déconnecté',
};

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.d, required this.first, this.onDisconnect});

  final ConsoleDevice d;
  final bool first;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !d.active;
    final system = d.osVersion == null ? 'Android' : 'Android ${d.osVersion}';
    return ListTile(
      key: first ? const Key('account.device') : Key('account.device.${d.id}'),
      leading: CircleAvatar(
        backgroundColor: (muted ? theme.colorScheme.outline : _green).withValues(alpha: 0.14),
        foregroundColor: muted ? theme.colorScheme.outline : _green,
        child: const Icon(Icons.phone_android),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              d.model ?? 'Modèle inconnu',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted ? theme.colorScheme.onSurfaceVariant : null),
            ),
          ),
          if (d.active) ...[const SizedBox(width: 6), const _Pill(label: 'Actif', color: _green)],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$system · version ${d.appVersion}'),
          Text(
            d.active
                ? 'Dernière connexion : ${_time(d.lastSeenAt)}'
                : 'Jusqu’au ${_day(d.revokedAt!)} · ${_revoked(d.revokedReason)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: onDisconnect == null
          ? null
          : IconButton(
              key: Key('account.device.disconnect.${d.id}'),
              tooltip: 'Déconnecter cet appareil',
              icon: const Icon(Icons.logout, color: _red),
              onPressed: onDisconnect,
            ),
    );
  }
}

class _Action {
  const _Action(this.key, this.label, this.icon, this.color, this.action);

  final String key;
  final String label;
  final IconData icon;
  final Color? color;
  final String action;
}

/// Actions en tuiles colorées, deux par ligne.
class _ActionGrid extends StatelessWidget {
  const _ActionGrid({super.key, required this.actions, required this.onTap});

  final List<_Action> actions;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - PrivioSpacing.s) / 2;
        return Wrap(
          spacing: PrivioSpacing.s,
          runSpacing: PrivioSpacing.s,
          children: [
            for (final x in actions)
              SizedBox(
                width: w,
                child: Material(
                  color: (x.color ?? theme.colorScheme.onSurfaceVariant).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: Key(x.key),
                    borderRadius: BorderRadius.circular(16),
                    onTap: onTap == null ? null : () => onTap!(x.action),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.m,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(x.icon, size: 20, color: x.color ?? theme.colorScheme.onSurface),
                          const SizedBox(width: PrivioSpacing.s),
                          Expanded(
                            child: Text(
                              x.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: x.color ?? theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Historique : sanctions, demandes d'assistance et actions de l'équipe, du plus récent
/// au plus ancien.
class _History extends StatelessWidget {
  const _History({required this.a, required this.sanctions});

  final ConsoleAccount a;
  final List<Sanction> sanctions;

  @override
  Widget build(BuildContext context) {
    final items = <(DateTime, IconData, Color, String, String?)>[
      for (final s in sanctions)
        (
          s.createdAt,
          s.kind == 'warning' ? Icons.warning_amber_rounded : Icons.block,
          s.kind == 'warning' ? _amber : _red,
          '${s.kind == 'warning' ? 'Avertissement' : 'Suspension'} · '
              '${reasonLabel(s.reason).toLowerCase()}${s.liftedAt != null ? ' · levée' : ''}',
          s.note,
        ),
      for (final r in a.support)
        (
          r.createdAt,
          Icons.support_agent,
          _blue,
          'Demande d’assistance · ${r.answered ? 'répondue' : 'en attente'}',
          r.details,
        ),
      for (final x in a.actions)
        (
          x.at,
          switch (x.action) {
            'avatar_remove' => Icons.hide_image_outlined,
            'handle_reset' => Icons.alternate_email,
            'two_step_reset' => Icons.lock_reset,
            _ => Icons.phonelink_erase,
          },
          _violet,
          switch (x.action) {
            'avatar_remove' => 'Photo de profil retirée',
            'handle_reset' => 'Identifiant @${x.detail['old_handle'] ?? '—'} remplacé',
            'two_step_reset' => 'Deux étapes réinitialisées',
            _ => 'Téléphone déconnecté par l’équipe',
          },
          null,
        ),
    ]..sort((x, y) => y.$1.compareTo(x.$1));
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return _Section(
      title: 'Historique',
      child: SettingsCard(
        key: const Key('account.history'),
        children: [
          for (final (i, x) in items.indexed) ...[
            if (i > 0) const SettingsDivider(),
            ListTile(
              dense: true,
              leading: Icon(x.$2, color: x.$3),
              title: Text(x.$4),
              subtitle: Text(
                [_time(x.$1), if (x.$5 != null) x.$5!].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lot 5.6 : identifiants réservés. Les mots toujours réservés sont verrouillés ; les autres
/// se réservent et se libèrent ici (une réservation ne retire rien à un compte existant).
class ReservedHandlesView extends ConsumerStatefulWidget {
  const ReservedHandlesView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<ReservedHandlesView> createState() => _ReservedHandlesViewState();
}

class _ReservedHandlesViewState extends ConsumerState<ReservedHandlesView> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _set(String handle, bool reserved) async {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).reserveHandle(handle, reserved: reserved);
      if (reserved) _text.clear();
      ref
        ..invalidate(reservedHandlesProvider)
        ..invalidate(consoleJournalProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            reserved
                ? '@${handle.replaceFirst('@', '').toLowerCase()} est réservé.'
                : '@$handle est libéré.',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(reservedHandlesProvider);
    return ListView(
      key: const Key('reserved.view'),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.m,
        PrivioSpacing.xs,
        PrivioSpacing.m,
        PrivioSpacing.xxl,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('reserved.back'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour à la liste'),
          ),
        ),
        Text('Identifiants réservés', style: theme.textTheme.titleLarge),
        const SizedBox(height: PrivioSpacing.xs),
        Text(
          'Personne ne peut les prendre à l’inscription ni en changeant d’identifiant. '
          'Ils s’affichent comme « déjà pris ».',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.m),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('reserved.input'),
                controller: _text,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Réserver', prefixText: '@'),
              ),
            ),
            const SizedBox(width: PrivioSpacing.s),
            FilledButton(
              key: const Key('reserved.add'),
              onPressed: _busy || _text.text.trim().length < 3
                  ? null
                  : () => _set(_text.text.trim(), true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.l),
        switch (list) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.added.isNotEmpty) ...[
                Text('Ajoutés', style: theme.textTheme.titleSmall),
                const SizedBox(height: PrivioSpacing.s),
                SettingsCard(
                  children: [
                    for (final (i, r) in value.added.indexed) ...[
                      if (i > 0) const SettingsDivider(),
                      ListTile(
                        key: Key('reserved.${r.handle}'),
                        leading: const Icon(Icons.alternate_email, color: _blue),
                        title: Text('@${r.handle}'),
                        subtitle: Text(
                          [
                            'Depuis le ${_day(r.createdAt)}',
                            if (r.inUse) 'déjà porté par un compte',
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          key: Key('reserved.release.${r.handle}'),
                          tooltip: 'Libérer',
                          icon: const Icon(Icons.close),
                          onPressed: _busy ? null : () => _set(r.handle, false),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: PrivioSpacing.l),
              ],
              Text('Toujours réservés', style: theme.textTheme.titleSmall),
              const SizedBox(height: PrivioSpacing.s),
              Wrap(
                key: const Key('reserved.base'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in value.base)
                    Chip(
                      avatar: const Icon(Icons.lock_outline, size: 16),
                      label: Text('@$h'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
          AsyncError(:final error) => ErrorView(
            message: toAppFailure(error).message,
            onRetry: () => ref.invalidate(reservedHandlesProvider),
          ),
          _ => const Padding(padding: EdgeInsets.all(PrivioSpacing.xl), child: LoadingView()),
        },
      ],
    );
  }
}
