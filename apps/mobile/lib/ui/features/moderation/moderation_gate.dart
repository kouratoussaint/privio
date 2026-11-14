import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';

/// Lot 5.3 : recouvre l'application quand le compte est suspendu (écran dédié, contestation
/// possible une fois) ; affiche une fois le message de l'équipe Privio après un avertissement.
class ModerationGate extends ConsumerWidget {
  const ModerationGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lot 5.4 : téléphone déconnecté par l'assistance → retour à la connexion, avec le motif.
    // Seulement pour un NOUVEAU signal : pendant un rechargement, la valeur précédente reste.
    ref.listen(realtimeSignalsProvider, (prev, next) {
      if (next case AsyncData(:final value)
          when value.event == 'disconnected' && !identical(value, prev?.value)) {
        unawaited(ref.read(sessionControllerProvider.notifier).deviceDisconnected());
      }
    });
    final status = ref.watch(moderationStatusProvider).value ?? ModerationStatus.none;
    final overlay = switch (status) {
      ModerationStatus(:final suspension?) => _SuspendedView(s: suspension),
      ModerationStatus(:final warning?) => _WarningView(w: warning),
      _ => null,
    };
    if (overlay == null) return child;
    return Stack(
      children: [
        // L'application reste dessous, inaccessible.
        ExcludeSemantics(child: IgnorePointer(child: child)),
        Positioned.fill(
          // Champ de texte hors du Navigator : il lui faut son propre Overlay.
          // Clé liée à la situation : l'écran se reconstruit quand elle change.
          child: Overlay(
            key: ValueKey(
              '${status.suspension?.id}/${status.suspension?.appealed}/'
              '${status.suspension?.appealDecision}/${status.warning?.id}',
            ),
            initialEntries: [OverlayEntry(builder: (_) => Material(child: overlay))],
          ),
        ),
      ],
    );
  }
}

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
}

class _SuspendedView extends ConsumerStatefulWidget {
  const _SuspendedView({required this.s});

  final SuspensionInfo s;

  @override
  ConsumerState<_SuspendedView> createState() => _SuspendedViewState();
}

class _SuspendedViewState extends ConsumerState<_SuspendedView> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _appeal() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).submitAppeal(widget.s.id, _text.text.trim());
      ref.invalidate(moderationStatusProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.s;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          key: const Key('moderation.suspended'),
          padding: const EdgeInsets.all(PrivioSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.block, size: 56, color: theme.colorScheme.error),
                const SizedBox(height: PrivioSpacing.l),
                Text(
                  'Compte suspendu',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  s.until == null ? 'Sans limite de durée' : 'Jusqu’au ${_when(s.until!)}',
                  key: const Key('moderation.until'),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PrivioSpacing.l),
                Text(
                  'L’équipe Privio a suspendu votre compte à la suite de signalements '
                  '(motif : ${reasonLabel(s.reason).toLowerCase()}). Pendant la suspension, '
                  'vous ne pouvez ni lire ni envoyer de messages. Vos messages déjà envoyés '
                  's’effacent normalement.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: PrivioSpacing.xl),
                if (!s.appealed) ...[
                  Text('Contester', style: theme.textTheme.titleSmall),
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(
                    'Expliquez pourquoi la sanction vous semble injustifiée. Une seule '
                    'contestation est possible.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: PrivioSpacing.s),
                  TextField(
                    key: const Key('moderation.appeal'),
                    controller: _text,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: 'Votre explication', errorText: _error),
                  ),
                  FilledButton(
                    key: const Key('moderation.appeal.send'),
                    onPressed: _sending || _text.text.trim().length < 3 ? null : _appeal,
                    child: const Text('Envoyer ma contestation'),
                  ),
                ] else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.l),
                      child: Text(
                        s.appealDecision == 'upheld'
                            ? 'Contestation examinée : la suspension est maintenue.'
                            : 'Contestation envoyée : l’équipe Privio l’examine.',
                        key: const Key('moderation.appeal.state'),
                      ),
                    ),
                  ),
                const SizedBox(height: PrivioSpacing.xl),
                TextButton(
                  key: const Key('moderation.signout'),
                  onPressed: () =>
                      unawaited(ref.read(sessionControllerProvider.notifier).signOut()),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningView extends ConsumerStatefulWidget {
  const _WarningView({required this.w});

  final WarningInfo w;

  @override
  ConsumerState<_WarningView> createState() => _WarningViewState();
}

class _WarningViewState extends ConsumerState<_WarningView> {
  bool _busy = false;

  Future<void> _ack() async {
    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).acknowledgeWarning(widget.w.id);
    } on Object {
      // Réessayé à la prochaine ouverture.
    }
    ref.invalidate(moderationStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.xl),
          child: Card(
            key: const Key('moderation.warning'),
            child: Padding(
              padding: const EdgeInsets.all(PrivioSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.report_outlined, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: PrivioSpacing.m),
                  Text('Message de l’équipe Privio', style: theme.textTheme.titleLarge),
                  const SizedBox(height: PrivioSpacing.m),
                  Text(
                    'Votre compte a fait l’objet de signalements '
                    '(motif : ${reasonLabel(widget.w.reason).toLowerCase()}). Merci de '
                    'respecter les règles de Privio : pas de spam, de harcèlement, de menaces '
                    'ni de contenu inapproprié. En cas de récidive, votre compte pourra être '
                    'suspendu.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: PrivioSpacing.xl),
                  FilledButton(
                    key: const Key('moderation.warning.ack'),
                    onPressed: _busy ? null : _ack,
                    child: const Text('J’ai compris'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
