import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/search_text.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/messaging_providers.dart';

/// Lot 8.4c — alerte anti-usurpation : un compte qui N'EST PAS mon contact porte le nom
/// (ou presque) d'un de mes contacts. Calcul sur ce téléphone, rien n'est envoyé.
ConversationSummary? lookAlikeContact(
  List<ConversationSummary> conversations, {
  required String userId,
  required String name,
}) {
  final contacts = [
    for (final c in conversations)
      if (!c.isGroup && c.peerId != null && !c.peerDeleted) c,
  ];
  // Déjà mon contact : pas d'alerte.
  if (contacts.any((c) => c.peerId == userId)) return null;
  for (final c in contacts) {
    if (namesLookAlike(c.title, name)) return c;
  }
  return null;
}

class ImpersonationWarning extends ConsumerWidget {
  const ImpersonationWarning({
    super.key,
    required this.userId,
    required this.name,
    required this.handle,
  });

  final String userId;
  final String name;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
    final match = lookAlikeContact(list, userId: userId, name: name);
    if (match == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Container(
      key: const Key('impersonation.warning'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
      padding: const EdgeInsets.all(PrivioSpacing.m),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        border: Border.all(color: error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: error, size: 20),
          const SizedBox(width: PrivioSpacing.s),
          Expanded(
            child: Text(
              L.t.impersonationWarning(match.title, match.peerHandle ?? '', handle),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
