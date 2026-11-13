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

String journalText(JournalEntry e, String unit) => switch (e.action) {
  'dashboard' => 'Consultation du tableau de bord',
  'stats' => 'Consultation des statistiques',
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
        _ => Icons.visibility_outlined,
      }),
      title: Text(journalText(e, unit)),
      subtitle: Text(
        'Le ${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}',
      ),
    );
  }
}
