import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/messaging_providers.dart';

/// Motifs de signalement (dossier : modération).
List<(String, String)> get kReportReasons => [
  ('harassment', L.t.harcelementOuInsultes),
  ('threat', L.t.menacesOuViolence),
  ('spam', L.t.spamOuArnaque),
  ('inappropriate', L.t.contenuChoquant),
  ('impersonation', L.t.usurpationIdentite),
  ('other', L.t.autreRaison),
];

/// Signaler un message (si [messageId]) ou un contact. La copie du message n'est jointe
/// qu'avec l'accord explicite de la personne (case cochée), conservée 90 jours.
/// [reportedUserId] null : signalement d'un groupe entier ([conversationId]).
Future<void> showReportSheet(
  BuildContext context, {
  required String? reportedUserId,
  required String reportedName,
  String? conversationId,
  String? messageId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ReportSheet(
    reportedUserId: reportedUserId,
    reportedName: reportedName,
    conversationId: conversationId,
    messageId: messageId,
  ),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.reportedUserId,
    required this.reportedName,
    this.conversationId,
    this.messageId,
  });

  final String? reportedUserId;
  final String reportedName;
  final String? conversationId;
  final String? messageId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _details = TextEditingController();
  String? _reason;
  bool _includeMessage = true;
  bool _block = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(messagingApiProvider)
          .report(
            reason: _reason!,
            reportedUserId: widget.reportedUserId,
            conversationId: widget.conversationId,
            messageId: widget.messageId,
            details: _details.text.trim().isEmpty ? null : _details.text.trim(),
            includeMessage: widget.messageId != null && _includeMessage,
          );
      final target = widget.reportedUserId;
      if (_block && target != null) await setBlocked(ref, target, blocked: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _block
                ? L.t.merciVotreSignalementEstTransmis(widget.reportedName)
                : L.t.merciVotreSignalementEstTransmis2,
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMessage = widget.messageId != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xl,
            0,
            PrivioSpacing.xl,
            PrivioSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isMessage ? L.t.signalerCeMessage : L.t.signalerReportedname(widget.reportedName),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: PrivioSpacing.xs),
              Text(L.t.votreSignalementEstConfidentielPersonne, style: theme.textTheme.bodySmall),
              const SizedBox(height: PrivioSpacing.s),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(
                  children: [
                    for (final (code, label) in kReportReasons)
                      RadioListTile<String>(
                        key: Key('report.$code'),
                        value: code,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const Key('report.details'),
                controller: _details,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(labelText: L.t.precisionsFacultatif),
              ),
              if (isMessage)
                CheckboxListTile(
                  key: const Key('report.include'),
                  value: _includeMessage,
                  onChanged: (v) => setState(() => _includeMessage = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(L.t.joindreCopieCeMessage),
                  subtitle: Text(L.t.lueUniquementParEquipeModeration),
                ),
              if (widget.reportedUserId != null)
                CheckboxListTile(
                  key: const Key('report.block'),
                  value: _block,
                  onChanged: (v) => setState(() => _block = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(L.t.bloquerAussiReportedname(widget.reportedName)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              FilledButton(
                key: const Key('report.submit'),
                onPressed: _reason == null || _busy ? null : _submit,
                child: Text(_busy ? L.t.envoi : L.t.envoyerSignalement),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
