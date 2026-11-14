import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/moderation_providers.dart';
import '../../core/widgets/state_views.dart';

/// Aide → Mes demandes (lot 5.4) : messages envoyés à l'assistance (90 jours) et réponses.
class MySupportScreen extends ConsumerWidget {
  const MySupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(mySupportRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes demandes')),
      body: switch (requests) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.forum_outlined,
          title: 'Aucune demande',
          message: 'Vos messages à l’assistance et nos réponses apparaîtront ici.',
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(mySupportRequestsProvider.future),
          child: ListView(
            key: const Key('support.list'),
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              for (final r in value) _RequestCard(r: r),
              const SizedBox(height: PrivioSpacing.l),
              Text(
                'Les demandes et les réponses sont gardées 90 jours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(mySupportRequestsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.r});

  final SupportRequest r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Card(
      key: Key('support.${r.id}'),
      margin: const EdgeInsets.only(bottom: PrivioSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Envoyée le ${_when(r.createdAt)}', style: theme.textTheme.bodySmall),
                ),
                Chip(
                  key: Key('support.state.${r.id}'),
                  label: Text(r.answered ? 'Répondue' : 'Envoyée'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(r.details ?? ''),
            if (r.answered) ...[
              const SizedBox(height: PrivioSpacing.m),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(PrivioSpacing.m),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(PrivioRadius.medium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réponse de l’équipe Privio',
                      style: theme.textTheme.labelLarge?.copyWith(color: p.accentText),
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(r.reply!, key: Key('support.reply.${r.id}')),
                    if (r.repliedAt != null)
                      Text('Le ${_when(r.repliedAt!)}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: PrivioSpacing.s),
                child: Text(
                  'L’équipe Privio vous répondra ici ; vous recevrez une notification.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
