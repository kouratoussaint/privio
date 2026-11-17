import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/contact_labels.dart';
import '../../../state/contact_labels_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/privio_menu.dart';
import '../../core/widgets/success_snack.dart';
import '../groups/join_group_screen.dart' show QrScanScreen;

/// Lot 10.4 — « Vérifié en personne » et surnom privé (ADR-048).

/// Couleur du badge « Vérifié en personne ».
const verifiedColor = MenuTint.green;

/// Lire le QR code de vérification d'un contact (remplacé dans les tests).
final verificationScannerProvider = Provider<Future<String?> Function(BuildContext context)>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => QrScanScreen(
            parse: parseVerificationCode,
            hint: L.t.verifyScanHint,
            invalid: L.t.verifyScanInvalid,
          ),
          fullscreenDialog: true,
        ),
      ),
);

Future<void> openVerifyInPerson(BuildContext context, String userId, String name) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VerifyInPersonScreen(userId: userId, name: name),
      ),
    );

/// Pourquoi la vérification est à refaire.
String lapseText(ContactLabel label, String name) => switch (label.lapse) {
  'phone' => L.t.verifyLapsedPhone(name),
  'both' => L.t.verifyLapsedBoth(name),
  _ => L.t.verifyLapsedDevice(name),
};

String verifiedOnText(DateTime at) =>
    L.t.verifiedOn(DateFormat('dd/MM/yyyy', 'fr').format(at.toLocal()));

enum _Step { choose, showing, expired, done }

class VerifyInPersonScreen extends ConsumerStatefulWidget {
  const VerifyInPersonScreen({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  ConsumerState<VerifyInPersonScreen> createState() => _VerifyInPersonScreenState();
}

class _VerifyInPersonScreenState extends ConsumerState<VerifyInPersonScreen> {
  _Step _step = _Step.choose;
  VerificationCode? _code;
  Timer? _tick;
  int _left = 0;
  bool _busy = false;
  bool _checking = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _show() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final code = await ref.read(messagingApiProvider).createVerificationCode(widget.userId);
      if (!mounted) return;
      _tick?.cancel();
      setState(() {
        _code = code;
        _step = _Step.showing;
        _left = _remaining(code);
      });
      // Compte à rebours chaque seconde ; résultat demandé toutes les 2 secondes (le
      // signal temps réel recharge aussi les étiquettes).
      // Décompte à la seconde depuis l'affichage (indépendant de l'heure du téléphone).
      final start = _left;
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        final left = (start - t.tick).clamp(0, 120);
        setState(() => _left = left);
        if (left <= 0) {
          t.cancel();
          setState(() => _step = _Step.expired);
        } else if (t.tick.isEven) {
          unawaited(_check(code));
        }
      });
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Secondes restantes à l'affichage du code (arrondi au-dessus : « 2:00 » au départ).
  int _remaining(VerificationCode code) {
    final ms = code.expiresAt.difference(DateTime.now()).inMilliseconds;
    return (ms / 1000).ceil().clamp(0, 120);
  }

  Future<void> _check(VerificationCode code) async {
    if (_checking) return;
    _checking = true;
    try {
      final status = await ref.read(messagingApiProvider).verificationCodeStatus(code.code);
      if (!mounted || _code != code) return;
      if (status == 'verified') await _finish();
    } on Object {
      // Réseau : on réessaie au tour suivant.
    } finally {
      _checking = false;
    }
  }

  Future<void> _scan() async {
    final code = await ref.read(verificationScannerProvider)(context);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagingApiProvider).confirmVerificationCode(code, widget.userId);
      await _finish();
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    _tick?.cancel();
    if (mounted) setState(() => _step = _Step.done);
    await ref.read(contactLabelsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final name = widget.name;
    final body = switch (_step) {
      _Step.choose => [
        const Icon(Icons.verified_user_outlined, size: 64, color: verifiedColor),
        const SizedBox(height: PrivioSpacing.l),
        Text(
          L.t.verifyIntroTitle(name),
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: PrivioSpacing.m),
        Text(L.t.verifyIntroText, textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton.icon(
          key: const Key('verify.show'),
          onPressed: _busy ? null : _show,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(L.t.verifyShowMyCode),
        ),
        const SizedBox(height: PrivioSpacing.m),
        OutlinedButton.icon(
          key: const Key('verify.scan'),
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(L.t.verifyScanTheirCode),
        ),
        const SizedBox(height: PrivioSpacing.xl),
        Text(
          L.t.verifyBadgeNote(name),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
      _Step.showing => [
        Text(
          L.t.verifyShowTitle(name),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: PrivioSpacing.l),
        Center(
          child: Container(
            padding: const EdgeInsets.all(PrivioSpacing.m),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(PrivioRadius.large),
            ),
            child: QrImageView(
              key: const Key('verify.qr'),
              data: _code!.qrData,
              size: 220,
              backgroundColor: Colors.white,
              semanticsLabel: L.t.verifyQrLabel,
            ),
          ),
        ),
        const SizedBox(height: PrivioSpacing.m),
        Text(
          L.t.verifyValidFor('${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}'),
          key: const Key('verify.countdown'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(color: p.accentText),
        ),
        const SizedBox(height: PrivioSpacing.l),
        Text(L.t.verifyShowHelp(name), textAlign: TextAlign.center),
      ],
      _Step.expired => [
        Icon(Icons.timer_off_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: PrivioSpacing.l),
        Text(L.t.verifyExpired, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.l),
        FilledButton(
          key: const Key('verify.renew'),
          onPressed: _busy ? null : _show,
          child: Text(L.t.verifyNewCode),
        ),
      ],
      _Step.done => [
        const Icon(Icons.verified_user, size: 72, color: verifiedColor, key: Key('verify.success')),
        const SizedBox(height: PrivioSpacing.l),
        Text(L.t.verifyDone(name), style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.m),
        Text(L.t.verifyDoneText, textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          key: const Key('verify.done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.t.verifyFinished),
        ),
      ],
    };
    return Scaffold(
      appBar: AppBar(title: Text(L.t.verifierEnPersonne)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PrivioSpacing.xl),
          children: [
            const SizedBox(height: PrivioSpacing.l),
            ...body,
          ],
        ),
      ),
    );
  }
}

/// Avis dans la discussion : le contact vérifié a changé de téléphone ou de numéro.
class VerificationNoticeBanner extends StatelessWidget {
  const VerificationNoticeBanner({
    super.key,
    required this.label,
    required this.name,
    required this.onVerify,
    required this.onClose,
  });

  final ContactLabel label;
  final String name;
  final VoidCallback onVerify;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tint = MenuTint.amber;
    return Padding(
      key: const Key('chat.verify_notice'),
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, PrivioSpacing.s, PrivioSpacing.l, 0),
      child: Material(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, 6, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined, size: 20, color: tint),
              const SizedBox(width: PrivioSpacing.s),
              Expanded(
                child: Text(
                  '${lapseText(label, name)} ${L.t.verifyAgainHint}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('chat.verify_again'),
                onPressed: onVerify,
                child: Text(L.t.verifyAgain),
              ),
              IconButton(
                key: const Key('chat.verify_notice_close'),
                tooltip: L.t.fermer,
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit bouclier vert à côté d'un nom (liste des membres d'un groupe).
class VerifiedMark extends StatelessWidget {
  const VerifiedMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: L.t.verifieEnPersonne,
    child: Icon(Icons.verified_user, size: size, color: verifiedColor),
  );
}

/// Choisir, changer ou retirer le surnom privé de [userId].
Future<void> editNickname(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String realName,
}) async {
  final current = ref.read(contactLabelsProvider)[userId]?.nickname;
  final ctrl = TextEditingController(text: current ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L.t.surnomPrive),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('nickname.field'),
            controller: ctrl,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: realName),
          ),
          Text(L.t.surnomPriveAide(realName), style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
      actions: [
        if (current != null)
          TextButton(
            key: const Key('nickname.remove'),
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(L.t.retirer),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('nickname.save'),
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: Text(L.t.enregistrer),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  if (result == null || !context.mounted) return;
  final trimmed = result.trim();
  if (trimmed == (current ?? '')) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(contactLabelsProvider.notifier)
        .setNickname(userId, trimmed.isEmpty ? null : trimmed);
    messenger.showSnackBar(successSnack(trimmed.isEmpty ? L.t.surnomRetire : L.t.surnomEnregistre));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}
