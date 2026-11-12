import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/messaging_providers.dart';

/// Aide : questions fréquentes et contact de l'assistance (lot 2.5).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static const faq = [
    (
      'Quand mes messages sont-ils effacés ?',
      'Chaque message s’efface automatiquement après la durée de la discussion (72 h par '
          'défaut, ou moins si vous l’avez réglée), qu’il ait été lu ou non. Il disparaît du '
          'serveur et de votre téléphone, même sans connexion.',
    ),
    (
      'Comment changer la durée des messages ?',
      'Dans une discussion, touchez la minuterie en haut, ou la carte « Les messages de cette '
          'discussion s’effacent… ». Pour un seul message, touchez la minuterie dans la zone de '
          'saisie. Une durée ne dépasse jamais 72 h.',
    ),
    (
      'Mes messages sont-ils chiffrés ?',
      'Ils sont protégés pendant leur transport (connexion chiffrée) et enregistrés chiffrés '
          'sur votre téléphone. Sur les serveurs de Privio, ils restent techniquement '
          'accessibles à Privio jusqu’à leur expiration, puis sont définitivement effacés.',
    ),
    (
      'Peut-on faire une capture d’écran ?',
      'Non, les captures d’écran sont bloquées dans Privio sur Android. Une photo prise avec '
          'un autre appareil reste toutefois possible.',
    ),
    (
      'Pourquoi ai-je été déconnecté ?',
      'Privio ne s’ouvre que sur un seul téléphone à la fois. Une connexion sur un autre '
          'appareil déconnecte le précédent et efface les messages qui y étaient enregistrés.',
    ),
    (
      'Que se passe-t-il sans réseau ?',
      'Les messages déjà reçus restent lisibles. Ceux que vous écrivez attendent et partent '
          'seuls dès le retour du réseau.',
    ),
    (
      'Comment bloquer ou signaler quelqu’un ?',
      'Touchez le nom du contact en haut de la discussion, puis « Bloquer » ou « Signaler ». '
          'Pour signaler un message précis, faites un appui long sur ce message.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et assistance')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
        children: [
          for (final (q, a) in faq)
            ExpansionTile(
              title: Text(q, style: theme.textTheme.bodyLarge),
              childrenPadding: const EdgeInsets.fromLTRB(
                PrivioSpacing.l,
                0,
                PrivioSpacing.l,
                PrivioSpacing.l,
              ),
              children: [Text(a, style: theme.textTheme.bodyMedium)],
            ),
          const Divider(),
          ListTile(
            key: const Key('help.contact'),
            leading: const Icon(Icons.support_agent),
            title: const Text('Contacter l’assistance'),
            subtitle: const Text('Un problème, une question ? Décrivez-le en quelques mots.'),
            onTap: () => _contact(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _contact(BuildContext context, WidgetRef ref) async {
    final text =
        (await showDialog<String>(
          context: context,
          builder: (_) => const _SupportDialog(),
        ))?.trim() ??
        '';
    if (text.isEmpty || !context.mounted) return;
    try {
      await ref.read(messagingApiProvider).report(reason: 'support', details: text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci, votre message a été transmis à l’assistance.')),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }
}

/// Fenêtre « Contacter l'assistance » : elle possède et libère elle-même son champ
/// (libérer le champ pendant l'animation de fermeture ferait planter l'application).
class _SupportDialog extends StatefulWidget {
  const _SupportDialog();

  @override
  State<_SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<_SupportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Contacter l’assistance'),
    content: TextField(
      key: const Key('help.message'),
      controller: _controller,
      autofocus: true,
      maxLength: 1000,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        hintText: 'Décrivez votre problème (sans données sensibles)',
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(
        key: const Key('help.send'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Envoyer'),
      ),
    ],
  );
}
