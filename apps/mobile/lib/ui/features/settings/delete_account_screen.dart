import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/settings_card.dart';

/// Suppression définitive du compte (AUTH-006). Confirmation par saisie de « SUPPRIMER ».
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  static const confirmationWord = 'SUPPRIMER';

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(messagingApiProvider).deleteMyAccount();
      await ref.read(sessionControllerProvider.notifier).onAccountDeleted();
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _confirm.text.trim().toUpperCase() == DeleteAccountScreen.confirmationWord;
    const effects = [
      'Votre profil, votre identifiant et votre numéro sont supprimés.',
      'Vos messages envoyés sont supprimés, y compris chez les personnes qui les ont reçus.',
      'Vos blocages et vos discussions disparaissent.',
      'Les messages enregistrés sur ce téléphone sont détruits.',
      'Un signalement vous concernant peut être conservé jusqu’à 90 jours pour la modération.',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: SettingsListView(
        children: [
          SettingsCard(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              Icon(Icons.warning_amber_rounded, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: PrivioSpacing.l),
              Text('Cette action est définitive.', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.m),
              for (final e in effects)
                Padding(
                  padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(e, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.l),
          TextField(
            key: const Key('delete.confirm'),
            controller: _confirm,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Pour confirmer, écrivez SUPPRIMER'),
          ),
          if (_error != null) ...[
            const SizedBox(height: PrivioSpacing.s),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: PrivioSpacing.l),
          FilledButton(
            key: const Key('delete.submit'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: ready && !_busy ? _delete : null,
            child: Text(_busy ? 'Suppression…' : 'Supprimer définitivement mon compte'),
          ),
        ],
      ),
    );
  }
}
