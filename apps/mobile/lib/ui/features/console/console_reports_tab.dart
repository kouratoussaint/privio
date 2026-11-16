import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/moderation.dart';
import '../../../state/console_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/moderation_providers.dart';
import '../../../state/providers.dart';
import '../../core/widgets/settings_card.dart';
import 'console_screen.dart' show ConsoleBackHandler;
import '../../core/widgets/state_views.dart';

/// Onglet « Signalements » de la console (lot 5.3) : files, dossiers, décisions,
/// contestations. Les signalements visant la même cible forment un seul dossier.
class ConsoleReportsTab extends ConsumerStatefulWidget {
  const ConsoleReportsTab({super.key});

  @override
  ConsumerState<ConsoleReportsTab> createState() => _ConsoleReportsTabState();
}

class _ConsoleReportsTabState extends ConsumerState<ConsoleReportsTab> with ConsoleBackHandler {
  @override
  bool handleBack() {
    if (_dossier == null) return false;
    setState(() => _dossier = null);
    return true;
  }

  /// open, reviewing, closed, appeals.
  String _queue = 'open';
  String? _kind;
  String? _reason;
  List<ModerationReport>? _dossier;

  @override
  Widget build(BuildContext context) {
    final dossier = _dossier;
    if (dossier != null) {
      return DossierView(reports: dossier, onBack: () => setState(() => _dossier = null));
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.m, PrivioSpacing.m, 0),
          child: Wrap(
            key: const Key('reports.queue'),
            spacing: PrivioSpacing.s,
            runSpacing: PrivioSpacing.xs,
            children: [
              for (final (q, label) in const [
                ('open', 'À traiter'),
                ('reviewing', 'En cours'),
                ('closed', 'Traités'),
                ('appeals', 'Contestations'),
              ])
                consoleChip(
                  context,
                  key: Key('reports.queue.$q'),
                  label: label,
                  selected: _queue == q,
                  onTap: () => setState(() => _queue = q),
                ),
            ],
          ),
        ),
        if (_queue != 'appeals')
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: PrivioSpacing.m,
              vertical: PrivioSpacing.s,
            ),
            child: Row(
              children: [
                for (final (k, label) in const [
                  ('account', 'Comptes'),
                  ('message', 'Messages'),
                  ('group', 'Groupes'),
                  ('support', 'Assistance'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: PrivioSpacing.s),
                    child: consoleChip(
                      context,
                      key: Key('reports.kind.$k'),
                      label: label,
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = _kind == k ? null : k),
                    ),
                  ),
                PopupMenuButton<String?>(
                  key: const Key('reports.reason'),
                  tooltip: 'Filtrer par motif',
                  initialValue: _reason,
                  onSelected: (v) => setState(() => _reason = v == '' ? null : v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('Tous les motifs')),
                    for (final e in kReportReasons.entries)
                      if (e.key != 'support') PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(_reason == null ? 'Motif' : reasonLabel(_reason)),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _queue == 'appeals'
              ? const _AppealsList()
              : _DossierList(
                  status: _queue,
                  kind: _kind,
                  reason: _reason,
                  onOpen: (d) => setState(() => _dossier = d),
                ),
        ),
        if (_queue == 'closed')
          Padding(
            padding: const EdgeInsets.all(PrivioSpacing.s),
            child: Text('Signalements gardés 90 jours.', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Puce aux couleurs de Privio (violet quand elle est choisie), comme le sélecteur de durée.
Widget consoleChip(
  BuildContext context, {
  required Key key,
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final fill = dark ? PrivioColors.lilac : PrivioColors.purple;
  final onFill = dark ? PrivioColors.navy : Colors.white;
  return ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    selectedColor: fill,
    labelStyle: selected ? TextStyle(color: onFill, fontWeight: FontWeight.w600) : null,
    onSelected: (_) => onTap(),
  );
}

String _date(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} à ${two(l.hour)}:${two(l.minute)}';
}

String _target(ModerationReport r) => switch (r.kind) {
  'support' => 'Demande d’assistance',
  'group' => 'Groupe « ${r.groupTitle ?? 'sans nom'} »',
  _ =>
    r.reportedHandle == null
        ? 'Compte supprimé'
        : '@${r.reportedHandle}${r.reportedName == null ? '' : ' · ${r.reportedName}'}',
};

String _suspension(ModerationReport r) => r.suspendedUntil == null
    ? 'Suspendu sans limite'
    : 'Suspendu jusqu’au ${_date(r.suspendedUntil!)}';

class _DossierList extends ConsumerWidget {
  const _DossierList({
    required this.status,
    required this.kind,
    required this.reason,
    required this.onOpen,
  });

  final String status;
  final String? kind;
  final String? reason;
  final void Function(List<ModerationReport>) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(consoleReportsProvider(status));
    return switch (reports) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consoleReportsProvider(status).future),
        child: _list(
          context,
          groupDossiers([
            for (final r in value)
              if ((kind == null || r.kind == kind) && (reason == null || r.reason == reason)) r,
          ]),
        ),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleReportsProvider(status)),
      ),
      _ => const LoadingView(),
    };
  }

  Widget _list(BuildContext context, List<List<ModerationReport>> dossiers) {
    if (dossiers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          EmptyView(
            icon: Icons.verified_outlined,
            title: switch (status) {
              'open' => 'Rien à traiter',
              'reviewing' => 'Aucun dossier en cours',
              _ => 'Aucun signalement traité',
            },
            message: 'Les nouveaux signalements arrivent ici, avec une notification.',
          ),
        ],
      );
    }
    // Lot 5.5 : dossiers en tuiles blanches.
    return ListView.separated(
      key: Key('reports.list.$status'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.m,
        PrivioSpacing.s,
        PrivioSpacing.m,
        PrivioSpacing.xl,
      ),
      itemCount: dossiers.length,
      separatorBuilder: (_, _) => const SizedBox(height: PrivioSpacing.s),
      itemBuilder: (_, i) => SettingsCard(children: [_dossierTile(context, dossiers[i])]),
    );
  }

  Widget _dossierTile(BuildContext context, List<ModerationReport> d) {
    final theme = Theme.of(context);
    const coral = Color(0xFFD85A30);
    final first = d.first;
    final reasons = {for (final r in d) reasonLabel(r.reason)}.join(', ');
    final people = {for (final r in d) r.reporterHandle}.length;
    return ListTile(
      key: Key('dossier.${first.target}'),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: coral.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(
          switch (first.kind) {
            'support' => Icons.support_agent,
            'group' => Icons.groups_outlined,
            'message' => Icons.chat_bubble_outline,
            _ => Icons.person_outline,
          },
          color: coral,
          size: 20,
        ),
      ),
      title: Text(_target(first)),
      subtitle: Text(
        [
          if (first.kind != 'support')
            '${d.length} signalement${d.length > 1 ? 's' : ''} · $people personne${people > 1 ? 's' : ''}',
          reasons,
          if (status == 'closed' && first.decision != null)
            kDecisionLabels[first.decision] ?? first.decision!
          else
            'depuis le ${_date(first.createdAt)}',
          if (first.suspended) _suspension(first),
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: first.protected
          ? Tooltip(
              message: 'Compte de l’administration',
              child: Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => onOpen(d),
    );
  }
}

/// Un dossier : la cible, ses signalements, les décisions possibles.
class DossierView extends ConsumerStatefulWidget {
  const DossierView({super.key, required this.reports, required this.onBack});

  final List<ModerationReport> reports;
  final VoidCallback onBack;

  @override
  ConsumerState<DossierView> createState() => _DossierViewState();
}

class _DossierViewState extends ConsumerState<DossierView> {
  bool _busy = false;

  ModerationReport get _first => widget.reports.first;
  List<String> get _ids => [for (final r in widget.reports) r.id];
  bool get _pending => _first.status != 'closed';

  Future<void> _take() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).takeReports(_ids);
      refreshModeration(ref);
      widget.onBack();
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Motif obligatoire (et durée pour une suspension), puis confirmation.
  Future<void> _decide(String action) async {
    final result = await showDialog<(String, int?, String?)>(
      context: context,
      builder: (_) => DecisionDialog(action: action, target: _target(_first)),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).moderate(_ids, action, result.$1, days: result.$2);
      refreshModeration(ref);
      _toast(switch (action) {
        'dismiss' => 'Dossier classé sans suite.',
        'warn' => 'Avertissement envoyé.',
        'suspend' => 'Compte suspendu.',
        'delete_message' => 'Message supprimé.',
        _ => 'Groupe fermé.',
      });
      widget.onBack();
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lot 5.4 : une réponse par demande, notifiée sans contenu à la personne.
  Future<void> _reply() async {
    final text = await showDialog<String>(context: context, builder: (_) => const ReplyDialog());
    if (text == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).replySupport(_first.id, text);
      refreshModeration(ref);
      _toast('Réponse envoyée.');
      widget.onBack();
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lift() async {
    final result = await showDialog<(String, int?, String?)>(
      context: context,
      builder: (_) => DecisionDialog(action: 'lift', target: _target(_first)),
    );
    if (result == null || !mounted || _first.reportedUserId == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).liftSuspension(_first.reportedUserId!, result.$1);
      refreshModeration(ref);
      _toast('Compte réactivé.');
      widget.onBack();
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = _first;
    final isUser = f.kind == 'account' || f.kind == 'message';
    final hasMessage = widget.reports.any((r) => r.messageId != null);
    final sanctions = isUser && f.reportedUserId != null
        ? ref.watch(userSanctionsProvider(f.reportedUserId!)).value
        : null;
    return ListView(
      key: const Key('dossier.view'),
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
      children: [
        ListTile(
          key: const Key('dossier.back'),
          leading: const Icon(Icons.arrow_back),
          title: const Text('Retour à la liste'),
          onTap: widget.onBack,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_target(f), style: theme.textTheme.titleLarge, key: const Key('dossier.target')),
              const SizedBox(height: PrivioSpacing.xs),
              if (isUser && f.reportedSince != null)
                Text('Inscrit le ${_date(f.reportedSince!).split(' à').first}'),
              if (isUser)
                Text(
                  'Signalé ${f.reports90d} fois en 90 jours, par ${f.reporters90d} '
                  'personne${f.reporters90d > 1 ? 's' : ''}',
                  key: const Key('dossier.counts'),
                ),
              if (f.suspended)
                Text(
                  _suspension(f),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              if (f.kind == 'group' && f.groupClosed) const Text('Groupe déjà fermé'),
              if (f.protected)
                Padding(
                  padding: const EdgeInsets.only(top: PrivioSpacing.s),
                  child: Text(
                    'Compte de l’administration : il ne peut pas être sanctionné.',
                    key: const Key('dossier.protected'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              if (sanctions != null && sanctions.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.s),
                Text('Sanctions passées', style: theme.textTheme.titleSmall),
                for (final s in sanctions)
                  Text(
                    '${s.kind == 'warning' ? 'Avertissement' : 'Suspension'} le '
                    '${_date(s.createdAt)} · ${reasonLabel(s.reason).toLowerCase()}'
                    '${s.liftedAt != null ? ' · levée' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        for (final r in widget.reports) _ReportCard(r: r),
        if (_pending) ...[
          const SizedBox(height: PrivioSpacing.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Wrap(
              spacing: PrivioSpacing.s,
              runSpacing: PrivioSpacing.s,
              children: [
                if (f.status == 'open')
                  OutlinedButton.icon(
                    key: const Key('dossier.take'),
                    onPressed: _busy ? null : _take,
                    icon: const Icon(Icons.pan_tool_outlined),
                    label: const Text('Prendre en charge'),
                  ),
                OutlinedButton(
                  key: const Key('dossier.dismiss'),
                  onPressed: _busy ? null : () => _decide('dismiss'),
                  child: const Text('Classer sans suite'),
                ),
                if (isUser && !f.protected && f.reportedUserId != null) ...[
                  FilledButton(
                    key: const Key('dossier.warn'),
                    onPressed: _busy ? null : () => _decide('warn'),
                    child: const Text('Avertir'),
                  ),
                  FilledButton(
                    key: const Key('dossier.suspend'),
                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                    onPressed: _busy ? null : () => _decide('suspend'),
                    child: const Text('Suspendre…'),
                  ),
                ],
                if (hasMessage)
                  OutlinedButton(
                    key: const Key('dossier.delete_message'),
                    onPressed: _busy ? null : () => _decide('delete_message'),
                    child: const Text('Supprimer le message'),
                  ),
                if (f.kind == 'group' && !f.groupClosed)
                  FilledButton(
                    key: const Key('dossier.close_group'),
                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                    onPressed: _busy ? null : () => _decide('close_group'),
                    child: const Text('Fermer le groupe'),
                  ),
              ],
            ),
          ),
        ],
        if (f.suspended && f.reportedUserId != null)
          Padding(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            child: OutlinedButton.icon(
              key: const Key('dossier.lift'),
              onPressed: _busy ? null : _lift,
              icon: const Icon(Icons.lock_open),
              label: const Text('Réactiver le compte'),
            ),
          ),
        if (f.kind == 'support' && _pending)
          Padding(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            child: FilledButton.icon(
              key: const Key('dossier.reply'),
              onPressed: _busy ? null : _reply,
              icon: const Icon(Icons.reply),
              label: const Text('Répondre'),
            ),
          ),
      ],
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({required this.r});

  final ModerationReport r;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  ReportEvidence? _evidence;
  Uint8List? _media;
  bool _loading = false;
  String? _error;

  Future<void> _show() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await ref.read(adminApiProvider).evidence(widget.r.id);
      Uint8List? media;
      if (e.mediaPath != null) {
        final api = ref.read(messagingApiProvider);
        media = e.kind == 'photo'
            ? await api.downloadPhoto(e.mediaPath!)
            : await api.downloadVoice(e.mediaPath!);
      }
      if (!mounted) return;
      setState(() {
        _evidence = e;
        _media = media;
      });
      ref.invalidate(consoleJournalProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final r = widget.r;
    final e = _evidence;
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, PrivioSpacing.m, PrivioSpacing.l, 0),
      child: Card(
        key: Key('report.${r.id}'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reasonLabel(r.reason), style: theme.textTheme.titleSmall),
              Text(
                'Le ${_date(r.createdAt)} · par ${r.reporterHandle == null ? 'un compte supprimé' : '@${r.reporterHandle}'}'
                '${r.kind == 'message' ? ' · message signalé' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              if (r.details != null) ...[
                const SizedBox(height: PrivioSpacing.s),
                Text('« ${r.details} »'),
              ],
              if (r.reply != null) ...[
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  'Réponse${r.repliedAt == null ? '' : ' du ${_date(r.repliedAt!)}'}\u202F: ${r.reply}',
                  key: Key('report.reply.${r.id}'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: p.accentText),
                ),
              ],
              if (r.decision != null && r.decision != 'answered') ...[
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  '${kDecisionLabels[r.decision] ?? r.decision}'
                  '${r.decidedAt == null ? '' : ' le ${_date(r.decidedAt!)}'}'
                  '${r.decisionNote == null ? '' : ' · ${r.decisionNote}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: p.accentText),
                ),
              ],
              if (r.evidenceKind != null && e == null) ...[
                const SizedBox(height: PrivioSpacing.s),
                Text(
                  'Copie jointe par la personne qui signale. Son ouverture est inscrite au journal.',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton.icon(
                  key: Key('report.evidence.${r.id}'),
                  onPressed: _loading ? null : _show,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(switch (r.evidenceKind) {
                    'photo' => 'Afficher la photo signalée',
                    'voice' => 'Écouter le vocal signalé',
                    _ => 'Afficher la copie du message',
                  }),
                ),
              ],
              if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              if (e != null) ...[
                const SizedBox(height: PrivioSpacing.s),
                Container(
                  key: Key('report.copy.${r.id}'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(PrivioSpacing.m),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(PrivioRadius.medium),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.kind == 'photo' && _media != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(PrivioRadius.small),
                          child: Image.memory(_media!, height: 220, fit: BoxFit.contain),
                        ),
                      if (e.kind == 'voice' && _media != null)
                        TextButton.icon(
                          key: Key('report.play.${r.id}'),
                          onPressed: () => unawaited(ref.read(audioEngineProvider).play(_media!)),
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Écouter (${((e.durationMs ?? 0) / 1000).round()} s)'),
                        ),
                      if (e.body != null && e.body!.isNotEmpty) Text(e.body!),
                      if (e.sentAt != null)
                        Text('Envoyé le ${_date(e.sentAt!)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Motif (obligatoire) et, pour une suspension, la durée.
class DecisionDialog extends StatefulWidget {
  const DecisionDialog({
    super.key,
    required this.action,
    required this.target,
    this.askReason = false,
  });

  final String action;
  final String target;

  /// Lot 5.4 : sanction depuis la fiche (sans signalement) : choisir le motif montré.
  final bool askReason;

  @override
  State<DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<DecisionDialog> {
  final _note = TextEditingController();
  int? _days = 7;
  String _reason = 'other';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, effect) = switch (widget.action) {
      'dismiss' => (
        'Classer sans suite',
        'Aucune mesure. Le dossier passe dans «\u202FTraités\u202F».',
      ),
      'warn' => (
        'Avertir',
        'Un message de l’équipe Privio s’affichera à sa prochaine ouverture de l’application.',
      ),
      'suspend' => (
        'Suspendre',
        'L’application bascule aussitôt sur l’écran «\u202FCompte suspendu\u202F». Ses correspondants '
            'ne voient aucune mention.',
      ),
      'delete_message' => (
        'Supprimer le message',
        'Le message signalé est effacé pour tout le monde.',
      ),
      'close_group' => (
        'Fermer le groupe',
        'Plus personne ne pourra y écrire ; les membres voient « Groupe fermé par Privio ».',
      ),
      'disconnect' => (
        'Déconnecter le téléphone',
        'La session est coupée tout de suite. La personne devra se reconnecter avec son '
            'numéro et le code reçu par SMS.',
      ),
      'two_step_reset' => (
        'Réinitialiser la vérification en deux étapes',
        'À faire seulement après avoir vérifié l’identité de la personne. La vérification est '
            'désactivée\u202F: le téléphone qui attend le code s’ouvre, sans code de sécurité.',
      ),
      // Lot 5.6
      'remove_avatar' => (
        'Retirer la photo de profil',
        'La photo disparaît pour tout le monde. La personne pourra en choisir une autre.',
      ),
      'reset_handle' => (
        'Imposer un nouvel identifiant',
        'L’identifiant est remplacé tout de suite par un identifiant neutre. À sa prochaine '
            'ouverture de l’application, la personne devra en choisir un nouveau.',
      ),
      'disconnect_device' => (
        'Déconnecter cet appareil',
        'Seul ce téléphone est déconnecté. La personne devra se reconnecter avec son numéro '
            'et le code reçu par SMS.',
      ),
      'uphold' => (
        'Maintenir la suspension',
        'La personne verra que sa contestation a été examinée et que la suspension est maintenue.',
      ),
      _ => ('Lever la suspension', 'Le compte est réactivé tout de suite.'),
    };
    return AlertDialog(
      key: Key('decision.${widget.action}'),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.target, style: theme.textTheme.titleSmall),
            const SizedBox(height: PrivioSpacing.s),
            Text(effect, style: theme.textTheme.bodySmall),
            if (widget.action == 'suspend') ...[
              const SizedBox(height: PrivioSpacing.m),
              Wrap(
                spacing: PrivioSpacing.s,
                children: [
                  for (final (d, label) in const [
                    (1, '24 h'),
                    (7, '7 jours'),
                    (30, '30 jours'),
                    (null, 'Sans limite'),
                  ])
                    consoleChip(
                      context,
                      key: Key('decision.days.${d ?? 0}'),
                      label: label,
                      selected: _days == d,
                      onTap: () => setState(() => _days = d),
                    ),
                ],
              ),
            ],
            if (widget.askReason) ...[
              const SizedBox(height: PrivioSpacing.m),
              Text('Motif montré à la personne', style: theme.textTheme.labelLarge),
              const SizedBox(height: PrivioSpacing.xs),
              Wrap(
                spacing: PrivioSpacing.s,
                runSpacing: PrivioSpacing.xs,
                children: [
                  for (final e in kReportReasons.entries)
                    if (e.key != 'support')
                      consoleChip(
                        context,
                        key: Key('decision.reason.${e.key}'),
                        label: e.value,
                        selected: _reason == e.key,
                        onTap: () => setState(() => _reason = e.key),
                      ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.m),
            TextField(
              key: const Key('decision.note'),
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Motif (interne, jamais montré)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('decision.confirm'),
          onPressed: _note.text.trim().length < 3
              ? null
              : () => Navigator.pop(context, (_note.text.trim(), _days, _reason)),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

/// Contestations en attente : maintenir ou lever la suspension.
class _AppealsList extends ConsumerWidget {
  const _AppealsList();

  Future<void> _answer(BuildContext context, WidgetRef ref, Sanction s, bool lift) async {
    final result = await showDialog<(String, int?, String?)>(
      context: context,
      builder: (_) =>
          DecisionDialog(action: lift ? 'lift' : 'uphold', target: '@${s.handle ?? '—'}'),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).answerAppeal(s.id, lift: lift, note: result.$1);
      refreshModeration(ref);
      messenger.showSnackBar(
        SnackBar(content: Text(lift ? 'Suspension levée.' : 'Suspension maintenue.')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appeals = ref.watch(consoleAppealsProvider);
    final theme = Theme.of(context);
    return switch (appeals) {
      AsyncData(:final value) when value.isEmpty => ListView(
        children: const [
          SizedBox(height: 60),
          EmptyView(
            icon: Icons.gavel_outlined,
            title: 'Aucune contestation',
            message: 'Une personne suspendue peut contester une fois par sanction.',
          ),
        ],
      ),
      AsyncData(:final value) => ListView(
        key: const Key('appeals.list'),
        children: [
          for (final s in value)
            Card(
              key: Key('appeal.${s.id}'),
              margin: const EdgeInsets.all(PrivioSpacing.m),
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${s.handle ?? '—'}${s.displayName == null ? '' : ' · ${s.displayName}'}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${s.until == null ? 'Suspendu sans limite' : 'Suspendu jusqu’au ${_date(s.until!)}'}'
                      ' · ${reasonLabel(s.reason).toLowerCase()}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (s.note != null)
                      Text('Motif interne : ${s.note}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: PrivioSpacing.s),
                    Text('« ${s.appealText ?? ''} »'),
                    const SizedBox(height: PrivioSpacing.m),
                    Wrap(
                      spacing: PrivioSpacing.s,
                      children: [
                        OutlinedButton(
                          key: Key('appeal.uphold.${s.id}'),
                          onPressed: () => _answer(context, ref, s, false),
                          child: const Text('Maintenir'),
                        ),
                        FilledButton(
                          key: Key('appeal.lift.${s.id}'),
                          onPressed: () => _answer(context, ref, s, true),
                          child: const Text('Lever la suspension'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleAppealsProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

/// Modèles de réponse (lot 5.4), modifiables avant l'envoi.
const kReplyTemplates = <String>[
  'Merci, le problème est corrigé.',
  'Mettez à jour l’application puis réessayez.',
  'Nous avons besoin de plus de détails\u202F: que voyez-vous à l’écran\u202F?',
];

/// Réponse à une demande d'assistance (1 000 caractères au plus).
class ReplyDialog extends StatefulWidget {
  const ReplyDialog({super.key});

  @override
  State<ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<ReplyDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('reply.dialog'),
      title: const Text('Répondre'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La personne reçoit une notification sans contenu et lit la réponse dans '
              'Aide → Mes demandes. Une seule réponse par demande.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.m),
            Text('Modèles', style: theme.textTheme.labelLarge),
            for (final (i, t) in kReplyTemplates.indexed)
              TextButton(
                key: Key('reply.template.$i'),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => setState(() {
                  _text.text = t;
                  _text.selection = TextSelection.collapsed(offset: t.length);
                }),
                child: Text(t, textAlign: TextAlign.start),
              ),
            const SizedBox(height: PrivioSpacing.s),
            TextField(
              key: const Key('reply.text'),
              controller: _text,
              maxLength: 1000,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Votre réponse'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('reply.send'),
          onPressed: _text.text.trim().length < 2
              ? null
              : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}
