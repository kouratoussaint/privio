import '../../../l10n/l10n.dart';

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
import '../../core/motion/illustrations.dart';
import 'what_privio_keeps_screen.dart';

/// Aide : questions fréquentes et contact de l'assistance (lot 2.5).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static List<(String, String)> get faq => [
    (L.t.quandMesMessagesSontIls, L.t.chaqueMessageEffaceAutomatiquementApres),
    (L.t.commentChangerDureeMessages, L.t.dansDiscussionTouchezMinuterieHaut),
    (L.t.mesMessagesSontIlsChiffres, L.t.ilsSontProtegesPendantLeur),
    (L.t.peutOnFaireCaptureEcran, L.t.nonCapturesEcranSontBloquees),
    (L.t.pourquoiAiJeEteDeconnecte, L.t.privioNeOuvreQueSur),
    (L.t.queSePasseTIl, L.t.messagesDejaRecusRestentLisibles),
    (L.t.commentBloquerOuSignalerQuelqu, L.t.touchezNomContactHautDiscussion),
    (L.t.commentEcrireQuelquPourPremiere, L.t.touchezCrayonCherchezSonIdentifiant),
    (L.t.pourquoiNePuisJePas, L.t.rechercheDemandeIdentifiantExactEx),
    (L.t.combienPhotosPuisJeEnvoyer, L.t.jusqu5PhotosParJour),
    (L.t.combienTempsDureMessageVocal, L.t.n30SecondesPlusTouchezMicro),
    (L.t.commentCreerGroupe, L.t.dansOngletGroupesTouchezNouveau),
    (L.t.commentViderDiscussion, L.t.ouvrezMenuHautDroiteDiscussion),
    (L.t.queSePasseTIl2, L.t.touchezCodeOublieSurEcran),
    (L.t.quiVoitQueJeSuis, L.t.parDefautVosContactsChangez),
    (L.t.commentEconomiserMesDonnees, L.t.dansParametresStockageDonneesChoisissez),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L.t.aideAssistance)),
      body: SettingsListView(
        children: [
          // Lot 7.2b2 : en-tête illustré.
          const Center(child: FloatingIcon(icon: Icons.support_agent, size: 40)),
          // Lot 8.4c : ce que Privio garde.
          const SizedBox(height: PrivioSpacing.l),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('help.keeps'),
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(L.t.keepTitle),
                subtitle: Text(L.t.keepEntrySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(WhatPrivioKeepsScreen.route()),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.questionsFrequentes),
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
          SettingsSectionTitle(L.t.assistance),
          SettingsCard(
            children: [
              const _ConnectionDiagnostic(),
              ListTile(
                key: const Key('help.contact'),
                leading: const Icon(Icons.support_agent),
                title: Text(L.t.contacterAssistance),
                subtitle: Text(L.t.problemeQuestionDecrivezQuelquesMots),
                onTap: () => _contact(context, ref),
              ),
              // Lot 5.4 : les demandes envoyées et les réponses de l'équipe Privio.
              ListTile(
                key: const Key('help.my_requests'),
                leading: const Icon(Icons.forum_outlined),
                title: Text(L.t.mesDemandes),
                subtitle: Text(L.t.vosMessagesAssistanceNosReponses),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L.t.merciVotreMessageEteTransmis)));
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
    title: Text(L.t.contacterAssistance),
    content: TextField(
      key: const Key('help.message'),
      controller: _controller,
      autofocus: true,
      maxLength: 1000,
      minLines: 3,
      maxLines: 6,
      decoration: InputDecoration(hintText: L.t.decrivezVotreProblemeSansDonnees),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t.annuler)),
      FilledButton(
        key: const Key('help.send'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(L.t.envoyer),
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
          title: Text(L.t.diagnosticConnexion),
          subtitle: Text(L.t.receptionMessagesDirect),
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
