import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/state_views.dart';

/// Onglet « Journal » (lot 5.2) : consultations et changements de réglages, du plus récent
/// au plus ancien. Conservé `admin_audit_retention_days` jours (90 par défaut).
class ConsoleJournalTab extends ConsumerWidget {
  const ConsoleJournalTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(consoleJournalProvider);
    // Unités des réglages, pour afficher « 5 → 3 » proprement.
    final units = {
      for (final p in ref.watch(consolePoliciesProvider).value ?? const <ConsolePolicy>[])
        p.key: p.unit,
    };
    return switch (journal) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consoleJournalProvider.future),
        child: value.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  EmptyView(
                    icon: Icons.history,
                    title: 'Journal vide',
                    message: 'Les consultations et les changements apparaîtront ici.',
                  ),
                ],
              )
            : ListView.separated(
                key: const Key('console.journal'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
                itemCount: value.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _EntryTile(e: value[i], unit: units[value[i].key] ?? 'nb'),
              ),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleJournalProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

String _who(JournalEntry e) {
  final h = e.detail['handle'] as String?;
  final g = e.detail['group'] as String?;
  if (h != null) return '@$h';
  if (g != null) return 'groupe «\u202F$g\u202F»';
  return 'dossier';
}

String journalText(JournalEntry e, String unit) => switch (e.action) {
  'dashboard' => 'Consultation du tableau de bord',
  'stats' => 'Consultation des statistiques',
  'evidence' => 'Lecture d’une copie signalée (${_who(e)})',
  'account' => 'Fiche de ${_who(e)} consultée',
  'account_search' =>
    e.detail['by'] == 'phone' ? 'Recherche de compte par numéro' : 'Recherche de compte',
  'disconnect' => 'Téléphone de ${_who(e)} déconnecté',
  'two_step_reset' => 'Vérification en deux étapes de ${_who(e)} réinitialisée',
  'reply' => 'Réponse à la demande d’assistance de ${_who(e)}',
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
        'account' || 'account_search' => Icons.person_search_outlined,
        'disconnect' => Icons.phonelink_erase,
        'two_step_reset' => Icons.lock_reset,
        'reply' => Icons.support_agent,
        _ => Icons.visibility_outlined,
      }),
      title: Text(journalText(e, unit)),
      subtitle: Text(
        'Le ${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}',
      ),
    );
  }
}
