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
import '../../core/widgets/state_views.dart';
import '../lock/app_lock_screens.dart';
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

  void _open() {
    ref.invalidate(consoleDashboardProvider);
    setState(() {
      _verified = true;
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
    final onBar =
        Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          if (open)
            IconButton(
              key: const Key('console.close'),
              tooltip: 'Refermer la console',
              icon: const Icon(Icons.lock_outline),
              onPressed: _close,
            ),
        ],
        // Lots 5.2 et 5.3 : cinq onglets une fois la console ouverte.
        bottom: open
            ? TabBar(
                key: const Key('console.tabs'),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                // Lisible sur la barre violette : blanc, et blanc atténué pour les autres onglets.
                labelColor: onBar,
                unselectedLabelColor: onBar.withValues(alpha: 0.78),
                indicatorColor: onBar,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(key: Key('console.tab.dashboard'), text: 'Tableau de bord'),
                  Tab(key: Key('console.tab.reports'), text: 'Signalements'),
                  Tab(key: Key('console.tab.policies'), text: 'Réglages'),
                  Tab(key: Key('console.tab.stats'), text: 'Statistiques'),
                  Tab(key: Key('console.tab.journal'), text: 'Journal'),
                ],
              )
            : null,
      ),
      body: switch ((lock, _verified)) {
        (null, _) => const LoadingView(),
        (final l?, _) when !l.enabled => const _LockRequired(),
        (_, true) => Listener(
          onPointerDown: (_) => _touch(),
          child: const TabBarView(
            children: [
              _Dashboard(),
              ConsoleReportsTab(),
              ConsolePoliciesTab(),
              ConsoleStatsTab(),
              ConsoleJournalTab(),
            ],
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
    return open ? DefaultTabController(length: 5, child: scaffold) : scaffold;
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
  const _Dashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(consoleDashboardProvider);
    return switch (dash) {
      AsyncData(:final value) => RefreshIndicator(
        key: const Key('console.refresh'),
        onRefresh: () => ref.refresh(consoleDashboardProvider.future),
        child: _DashboardList(d: value),
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
  const _DashboardList({required this.d});

  final ConsoleDashboard d;

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
          footnote: 'Leur traitement arrive au lot 5.3.',
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
