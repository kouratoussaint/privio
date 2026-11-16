import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/console_providers.dart';
import '../../core/motion/motion.dart';
import '../../core/widgets/state_views.dart';
import '../lock/app_lock_screens.dart';
import 'console_accounts_tab.dart';
import 'console_features_tab.dart';
import 'console_journal_tab.dart';
import 'console_policies_tab.dart';
import 'console_reports_tab.dart';
import 'console_stats_tab.dart';

/// Console d'administration (lot 5.1, amendement 6). Réservée au compte administrateur :
/// le serveur le vérifie à chaque appel. À chaque ouverture : code Privio ou empreinte ;
/// refermée après [ConsoleScreen.idleTimeout] sans action ou quand l'app passe en arrière-plan.
class ConsoleScreen extends ConsumerStatefulWidget {
  const ConsoleScreen({super.key});

  static const idleTimeout = Duration(minutes: 5);

  @override
  ConsumerState<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends ConsumerState<ConsoleScreen> with WidgetsBindingObserver {
  bool _verified = false;
  ConsoleSection _section = ConsoleSection.home;
  String? _message;
  bool _error = false;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sortie de l'app (même brève) : la console se referme.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _close();
  }

  void _close({bool idle = false}) {
    _idle?.cancel();
    if (!_verified || !mounted) return;
    // Dialogues et feuilles ouverts au-dessus de la console : refermés aussi.
    Navigator.of(context).popUntil((r) => r is! PopupRoute);
    setState(() {
      _verified = false;
      _message = idle ? 'Console refermée après 5 min sans action.' : null;
      _error = false;
    });
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(ConsoleScreen.idleTimeout, () => _close(idle: true));
  }

  /// Rubriques visitées (bouton retour du téléphone : on y revient une à une).
  final List<ConsoleSection> _history = [];

  /// Fiches ouvertes dans une rubrique (compte, dossier) : le retour les referme d'abord.
  final List<bool Function()> _backHandlers = [];

  void _go(ConsoleSection s) {
    if (s == _section) return;
    setState(() {
      _history.add(_section);
      _section = s;
    });
  }

  /// Lot 5.5 (correction du 16/11/2026) : retour dans la console. Menu latéral (fermé par
  /// Flutter), puis fiche ouverte, puis rubrique précédente, puis Accueil ; on ne quitte la
  /// console que depuis l'Accueil.
  void _back() {
    for (final h in _backHandlers.reversed.toList()) {
      if (h()) return;
    }
    if (_history.isNotEmpty) {
      setState(() => _section = _history.removeLast());
      return;
    }
    if (_section != ConsoleSection.home) {
      setState(() => _section = ConsoleSection.home);
      return;
    }
    Navigator.of(context).pop();
  }

  void _open() {
    ref.invalidate(consoleDashboardProvider);
    setState(() {
      _verified = true;
      _section = ConsoleSection.home;
      _history.clear();
      _message = null;
      _error = false;
    });
    _touch();
  }

  Future<void> _pin(String pin) async {
    final r = await ref.read(appLockProvider.notifier).verify(pin);
    if (!mounted) return;
    switch (r) {
      case Unlocked():
        _open();
      case WrongPin():
        setState(() {
          _message = 'Code incorrect.';
          _error = true;
        });
      case MustWait(:final until):
        setState(() {
          _message =
              'Trop d’essais. Réessayez dans ${formatWait(until.difference(DateTime.now()))}.';
          _error = true;
        });
    }
  }

  Future<void> _biometrics() async {
    final ok = await ref
        .read(appLockProvider.notifier)
        .confirmWithBiometrics('Ouvrir la console Privio');
    if (ok && mounted) _open();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider).value;
    final open = _verified && (lock?.enabled ?? false);
    final scaffold = Scaffold(
      drawer: open ? _ConsoleDrawer(current: _section, onSelect: _go) : null,
      appBar: AppBar(
        title: Text(open ? _section.label : 'Administration'),
        // Lot 5.5 : menu latéral (plus d'onglets à faire défiler).
        leading: open
            ? Builder(
                builder: (context) => IconButton(
                  key: const Key('console.menu'),
                  tooltip: 'Menu de la console',
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
        actions: [
          if (open)
            IconButton(
              key: const Key('console.close'),
              tooltip: 'Refermer la console',
              icon: const Icon(Icons.lock_outline),
              onPressed: _close,
            ),
        ],
      ),
      body: switch ((lock, _verified)) {
        (null, _) => const LoadingView(),
        (final l?, _) when !l.enabled => const _LockRequired(),
        (_, true) => Listener(
          onPointerDown: (_) => _touch(),
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            switchInCurve: Motion.enter,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: switch (_section) {
                ConsoleSection.home => _Dashboard(onOpen: _go),
                ConsoleSection.reports => const ConsoleReportsTab(),
                ConsoleSection.accounts => const ConsoleAccountsTab(),
                ConsoleSection.features => const ConsoleFeaturesTab(),
                ConsoleSection.policies => const ConsolePoliciesTab(),
                ConsoleSection.stats => const ConsoleStatsTab(),
                ConsoleSection.journal => const ConsoleJournalTab(),
              },
            ),
          ),
        ),
        (final l?, false) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PrivioSpacing.xl),
            child: PinEntry(
              key: const Key('console.pin'),
              title: 'Code Privio',
              message: _message ?? 'Confirmez votre identité pour ouvrir la console.',
              error: _error,
              onComplete: _pin,
              extra: l.config.biometrics && l.biometricsAvailable
                  ? IconButton(
                      key: const Key('console.biometrics'),
                      tooltip: 'Utiliser l’empreinte',
                      icon: const Icon(Icons.fingerprint),
                      iconSize: 32,
                      onPressed: _biometrics,
                    )
                  : null,
            ),
          ),
        ),
      },
    );
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ConsoleBackScope(handlers: _backHandlers, child: scaffold),
    );
  }
}

/// Lot 5.5 — rubriques de la console, chacune avec sa couleur.
enum ConsoleSection {
  home('dashboard', 'Accueil', Icons.space_dashboard_outlined, Color(0xFF6A3FD0)),
  reports('reports', 'Signalements', Icons.flag_outlined, Color(0xFFD85A30)),
  accounts('accounts', 'Comptes', Icons.people_outline, Color(0xFF2A73C9)),
  features('features', 'Fonctionnalités', Icons.toggle_on_outlined, Color(0xFF8E44C9)),
  policies('policies', 'Réglages', Icons.tune_rounded, Color(0xFF3E8B1A)),
  stats('stats', 'Statistiques', Icons.insights_outlined, Color(0xFF138A6E)),
  journal('journal', 'Journal', Icons.history_rounded, Color(0xFF5A6B85));

  const ConsoleSection(this.id, this.label, this.icon, this.color);

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

class _ConsoleDrawer extends StatelessWidget {
  const _ConsoleDrawer({required this.current, required this.onSelect});

  final ConsoleSection current;
  final ValueChanged<ConsoleSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      key: const Key('console.drawer'),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.m),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, PrivioSpacing.s, 20, PrivioSpacing.l),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6A3FD0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Console Privio', style: theme.textTheme.titleMedium),
                        Text(
                          'Administration',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final s in ConsoleSection.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Material(
                  color: s == current ? s.color.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    key: Key('console.tab.${s.id}'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: s.color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(s.icon, color: s.color, size: 20),
                    ),
                    title: Text(
                      s.label,
                      style: TextStyle(
                        fontWeight: s == current ? FontWeight.w700 : FontWeight.w500,
                        color: s == current ? s.color : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(s);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Verrouillage obligatoire pour ouvrir la console.
class _LockRequired extends StatelessWidget {
  const _LockRequired();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        child: Column(
          key: const Key('console.lock_required'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: PrivioSpacing.l),
            Text(
              'Verrouillage obligatoire',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PrivioSpacing.s),
            Text(
              'Pour ouvrir la console, activez d’abord le verrouillage de Privio '
              '(code ou empreinte). Il vous sera demandé à chaque ouverture.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton.icon(
              key: const Key('console.enable_lock'),
              onPressed: () => context.push(Routes.appLockNew),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Activer le verrouillage'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tableau de bord
// ---------------------------------------------------------------------------
class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.onOpen});

  final ValueChanged<ConsoleSection> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(consoleDashboardProvider);
    return switch (dash) {
      AsyncData(:final value) => RefreshIndicator(
        key: const Key('console.refresh'),
        onRefresh: () => ref.refresh(consoleDashboardProvider.future),
        child: _DashboardList(d: value, onOpen: onOpen),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleDashboardProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

class _DashboardList extends StatelessWidget {
  const _DashboardList({required this.d, required this.onOpen});

  final ConsoleDashboard d;
  final ValueChanged<ConsoleSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final since = d.countingSince;
    final healthy = d.expiredWaiting == 0 && d.pushFailed24h == 0;
    return ListView(
      key: const Key('console.dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        Text(
          'Mis à jour à ${_hm(d.generatedAt.toLocal())} · tirez vers le bas pour actualiser',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        // Lot 5.5 : rubriques en tuiles colorées (ce qui attend une action en avant).
        const SizedBox(height: PrivioSpacing.m),
        _Tiles(
          onOpen: onOpen,
          badges: {
            ConsoleSection.reports: d.reportsOpen > 0
                ? '${d.reportsOpen} à traiter'
                : 'Rien à traiter',
            ConsoleSection.accounts: '${d.accountsTotal} comptes',
            ConsoleSection.features: 'Activer, couper',
            ConsoleSection.policies: 'Limites et délais',
            ConsoleSection.stats: '30 derniers jours',
            ConsoleSection.journal: 'Toutes les actions',
          },
          alert: {if (d.reportsOpen > 0) ConsoleSection.reports},
        ),
        _Section(
          title: 'Comptes',
          icon: Icons.people_outline,
          stats: [
            _Stat('accounts.total', 'Comptes', d.accountsTotal),
            _Stat('accounts.active_24h', 'Actifs (24\u00A0h)', d.active24h),
            _Stat('accounts.active_7d', 'Actifs (7\u00A0jours)', d.active7d),
            _Stat('accounts.new_7d', 'Nouveaux (7\u00A0jours)', d.new7d),
          ],
        ),
        _Section(
          title: 'Activité',
          icon: Icons.chat_bubble_outline,
          stats: [
            _Stat('activity.today', 'Messages aujourd’hui', d.messagesToday),
            _Stat('activity.7d', 'Messages (7\u00A0jours)', d.messages7d),
            _Stat('activity.voice', 'Vocaux (7\u00A0jours)', d.voice7d),
            _Stat('activity.photos', 'Photos (7\u00A0jours)', d.photos7d),
          ],
          footnote: 'Messages en cours de conservation : ${d.messagesLive}',
        ),
        _Section(
          title: 'Groupes et demandes',
          icon: Icons.groups_outlined,
          stats: [
            _Stat('groups.total', 'Groupes', d.groupsTotal),
            _Stat('groups.created', 'Créés (7\u00A0jours)', d.groupsCreated7d),
            _Stat('groups.invitations', 'Invitations en attente', d.invitationsPending),
            _Stat('requests.pending', 'Demandes en attente', d.requestsPending),
            _Stat('requests.accepted', 'Demandes acceptées (7\u00A0j)', d.requestsAccepted7d),
            _Stat('requests.refused', 'Demandes refusées (7\u00A0j)', d.requestsRefused7d),
          ],
        ),
        _Section(
          title: 'Santé technique',
          icon: healthy ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          warn: !healthy,
          stats: [
            _Stat('health.push_sent', 'Notifications envoyées (24\u00A0h)', d.pushSent24h),
            _Stat(
              'health.push_failed',
              'Notifications en échec (24\u00A0h)',
              d.pushFailed24h,
              warn: d.pushFailed24h > 0,
            ),
            _Stat(
              'health.expired',
              'Messages expirés non effacés',
              d.expiredWaiting,
              warn: d.expiredWaiting > 0,
            ),
            _Stat('health.files', 'Fichiers à effacer', d.filesWaiting),
            _Stat.text('health.voice', 'Stockage vocaux', formatBytes(d.storageVoiceBytes)),
            _Stat.text('health.photos', 'Stockage photos', formatBytes(d.storagePhotoBytes)),
          ],
          footnote:
              'Effacement des messages : ${_run(d.purgeMessages)}\n'
              'Effacement des fichiers : ${_run(d.purgeMedia)}'
              '${d.pushNotConfigured24h > 0 ? '\nNotifications non configurées sur ce serveur (${d.pushNotConfigured24h} en 24 h)' : ''}',
        ),
        _Section(
          title: 'Signalements',
          icon: Icons.flag_outlined,
          warn: d.reportsOpen > 0,
          stats: [_Stat('reports.open', 'En attente', d.reportsOpen, warn: d.reportsOpen > 0)],
        ),
        const SizedBox(height: PrivioSpacing.l),
        Text(
          'Chiffres seulement : aucun message, nom ni numéro n’est visible ici. '
          'Chaque ouverture est inscrite au journal de la console.'
          '${since == null ? '' : ' Activité comptée depuis le ${_dmy(since)}.'}',
          key: const Key('console.privacy_note'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  static String _dmy(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year}';

  static String _run(CronRun? r) {
    if (r == null) return 'pas encore de passage';
    final ago = DateTime.now().difference(r.at.toLocal());
    final when = ago.inMinutes < 1
        ? 'à l’instant'
        : ago.inMinutes < 60
        ? 'il y a ${ago.inMinutes} min'
        : ago.inHours < 24
        ? 'il y a ${ago.inHours} h'
        : 'le ${_dmy(r.at.toLocal())}';
    return '$when, ${r.ok ? 'réussi' : 'en échec'}';
  }
}

/// Lot 5.5 : tuiles des rubriques (2 par ligne).
class _Tiles extends StatelessWidget {
  const _Tiles({required this.onOpen, required this.badges, this.alert = const {}});

  final ValueChanged<ConsoleSection> onOpen;
  final Map<ConsoleSection, String> badges;
  final Set<ConsoleSection> alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - PrivioSpacing.m) / 2;
        return Wrap(
          spacing: PrivioSpacing.m,
          runSpacing: PrivioSpacing.m,
          children: [
            for (final (i, s) in ConsoleSection.values.skip(1).indexed)
              AppearIn(
                delay: Duration(milliseconds: 40 * i),
                offset: const Offset(0, 0.15),
                child: SizedBox(
                  width: w,
                  child: Material(
                    color: s.color.withValues(alpha: dark ? 0.26 : 0.1),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      key: Key('console.tile.${s.id}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onOpen(s),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                  child: Icon(s.icon, color: Colors.white, size: 20),
                                ),
                                const Spacer(),
                                if (alert.contains(s))
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              s.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              badges[s] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: alert.contains(s)
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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

class _Stat {
  const _Stat(this.id, this.label, int value, {this.warn = false}) : text = '$value';
  const _Stat.text(this.id, this.label, this.text) : warn = false;

  final String id;
  final String label;
  final String text;
  final bool warn;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.stats,
    this.footnote,
    this.warn = false,
  });

  final String title;
  final IconData icon;
  final List<_Stat> stats;
  final String? footnote;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final accent = warn ? theme.colorScheme.error : p.accentText;
    return Padding(
      padding: const EdgeInsets.only(top: PrivioSpacing.l),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: accent),
                  const SizedBox(width: PrivioSpacing.s),
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: PrivioSpacing.m),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - PrivioSpacing.m) / 2;
                  return Wrap(
                    spacing: PrivioSpacing.m,
                    runSpacing: PrivioSpacing.m,
                    children: [
                      for (final s in stats)
                        SizedBox(
                          width: w,
                          child: Column(
                            key: Key('console.${s.id}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  s.text,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: s.warn ? theme.colorScheme.error : null,
                                  ),
                                ),
                              ),
                              Text(
                                s.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (footnote != null) ...[
                const SizedBox(height: PrivioSpacing.m),
                Text(footnote!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lot 5.5 : une rubrique qui ouvre une fiche (compte, dossier) s'inscrit ici pour que le
/// bouton retour la referme avant de changer de rubrique.
class ConsoleBackScope extends InheritedWidget {
  const ConsoleBackScope({super.key, required this.handlers, required super.child});

  final List<bool Function()> handlers;

  static List<bool Function()>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ConsoleBackScope>()?.handlers;

  @override
  bool updateShouldNotify(ConsoleBackScope oldWidget) => false;
}

/// Inscrit [handler] auprès de la console tant que la rubrique est affichée.
mixin ConsoleBackHandler<T extends StatefulWidget> on State<T> {
  List<bool Function()>? _handlers;

  /// Vrai si le retour a été traité (fiche refermée).
  bool handleBack();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handlers ??= ConsoleBackScope.of(context)?..add(handleBack);
  }

  @override
  void dispose() {
    _handlers?.remove(handleBack);
    super.dispose();
  }
}
