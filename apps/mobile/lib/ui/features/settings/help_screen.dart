import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/realtime_service.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../core/widgets/settings_card.dart';

/// Aide : questions fréquentes et contact de l'assistance (lot 2.5).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static const faq = [
    (
      'Quand mes messages sont-ils effacés\u202F?',
      'Chaque message s’efface automatiquement après la durée de la discussion (72 h par '
          'défaut, ou moins si vous l’avez réglée), qu’il ait été lu ou non. Il disparaît du '
          'serveur et de votre téléphone, même sans connexion.',
    ),
    (
      'Comment changer la durée des messages\u202F?',
      'Dans une discussion, touchez la minuterie en haut, ou la carte «\u202FLes messages de cette '
          'discussion s’effacent…\u202F». Pour un seul message, touchez la minuterie dans la zone de '
          'saisie. Une durée ne dépasse jamais 72 h.',
    ),
    (
      'Mes messages sont-ils chiffrés\u202F?',
      'Ils sont protégés pendant leur transport (connexion chiffrée) et enregistrés chiffrés '
          'sur votre téléphone. Sur les serveurs de Privio, ils restent techniquement '
          'accessibles à Privio jusqu’à leur expiration, puis sont définitivement effacés.',
    ),
    (
      'Peut-on faire une capture d’écran\u202F?',
      'Non, les captures d’écran sont bloquées dans Privio sur Android. Une photo prise avec '
          'un autre appareil reste toutefois possible.',
    ),
    (
      'Pourquoi ai-je été déconnecté\u202F?',
      'Privio ne s’ouvre que sur un seul téléphone à la fois. Une connexion sur un autre '
          'appareil déconnecte le précédent et efface les messages qui y étaient enregistrés.',
    ),
    (
      'Que se passe-t-il sans réseau\u202F?',
      'Les messages déjà reçus restent lisibles. Ceux que vous écrivez attendent et partent '
          'seuls dès le retour du réseau.',
    ),
    (
      'Comment bloquer ou signaler quelqu’un\u202F?',
      'Touchez le nom du contact en haut de la discussion, puis «\u202FBloquer\u202F» ou «\u202FSignaler\u202F». '
          'Pour signaler un message précis, faites un appui long sur ce message.',
    ),
    (
      'Comment écrire à quelqu’un pour la première fois\u202F?',
      'Touchez le crayon, cherchez son identifiant (ou son numéro), puis «\u202FEnvoyer une demande\u202F», '
          'avec un petit mot si vous voulez. Dès qu’elle accepte, la discussion s’ouvre chez vous '
          'deux. Sans réponse, la demande expire après 24 h\u202F; après un refus, attendez quelques '
          'minutes avant de redemander (3 fois par jour au plus). Paramètres, Confidentialité\u202F: '
          'vous pouvez refuser toute demande.',
    ),
    (
      'Pourquoi ne puis-je pas trouver quelqu’un\u202F?',
      'La recherche demande l’identifiant exact (ex. @awa_s). Par numéro, on ne trouve que '
          'les personnes qui ont activé «\u202FMe trouver par mon numéro\u202F».',
    ),
    (
      'Combien de photos puis-je envoyer\u202F?',
      'Jusqu’à 5 photos par jour, groupes compris\u202F; le compteur repart à minuit. Une photo '
          's’efface comme les messages et ne peut pas être enregistrée dans la galerie. Dans la '
          'galerie, vous pouvez en choisir plusieurs à la fois.',
    ),
    (
      'Combien de temps dure un message vocal\u202F?',
      '30 secondes au plus. Touchez le micro pour enregistrer sans le tenir, ou maintenez-le\u202F: '
          'glissez vers la gauche pour annuler, vers le haut pour lâcher le doigt. Sans le '
          'doigt, le bouton pause permet de reprendre plus tard\u202F; les pauses ne comptent pas.',
    ),
    (
      'Comment créer un groupe\u202F?',
      'Dans l’onglet Groupes, touchez «\u202FNouveau groupe\u202F», donnez-lui un nom et choisissez les '
          'personnes à inviter (25 membres au plus). Chacune doit accepter l’invitation.',
    ),
    (
      'Comment vider une discussion\u202F?',
      'Ouvrez le menu en haut à droite de la discussion, puis «\u202FVider la discussion\u202F». '
          '«\u202FSeulement chez moi\u202F» vide votre copie. «\u202FPour nous deux\u202F» envoie une demande\u202F: si '
          'la personne accepte dans les 24 h, tout disparaît des deux côtés, sans trace. Dans un '
          'groupe, les administrateurs peuvent vider pour tous.',
    ),
    (
      'Que se passe-t-il si j’oublie mon code\u202F?',
      'Touchez «\u202FCode oublié\u202F?\u202F» sur l’écran de verrouillage. Il faudra vous déconnecter, ce '
          'qui efface les messages gardés sur ce téléphone, puis vous reconnecter par SMS.',
    ),
    (
      'Qui voit que je suis en ligne\u202F?',
      'Par défaut, vos contacts. Changez-le dans Paramètres, Confidentialité, «\u202FEn ligne et vu '
          'à\u202F». Ce choix ne vous empêche pas de voir celui des autres.',
    ),
    (
      'Comment économiser mes données\u202F?',
      'Dans Paramètres, Stockage et données, choisissez quand les photos se téléchargent\u202F: '
          'toujours, en Wi-Fi seulement ou jamais (vous touchez alors la photo pour la '
          'télécharger). Le même écran indique les données utilisées.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et assistance')),
      body: SettingsListView(
        children: [
          const SettingsSectionTitle('Questions fréquentes', first: true),
          SettingsCard(
            children: [
              for (final (q, a) in faq)
                ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(q, style: theme.textTheme.bodyLarge),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.l,
                    0,
                    PrivioSpacing.l,
                    PrivioSpacing.l,
                  ),
                  children: [Text(a, style: theme.textTheme.bodyMedium)],
                ),
            ],
          ),
          const SettingsSectionTitle('Assistance'),
          SettingsCard(
            children: [
              const _ConnectionDiagnostic(),
              ListTile(
                key: const Key('help.contact'),
                leading: const Icon(Icons.support_agent),
                title: const Text('Contacter l’assistance'),
                subtitle: const Text(
                  'Un problème, une question\u202F? Décrivez-le en quelques mots.',
                ),
                onTap: () => _contact(context, ref),
              ),
              // Lot 5.4 : les demandes envoyées et les réponses de l'équipe Privio.
              ListTile(
                key: const Key('help.my_requests'),
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Mes demandes'),
                subtitle: const Text('Vos messages à l’assistance et nos réponses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.mySupport),
              ),
            ],
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
      ref.invalidate(mySupportRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Merci, votre message a été transmis à l’assistance. La réponse arrivera dans '
              '«\u202FMes demandes\u202F».',
            ),
          ),
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

/// Diagnostic de connexion (déplacé des Paramètres au lot 4.4) : état de la
/// réception instantanée des messages.
class _ConnectionDiagnostic extends ConsumerWidget {
  const _ConnectionDiagnostic();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<RealtimeStatus>(
      valueListenable: ref.watch(realtimeStatusProvider).status,
      builder: (_, status, _) {
        final ok = status.state == RealtimeState.connected;
        final color = ok ? p.success : (status.state == RealtimeState.error ? p.warn : secondary);
        return ListTile(
          key: const Key('settings.realtime'),
          leading: const Icon(Icons.sync),
          title: const Text('Diagnostic de connexion'),
          subtitle: const Text('Réception des messages en direct'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  status.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
