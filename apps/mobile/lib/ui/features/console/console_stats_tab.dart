import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../domain/models/console_team.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/state_views.dart';
import 'day_bars.dart';
import 'stats_export.dart';

/// Onglet « Statistiques » (lot 5.2) : 30 derniers jours, nombres anonymes seulement.
class ConsoleStatsTab extends ConsumerWidget {
  const ConsoleStatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(consoleStatsProvider);
    return switch (stats) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consoleStatsProvider.future),
        child: _StatsList(s: value),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleStatsProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

String _pct(int part, int total) => total == 0 ? '—' : '${(part * 100 / total).round()} %';

String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _StatsList extends StatelessWidget {
  const _StatsList({required this.s});

  final ConsoleStats s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = [for (final d in s.days) d.day];
    final messages = s.sum((d) => d.messages);
    final requests = s.sum((d) => d.requests);
    final pushSent = s.sum((d) => d.pushSent);
    final pushFailed = s.sum((d) => d.pushFailed);
    final since = s.countingSince;
    return ListView(
      key: const Key('console.stats'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        Text(
          '30 derniers jours, en nombres seulement'
          '${since == null ? '' : ' · activité comptée depuis le ${_dmy(since)}'}.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        _Card(
          id: 'messages',
          title: 'Messages par jour',
          headline: formatThousands(messages),
          headlineLabel: 'messages sur 30 jours',
          children: [
            DayBars(
              key: const Key('stats.bars.messages'),
              days: days,
              values: [for (final d in s.days) d.messages],
              semanticLabel: 'Messages par jour sur 30 jours, total $messages',
            ),
            const SizedBox(height: PrivioSpacing.l),
            _Share('Texte', s.sum((d) => d.text), messages),
            _Share('Vocaux', s.sum((d) => d.voice), messages),
            _Share('Photos', s.sum((d) => d.photo), messages),
          ],
        ),
        _Card(
          id: 'active',
          title: 'Comptes actifs par jour',
          headline: s.days.isEmpty || s.days.last.active == null
              ? '—'
              : formatThousands(s.days.last.active!),
          headlineLabel: 'aujourd’hui',
          children: [
            DayBars(
              key: const Key('stats.bars.active'),
              days: days,
              values: [for (final d in s.days) d.active],
              semanticLabel: 'Comptes actifs par jour sur 30 jours',
            ),
            const SizedBox(height: PrivioSpacing.s),
            Text(
              'Relevé chaque soir à 23 h 55 (et à chaque consultation pour aujourd’hui). '
              'Seul le nombre est gardé.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        _Card(
          id: 'new_accounts',
          title: 'Nouveaux comptes par jour',
          headline: formatThousands(s.sum((d) => d.newAccounts)),
          headlineLabel: 'sur 30 jours',
          children: [
            DayBars(
              key: const Key('stats.bars.new_accounts'),
              days: days,
              values: [for (final d in s.days) d.newAccounts],
              semanticLabel: 'Nouveaux comptes par jour sur 30 jours',
            ),
          ],
        ),
        _Card(
          id: 'requests',
          title: 'Demandes de connexion',
          headline: formatThousands(requests),
          headlineLabel: 'envoyées sur 30 jours',
          children: [
            _Line('Acceptées', s.sum((d) => d.accepted), _pct(s.sum((d) => d.accepted), requests)),
            _Line('Refusées', s.sum((d) => d.refused), _pct(s.sum((d) => d.refused), requests)),
          ],
        ),
        _Card(
          id: 'push',
          title: 'Notifications',
          headline: formatThousands(pushSent),
          headlineLabel: 'envoyées sur 30 jours',
          children: [_Line('En échec', pushFailed, _pct(pushFailed, pushSent + pushFailed))],
        ),
        _Card(
          id: 'versions',
          title: 'Versions de l’application',
          headline: formatThousands(s.versions.fold(0, (a, v) => a + v.$2)),
          headlineLabel: 'téléphones actifs sur 30 jours',
          children: [
            if (s.versions.isEmpty)
              Text('Aucun téléphone actif.', style: theme.textTheme.bodySmall)
            else
              for (final (version, n) in s.versions)
                _Line(
                  version,
                  n,
                  _pct(n, s.versions.fold(0, (a, v) => a + v.$2)),
                  key: Key('stats.version.$version'),
                ),
          ],
        ),
        // Lot 5.9 : rétention, langues, usage des fonctions ; export.
        _Extra(stats: s),
        const SizedBox(height: PrivioSpacing.m),
        ExpansionTile(
          key: const Key('stats.table'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Afficher le tableau jour par jour'),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: PrivioSpacing.l,
                headingTextStyle: theme.textTheme.labelSmall,
                dataTextStyle: theme.textTheme.bodySmall,
                columns: const [
                  DataColumn(label: Text('Jour')),
                  DataColumn(label: Text('Messages'), numeric: true),
                  DataColumn(label: Text('Actifs'), numeric: true),
                  DataColumn(label: Text('Nouveaux'), numeric: true),
                  DataColumn(label: Text('Demandes'), numeric: true),
                ],
                rows: [
                  for (final d in s.days.reversed)
                    DataRow(
                      cells: [
                        DataCell(Text(_dmy(d.day))),
                        DataCell(Text('${d.messages}')),
                        DataCell(Text(d.active == null ? '—' : '${d.active}')),
                        DataCell(Text('${d.newAccounts}')),
                        DataCell(Text('${d.requests}')),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.id,
    required this.title,
    required this.headline,
    required this.headlineLabel,
    required this.children,
  });

  final String id;
  final String title;
  final String headline;
  final String headlineLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: PrivioSpacing.l),
      child: Card(
        key: Key('stats.$id'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.xs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: headline,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '  $headlineLabel', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: PrivioSpacing.m),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Part d'un total : une barre fine d'une seule teinte (pas de couleur par catégorie).
class _Share extends StatelessWidget {
  const _Share(this.label, this.value, this.total);

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '${formatThousands(value)} · ${_pct(value, total)}',
                key: Key('stats.share.$label'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: f,
              minHeight: 6,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, this.share, {super.key});

  final String label;
  final int value;
  final String share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text('${formatThousands(value)} · $share', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Lot 5.9 : rétention par semaine d'inscription, langue des téléphones, usage des
/// fonctions sur 30 jours, export CSV (nombres seulement).
class _Extra extends ConsumerWidget {
  const _Extra({required this.stats});

  final ConsoleStats stats;

  Future<void> _export(BuildContext context, WidgetRef ref, StatsExtra extra) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).logExport(30);
      await ref.read(shareCsvProvider)(statsCsvName(DateTime.now()), statsCsv(stats, extra));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extra = ref.watch(statsExtraProvider(30)).value;
    if (extra == null) return const SizedBox.shrink();
    final langTotal = extra.languages.values.fold(0, (a, b) => a + b);
    final usage = <String, int>{
      for (final k in kUsageMetrics.keys) k: extra.usage.fold(0, (a, d) => a + (d.$2[k] ?? 0)),
    };
    final usageTotal = usage.values.fold(0, (a, b) => a + b);
    String rate(int r, int d) => d == 0 ? '—' : '${(r * 100 / d).round()} %';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          id: 'retention',
          title: 'Rétention',
          headline: extra.retention.isEmpty
              ? '—'
              : rate(
                  extra.retention.fold(0, (a, w) => a + w.r7),
                  extra.retention.fold(0, (a, w) => a + w.d7),
                ),
          headlineLabel: 'revenus au moins 7 jours après l’inscription',
          children: [
            Text(
              'Par semaine d’inscription\u202F: revenus après 1, 7 et 30 jours (parmi les comptes '
              'inscrits depuis assez longtemps).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.s),
            for (final w in extra.retention)
              Padding(
                key: Key('stats.retention.${_dmy(w.week)}'),
                padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text('Sem. du ${_dmy(w.week)} · ${w.signups}')),
                    Text('${rate(w.r1, w.d1)} · ${rate(w.r7, w.d7)} · ${rate(w.r30, w.d30)}'),
                  ],
                ),
              ),
          ],
        ),
        _Card(
          id: 'languages',
          title: 'Langue choisie',
          headline: formatThousands(langTotal),
          headlineLabel: 'téléphones actifs sur 30 jours',
          children: [
            for (final e in extra.languages.entries)
              _Share(kLanguages[e.key] ?? e.key, e.value, langTotal),
          ],
        ),
        _Card(
          id: 'usage',
          title: 'Usage des fonctions',
          headline: formatThousands(usageTotal),
          headlineLabel: 'utilisations sur 30 jours',
          children: [
            for (final e in usage.entries)
              if (e.value > 0) _Share(kUsageMetrics[e.key]!, e.value, usageTotal),
          ],
        ),
        const SizedBox(height: PrivioSpacing.m),
        OutlinedButton.icon(
          key: const Key('stats.export'),
          onPressed: () => _export(context, ref, extra),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Exporter en CSV (nombres seulement)'),
        ),
      ],
    );
  }
}
