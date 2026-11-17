import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import 'console_policies_tab.dart';

/// Lot 5.7 (ADR-047) — rubrique « Santé du service » : versions de l'application,
/// appels, inscriptions et coût des SMS, diagnostics, alertes. Des nombres seulement.
class ConsoleHealthTab extends ConsumerWidget {
  const ConsoleHealthTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(consoleHealthProvider);
    return switch (health) {
      AsyncData(:final value) => RefreshIndicator(
        key: const Key('health.refresh'),
        onRefresh: () => ref.refresh(consoleHealthProvider.future),
        child: _HealthList(h: value),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleHealthProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

String _pct(double v) => '${(v * 100).round()} %';

/// Go décimaux, comme le volume gratuit du relais (« 12,4 Go »).
String _gb(int bytes) {
  final v = bytes / 1e9;
  final t = v >= 100 ? formatThousands(v.round()) : v.toStringAsFixed(1).replaceAll('.', ',');
  return '$t Go';
}

String _duration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m == 0 ? '$s s' : '$m min ${s.toString().padLeft(2, '0')}';
}

String _ago(DateTime at, DateTime now) {
  final d = now.difference(at.toLocal());
  if (d.inMinutes < 1) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

class _HealthList extends ConsumerWidget {
  const _HealthList({required this.h});

  final ConsoleHealth h;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(consolePoliciesProvider).value ?? const <ConsolePolicy>[];
    ConsolePolicy? policy(String key) => policies.where((p) => p.key == key).firstOrNull;
    final now = DateTime.now();
    return ListView(
      key: const Key('console.health'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        const SettingsNote(
          'Des nombres seulement\u202F: aucun numéro, aucun message. Tirez vers le bas pour actualiser.',
        ),
        // ------------------------------------------------------------------ Versions
        const SettingsSectionTitle('Versions de l’application'),
        SettingsCard(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          children: [
            _Numbers(
              items: [
                _Num('health.devices', 'Téléphones actifs (30 j)', '${h.devices}'),
                _Num(
                  'health.below_recommended',
                  'Sous la version conseillée',
                  '${h.belowRecommended}',
                  warn: h.belowRecommended > 0,
                ),
                _Num(
                  'health.below_min',
                  'Bloqués (sous la minimale)',
                  '${h.belowMin}',
                  warn: h.belowMin > 0,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.m),
        SettingsCard(
          children: [
            for (final key in ['app_recommended_build', 'app_min_build'])
              if (policy(key) case final p?) _PolicyRow(policy: p),
            if (policy('app_update_url') case final p?) _UrlRow(policy: p),
          ],
        ),
        const SettingsNote(
          'Le numéro de version est celui après le «\u202F+\u202F» (0.1.0+69 → 69). Touchez une version '
          'installée pour la conseiller ou l’imposer.',
        ),
        const SizedBox(height: PrivioSpacing.m),
        SettingsCard(
          children: [
            if (h.installed.isEmpty)
              const ListTile(title: Text('Aucun téléphone actif ces 30 derniers jours')),
            for (final v in h.installed)
              _VersionRow(
                v: v,
                minBuild: h.minBuild,
                recommendedBuild: h.recommendedBuild,
                total: h.devices,
                onTap: v.build == null
                    ? null
                    : () => _chooseVersion(context, ref, v.build!, policy),
              ),
          ],
        ),
        // ------------------------------------------------------------------ Appels
        const SettingsSectionTitle('Appels (30 derniers jours)'),
        SettingsCard(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          children: [
            _Numbers(
              items: [
                _Num(
                  'health.calls',
                  'Appels (audio · vidéo)',
                  '${h.callsTotal30d}',
                  sub: '${h.callsAudio30d} · ${h.callsVideo30d}',
                ),
                _Num('health.calls_ok', 'Réussis', '${h.callsOk30d}'),
                _Num(
                  'health.calls_failed',
                  'Échoués (connexion perdue)',
                  '${h.callsFailed30d}',
                  warn: h.callsFailed30d > 0 && h.callsFailed30d * 10 > h.callsTotal30d * 3,
                ),
                _Num(
                  'health.calls_unanswered',
                  'Sans réponse ou refusés',
                  '${h.callsUnanswered30d}',
                ),
                _Num(
                  'health.calls_avg',
                  'Durée moyenne',
                  h.averageCall == null ? '—' : _duration(h.averageCall!),
                ),
                _Num(
                  'health.relay_share',
                  'Passés par le relais',
                  h.relayShare == null ? '—' : _pct(h.relayShare!),
                  sub: '${h.callsRelayed30d} sur ${h.callsReported30d}',
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.l),
            _Gauge(
              key: const Key('health.relay_gauge'),
              label:
                  'Relais Cloudflare ce mois-ci : ${_gb(h.relayBytesMonth)} sur '
                  '${_gb(h.relayFreeBytes)} gratuits (estimation)',
              value: h.relayUse,
              warnAt: 0.8,
            ),
          ],
        ),
        const SettingsNote(
          'Chaque téléphone signale à la fin d’un appel décroché s’il passait par le relais et '
          'le volume échangé. Les applications antérieures au lot 5.7 ne le signalent pas.',
        ),
        // ------------------------------------------------------------------ Inscriptions
        const SettingsSectionTitle('Inscriptions et codes SMS (30 derniers jours)'),
        SettingsCard(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          children: [
            _Funnel(
              steps: [
                ('health.codes', 'Codes envoyés', h.codes30d),
                ('health.verified', 'Codes vérifiés', h.verified30d),
                ('health.profiles', 'Profils créés', h.profiles30d),
              ],
            ),
            const SizedBox(height: PrivioSpacing.m),
            Text(
              'Dont changements de numéro : ${h.phoneChange30d} · dernière heure : '
              '${h.codes1h} · 24 h : ${h.codes24h}',
              key: const Key('health.codes_detail'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (h.verifiedShare case final s?)
              Text(
                'Codes vérifiés : ${_pct(s)} des codes envoyés',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: PrivioSpacing.xl),
            Text(
              h.unitCost == 0
                  ? 'Renseignez le prix d’un SMS pour estimer le coût.'
                  : 'Coût estimé : ${formatPolicyValue('fcfa', h.costMonth)} ce mois-ci '
                        '(${h.codesMonth} codes) · ${formatPolicyValue('fcfa', h.cost30d)} sur 30 jours',
              key: const Key('health.cost'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        if (policy('sms_unit_cost') case final p?) ...[
          const SizedBox(height: PrivioSpacing.m),
          SettingsCard(children: [_PolicyRow(policy: p)]),
        ],
        // ------------------------------------------------------------------ Diagnostics
        const SettingsSectionTitle('Diagnostics'),
        _Diagnostics(h: h),
        const SizedBox(height: PrivioSpacing.m),
        SettingsCard(
          children: [
            if (h.jobs.isEmpty)
              const ListTile(title: Text('Tâches automatiques indisponibles sur ce serveur')),
            for (final j in h.jobs)
              ListTile(
                key: Key('health.job.${j.job}'),
                dense: true,
                leading: Icon(
                  j.late(now) ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: j.late(now)
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFF13866B),
                ),
                title: Text(j.label),
                subtitle: Text(
                  j.lastRun == null
                      ? 'pas encore de passage'
                      : '${_ago(j.lastRun!.at, now)}, ${j.lastRun!.ok ? 'réussi' : 'en échec'}',
                ),
              ),
          ],
        ),
        SettingsNote(
          'Messages expirés en attente d’effacement : ${h.expiredWaiting} · fichiers : '
          '${h.filesWaiting}',
        ),
        // ------------------------------------------------------------------ Alertes
        const SettingsSectionTitle('Alertes'),
        SettingsCard(
          children: [
            if (policy('health_alerts_enabled') case final p?) _AlertSwitch(policy: p),
            if (policy('sms_alert_per_hour') case final p?) _PolicyRow(policy: p),
          ],
        ),
        SettingsNote(
          'Effacement en retard, pic de codes SMS, échecs de notifications (20 % sur 1 h) '
          'ou d’appels (30 % sur 24 h), relais à 80 %\u202F: une notification sans contenu, au '
          'plus une par type toutes les 6 h. Téléphones de l’administration qui la reçoivent : '
          '${h.adminPushTargets}.',
        ),
        const SizedBox(height: PrivioSpacing.m),
        SettingsCard(
          children: [
            if (h.alerts.isEmpty)
              const ListTile(
                key: Key('health.no_alert'),
                leading: Icon(Icons.check_circle_outline, color: Color(0xFF13866B)),
                title: Text('Aucune alerte ces 30 derniers jours'),
              ),
            for (final (i, a) in h.alerts.indexed)
              ListTile(
                key: Key('health.alert.$i'),
                leading: Icon(
                  Icons.notification_important_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(a.title),
                subtitle: Text('${_ago(a.at, now)} · ${a.text}'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _chooseVersion(
    BuildContext context,
    WidgetRef ref,
    int build,
    ConsolePolicy? Function(String) policy,
  ) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          key: const Key('health.version_sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Version n° $build'),
              subtitle: const Text('Les téléphones relisent ce réglage au retour dans l’app.'),
            ),
            ListTile(
              key: const Key('health.version.recommend'),
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('En faire la version conseillée'),
              subtitle: const Text('Bandeau «\u202FMise à jour disponible\u202F» en dessous'),
              onTap: () => Navigator.pop(context, 'app_recommended_build'),
            ),
            ListTile(
              key: const Key('health.version.require'),
              leading: Icon(Icons.block_rounded, color: Theme.of(context).colorScheme.error),
              title: const Text('En faire la version minimale'),
              subtitle: const Text('En dessous, Privio ne s’utilise plus avant la mise à jour'),
              onTap: () => Navigator.pop(context, 'app_min_build'),
            ),
          ],
        ),
      ),
    );
    final p = key == null ? null : policy(key);
    if (p == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PolicyEditorSheet(policy: p, initialValue: build),
    );
    ref.invalidate(consoleHealthProvider);
  }
}

class _Num {
  const _Num(this.id, this.label, this.value, {this.sub, this.warn = false});

  final String id;
  final String label;
  final String value;
  final String? sub;
  final bool warn;
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.items});

  final List<_Num> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - PrivioSpacing.m) / 2;
        return Wrap(
          spacing: PrivioSpacing.m,
          runSpacing: PrivioSpacing.m,
          children: [
            for (final n in items)
              SizedBox(
                width: w,
                child: Column(
                  key: Key(n.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        n.value,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: n.warn ? theme.colorScheme.error : null,
                        ),
                      ),
                    ),
                    Text(
                      n.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (n.sub != null) Text(n.sub!, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Jauge d'utilisation (rouge au-delà de [warnAt]).
class _Gauge extends StatelessWidget {
  const _Gauge({super.key, required this.label, required this.value, required this.warnAt});

  final String label;
  final double value;
  final double warnAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final warn = value >= warnAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: PrivioSpacing.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 8,
            color: warn ? theme.colorScheme.error : p.accentText,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// Parcours : code envoyé → vérifié → profil créé.
class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});

  final List<(String, String, int)> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, (id, label, n)) in steps.indexed) ...[
          if (i > 0)
            Icon(Icons.arrow_forward_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          Expanded(
            child: Column(
              key: Key(id),
              children: [
                Text(
                  formatThousands(n),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Une version installée : nombre de téléphones, repères « conseillée » et « minimale ».
class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.v,
    required this.minBuild,
    required this.recommendedBuild,
    required this.total,
    this.onTap,
  });

  final InstalledVersion v;
  final int minBuild;
  final int recommendedBuild;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = v.build;
    final (tag, color) = b == null
        ? ('version inconnue', theme.colorScheme.onSurfaceVariant)
        : (minBuild > 0 && b < minBuild)
        ? ('bloquée', theme.colorScheme.error)
        : (recommendedBuild > 0 && b < recommendedBuild)
        ? ('mise à jour conseillée', const Color(0xFFB7700F))
        : ('à jour', const Color(0xFF13866B));
    return ListTile(
      key: Key('health.version.${v.version}'),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(Icons.phone_android_rounded, color: color, size: 18),
      ),
      title: Text(v.version),
      subtitle: Text(
        '${v.devices} téléphone${v.devices > 1 ? 's' : ''}'
        '${total == 0 ? '' : ' (${_pct(v.devices / total)})'} · $tag',
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Réglage numérique de la santé (versions, prix, seuil) : même éditeur que Réglages.
class _PolicyRow extends ConsumerWidget {
  const _PolicyRow({required this.policy});

  final ConsolePolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    return ListTile(
      key: Key('policy.${policy.key}'),
      title: Text(policy.label),
      subtitle: Text(
        policy.format(policy.value),
        style: policy.isDefault ? null : TextStyle(color: p.accentText),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => PolicyEditorSheet(policy: policy),
        );
        ref.invalidate(consoleHealthProvider);
      },
    );
  }
}

/// Lien de mise à jour (https), modifiable ; vide : la personne est invitée à réessayer.
class _UrlRow extends ConsumerWidget {
  const _UrlRow({required this.policy});

  final ConsolePolicy policy;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _UrlDialog(initial: policy.value as String? ?? ''),
    );
    if (next == null || next == policy.value || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await savePolicy(ref, policy, next);
      ref.invalidate(consoleHealthProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(next.isEmpty ? 'Lien retiré' : 'Lien de mise à jour enregistré')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = (policy.value as String? ?? '').trim();
    return ListTile(
      key: const Key('policy.app_update_url'),
      title: Text(policy.label),
      subtitle: Text(url.isEmpty ? 'Aucun lien · toucher pour en ajouter un' : url),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _edit(context, ref),
    );
  }
}

class _UrlDialog extends StatefulWidget {
  const _UrlDialog({required this.initial});

  final String initial;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty && !RegExp(r'^https://\S+$').hasMatch(v)) {
      setState(() => _error = 'Le lien doit commencer par https:// (sans espace).');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('update_url.editor'),
    title: const Text('Lien de mise à jour'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ouvert par le bouton «\u202FMettre à jour\u202F» du bandeau et de l’écran bloquant.',
        ),
        const SizedBox(height: PrivioSpacing.m),
        TextField(
          key: const Key('update_url.input'),
          controller: _ctrl,
          maxLength: 300,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: InputDecoration(hintText: 'https://…', errorText: _error),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const Key('update_url.clear'),
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Retirer'),
      ),
      FilledButton(
        key: const Key('update_url.save'),
        onPressed: _save,
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

/// Alertes par notification : interrupteur (confirmé comme tout réglage).
class _AlertSwitch extends ConsumerWidget {
  const _AlertSwitch({required this.policy});

  final ConsolePolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    key: const Key('health.alerts_switch'),
    title: Text(policy.label),
    subtitle: Text(policy.value == true ? 'Activées' : 'Désactivées'),
    value: policy.value == true,
    onChanged: (_) async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => PolicyEditorSheet(policy: policy, initialValue: policy.value != true),
      );
      ref.invalidate(consoleHealthProvider);
    },
  );
}

/// Notification de test et test du relais, avec leur résultat.
class _Diagnostics extends ConsumerStatefulWidget {
  const _Diagnostics({required this.h});

  final ConsoleHealth h;

  @override
  ConsumerState<_Diagnostics> createState() => _DiagnosticsState();
}

class _DiagnosticsState extends ConsumerState<_Diagnostics> {
  bool _pushing = false;
  bool _relaying = false;
  RelayTestResult? _relay;
  Timer? _refresh;

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _testPush() async {
    setState(() => _pushing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).testPush();
      messenger.showSnackBar(
        const SnackBar(
          key: Key('health.push_sent'),
          content: Text(
            'Notification de test envoyée\u202F: elle doit arriver dans quelques secondes.',
          ),
        ),
      );
      // Le compte rendu de push-dispatch arrive juste après : on relit la santé.
      _refresh = Timer(const Duration(seconds: 4), () {
        if (mounted) ref.invalidate(consoleHealthProvider);
      });
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _testRelay() async {
    setState(() {
      _relaying = true;
      _relay = null;
    });
    final r = await ref.read(adminApiProvider).testRelay();
    if (mounted) {
      setState(() {
        _relaying = false;
        _relay = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final test = widget.h.lastTest;
    Widget status(bool ok, String text, Key key) => Row(
      key: key,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.info_outline,
          size: 18,
          color: ok ? const Color(0xFF13866B) : theme.colorScheme.error,
        ),
        const SizedBox(width: PrivioSpacing.s),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
    return SettingsCard(
      padding: const EdgeInsets.all(PrivioSpacing.l),
      children: [
        OutlinedButton.icon(
          key: const Key('health.test_push'),
          onPressed: _pushing ? null : _testPush,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Envoyer une notification de test'),
        ),
        if (test != null) ...[
          const SizedBox(height: PrivioSpacing.s),
          status(
            test.ok,
            'Dernier test (${_ago(test.at, DateTime.now())}) : ${test.text}',
            const Key('health.push_result'),
          ),
        ],
        const SizedBox(height: PrivioSpacing.l),
        OutlinedButton.icon(
          key: const Key('health.test_relay'),
          onPressed: _relaying ? null : _testRelay,
          icon: _relaying
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_calls_rounded),
          label: const Text('Tester le relais des appels'),
        ),
        if (_relay case final r?) ...[
          const SizedBox(height: PrivioSpacing.s),
          status(r.ok, r.text, const Key('health.relay_result')),
        ],
      ],
    );
  }
}
