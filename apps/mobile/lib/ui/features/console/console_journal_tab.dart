import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import 'console_accounts_tab.dart' show ConsolePager;

/// Onglet « Journal » (lot 5.2) : consultations et changements, du plus récent au plus
/// ancien. Conservé `admin_audit_retention_days` jours (90 par défaut).
/// Lot 5.5 : filtres par type d'action et par période, pages numérotées.
class ConsoleJournalTab extends ConsumerStatefulWidget {
  const ConsoleJournalTab({super.key});

  @override
  ConsumerState<ConsoleJournalTab> createState() => _ConsoleJournalTabState();
}

const _slate = Color(0xFF5A6B85);

class _ConsoleJournalTabState extends ConsumerState<ConsoleJournalTab> {
  String? _type;
  int? _days;
  int _page = 1;

  static const _periods = <int?, String>{null: 'Tout', 1: '24 h', 7: '7 jours', 30: '30 jours'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = (_type, _days, _page);
    final journal = ref.watch(consoleJournalPageProvider(query));
    // Unités des réglages, pour afficher « 5 → 3 » proprement.
    final units = {
      for (final p in ref.watch(consolePoliciesProvider).value ?? const <ConsolePolicy>[])
        p.key: p.unit,
    };
    Widget chip(String key, String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: PrivioSpacing.s),
      child: ChoiceChip(
        key: Key(key),
        label: Text(label),
        selected: selected,
        selectedColor: _slate.withValues(alpha: 0.18),
        onSelected: (_) => onTap(),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            key: const Key('journal.types'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.m,
              PrivioSpacing.s,
              PrivioSpacing.m,
              0,
            ),
            children: [
              chip(
                'journal.type.all',
                'Tout',
                _type == null,
                () => setState(() {
                  _type = null;
                  _page = 1;
                }),
              ),
              for (final e in kJournalTypes.entries)
                chip(
                  'journal.type.${e.key}',
                  e.value,
                  _type == e.key,
                  () => setState(() {
                    _type = e.key;
                    _page = 1;
                  }),
                ),
            ],
          ),
        ),
        // Période : défile si l'écran est étroit.
        SingleChildScrollView(
          key: const Key('journal.periods'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, 0, PrivioSpacing.m, 0),
          child: Row(
            children: [
              Icon(Icons.date_range_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              for (final e in _periods.entries)
                chip(
                  'journal.days.${e.key ?? 'all'}',
                  e.value,
                  _days == e.key,
                  () => setState(() {
                    _days = e.key;
                    _page = 1;
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (journal) {
            AsyncData(:final value) => RefreshIndicator(
              onRefresh: () => ref.refresh(consoleJournalPageProvider(query).future),
              child: value.rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 60),
                        EmptyView(
                          icon: Icons.history,
                          title: 'Rien à afficher',
                          message: 'Aucune action de ce type sur cette période.',
                        ),
                      ],
                    )
                  : ListView(
                      key: const Key('console.journal'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        PrivioSpacing.m,
                        PrivioSpacing.s,
                        PrivioSpacing.m,
                        PrivioSpacing.l,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, PrivioSpacing.s),
                          child: Text(
                            '${value.total} action${value.total > 1 ? 's' : ''}',
                            key: const Key('journal.count'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        SettingsCard(
                          children: [
                            for (final (i, e) in value.rows.indexed) ...[
                              if (i > 0) const SettingsDivider(),
                              _EntryTile(e: e, unit: units[e.key] ?? 'nb'),
                            ],
                          ],
                        ),
                      ],
                    ),
            ),
            AsyncError(:final error) => ErrorView(
              message: toAppFailure(error).message,
              onRetry: () => ref.invalidate(consoleJournalPageProvider(query)),
            ),
            _ => const LoadingView(),
          },
        ),
        if (journal.value case final v?)
          ConsolePager(
            page: v.page,
            pages: v.pages,
            color: _slate,
            onPage: (p) => setState(() => _page = p),
          ),
      ],
    );
  }
}

String _who(JournalEntry e) {
  final h = e.detail['handle'] as String?;
  final g = e.detail['group'] as String?;
  if (h != null) return '@$h';
  if (g != null) return 'groupe «\u202F$g\u202F»';
  return 'dossier';
}

/// Lot 5.6 : filtre de la liste des comptes (« , nouveaux (7 j) »), rien pour « Tous ».
String _filter(JournalEntry e) {
  final f = e.detail['filter'];
  if (f == null || f == 'all') return '';
  return ', ${(kAccountFilters[f] ?? '$f').toLowerCase()}';
}

String journalText(JournalEntry e, String unit) => switch (e.action) {
  'dashboard' => 'Consultation du tableau de bord',
  'stats' => 'Consultation des statistiques',
  // Lot 5.7
  'health' => 'Consultation de la santé du service',
  'health_push' => 'Notification de test envoyée',
  'health_relay' => 'Test du relais des appels',
  'account_list' => 'Liste des comptes consultée (page ${e.detail['page'] ?? 1}${_filter(e)})',
  'evidence' => 'Lecture d’une copie signalée (${_who(e)})',
  'account' => 'Fiche de ${_who(e)} consultée',
  'account_search' =>
    e.detail['by'] == 'phone' ? 'Recherche de compte par numéro' : 'Recherche de compte',
  'disconnect' => 'Téléphone de ${_who(e)} déconnecté',
  'two_step_reset' => 'Vérification en deux étapes de ${_who(e)} réinitialisée',
  'reply' => 'Réponse à la demande d’assistance de ${_who(e)}',
  // Lot 5.6
  'avatar_remove' => 'Photo de profil de ${_who(e)} retirée',
  'handle_reset' =>
    'Nouvel identifiant imposé à @${e.detail['old_handle'] ?? '—'} (provisoire : ${_who(e)})',
  'reserved_handle' =>
    e.detail['reserved'] == false
        ? 'Identifiant ${_who(e)} libéré'
        : 'Identifiant ${_who(e)} réservé',
  'lift' => 'Réactivation de ${_who(e)}',
  'appeal' =>
    'Contestation de ${_who(e)}\u202F: ${e.detail['lift'] == true ? 'suspension levée' : 'suspension maintenue'}',
  'moderation' => switch (e.detail['action']) {
    'dismiss' => 'Dossier classé sans suite (${_who(e)})',
    'warn' => 'Avertissement à ${_who(e)}',
    'suspend' =>
      'Suspension de ${_who(e)} '
          '(${switch (e.detail['days']) {
            1 => '24\u00A0h',
            7 => '7\u00A0jours',
            30 => '30\u00A0jours',
            _ => 'sans limite',
          }})',
    'delete_message' => 'Message supprimé (${_who(e)})',
    'close_group' => 'Fermeture du ${_who(e)}',
    _ => 'Décision de modération',
  },
  'policy' =>
    'Réglage « ${e.label ?? e.key} » : '
        '${e.before == null ? 'défaut' : formatPolicyValue(unit, e.before)} → '
        '${formatPolicyValue(unit, e.after)}',
  _ => e.action,
};

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.e, required this.unit});

  final JournalEntry e;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final l = e.at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return ListTile(
      key: Key('journal.${e.id}'),
      leading: Icon(switch (e.action) {
        'policy' => Icons.tune,
        'stats' => Icons.bar_chart,
        'moderation' || 'lift' || 'appeal' => Icons.gavel_outlined,
        'evidence' => Icons.visibility,
        'account' || 'account_search' || 'account_list' => Icons.person_search_outlined,
        'disconnect' => Icons.phonelink_erase,
        'two_step_reset' => Icons.lock_reset,
        'reply' => Icons.support_agent,
        'avatar_remove' => Icons.hide_image_outlined,
        'handle_reset' || 'reserved_handle' => Icons.alternate_email,
        _ => Icons.visibility_outlined,
      }),
      title: Text(journalText(e, unit)),
      subtitle: Text(
        'Le ${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}',
      ),
    );
  }
}
