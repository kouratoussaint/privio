import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/join_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/settings_card.dart';

/// Lecture d'un QR code : l'écran caméra, remplacé dans les tests (pas de caméra).
final qrScannerProvider = Provider<Future<String?> Function(BuildContext context)>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScanScreen(), fullscreenDialog: true),
      ),
);

/// Lot 7.1b — « Rejoindre un groupe » : code reçu d'un administrateur (PRV-XXXXXX), ou son
/// QR code scanné. L'aperçu montre le nom du groupe et son nombre de membres ; selon le
/// réglage du groupe, on entre directement ou on envoie une demande.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _code = TextEditingController();
  GroupPreview? _preview;
  String? _previewCode;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _lookUp([String? raw]) async {
    final code = parseInviteCode(raw ?? _code.text);
    FocusScope.of(context).unfocus();
    if (code == null) {
      setState(() {
        _preview = null;
        _error = 'Code incomplet : « PRV- » suivi de 6 lettres ou chiffres.';
      });
      return;
    }
    if (raw != null) _code.text = code;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref.read(messagingApiProvider).previewGroupByCode(code);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewCode = code;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final raw = await ref.read(qrScannerProvider)(context);
    if (raw == null || !mounted) return;
    await _lookUp(raw);
  }

  void _open(String conversationId) {
    ref.invalidate(conversationsProvider);
    context.pushReplacement(Routes.chat(conversationId));
  }

  Future<void> _join() async {
    final code = _previewCode;
    if (code == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(messagingApiProvider).joinGroupByCode(code);
      if (!mounted) return;
      switch (r.status) {
        case JoinStatus.joined || JoinStatus.member when r.conversationId != null:
          _open(r.conversationId!);
          return;
        case JoinStatus.requested:
          ref.invalidate(myJoinRequestsProvider);
          _toast('Demande envoyée. Vous serez prévenu quand elle sera acceptée.');
          setState(() => _preview = _with(JoinStatus.pending, r.conversationId));
        default:
          setState(() => _preview = _with(r.status));
      }
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  GroupPreview _with(JoinStatus status, [String? conversationId]) => GroupPreview(
    status: status,
    title: _preview?.title,
    memberCount: _preview?.memberCount,
    conversationId: conversationId ?? _preview?.conversationId,
  );

  Future<void> _cancel() async {
    final id = _preview?.conversationId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagingApiProvider).cancelJoinRequest(id);
      ref.invalidate(myJoinRequestsProvider);
      if (mounted) {
        _toast('Demande annulée.');
        setState(
          () => _preview = GroupPreview(
            status: JoinStatus.approval,
            title: _preview?.title,
            memberCount: _preview?.memberCount,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre un groupe')),
      body: SettingsListView(
        children: [
          SettingsCard(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              Text(
                'Entrez le code reçu d’un administrateur du groupe, ou scannez le QR code '
                'qu’il vous montre sur son téléphone.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: PrivioSpacing.l),
              TextField(
                key: const Key('join.code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 12,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _lookUp(),
                onChanged: (_) {
                  if (_preview != null || _error != null) {
                    setState(() {
                      _preview = null;
                      _error = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Code d’invitation',
                  hintText: 'PRV-7K3Q9X',
                  counterText: '',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
              ),
              const SizedBox(height: PrivioSpacing.m),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('join.scan'),
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scanner'),
                    ),
                  ),
                  const SizedBox(width: PrivioSpacing.m),
                  Expanded(
                    child: FilledButton(
                      key: const Key('join.preview'),
                      onPressed: _busy ? null : _lookUp,
                      child: const Text('Continuer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_busy) ...[const SizedBox(height: PrivioSpacing.l), const LinearProgressIndicator()],
          if (_preview case final p?) ...[
            const SizedBox(height: PrivioSpacing.xl),
            _PreviewCard(
              preview: p,
              busy: _busy,
              onJoin: _join,
              onCancel: _cancel,
              onOpen: p.conversationId == null ? null : () => _open(p.conversationId!),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.busy,
    required this.onJoin,
    required this.onCancel,
    this.onOpen,
  });

  final GroupPreview preview;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCancel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final s = preview.status;
    final (String message, Widget? action) = switch (s) {
      JoinStatus.invalid => (
        'Ce code ne correspond à aucun groupe. Vérifiez-le auprès de la personne qui vous '
            'l’a donné : il a peut-être été changé.',
        null,
      ),
      JoinStatus.member || JoinStatus.joined => (
        'Vous faites déjà partie de ce groupe.',
        FilledButton(
          key: const Key('join.open'),
          onPressed: onOpen,
          child: const Text('Ouvrir le groupe'),
        ),
      ),
      JoinStatus.pending || JoinStatus.requested => (
        'Votre demande est envoyée. Un administrateur du groupe doit l’accepter ; '
            'vous serez prévenu.',
        OutlinedButton(
          key: const Key('join.cancel'),
          onPressed: busy ? null : onCancel,
          child: const Text('Annuler la demande'),
        ),
      ),
      JoinStatus.declined => (
        'Votre demande a été refusée. Vous pourrez en faire une nouvelle dans 24 h.',
        null,
      ),
      JoinStatus.full => ('Ce groupe est complet.', null),
      JoinStatus.open => (
        'Vous pouvez rejoindre ce groupe directement.',
        FilledButton(
          key: const Key('join.submit'),
          onPressed: busy ? null : onJoin,
          child: const Text('Rejoindre le groupe'),
        ),
      ),
      JoinStatus.approval => (
        'Un administrateur du groupe doit accepter votre demande.',
        FilledButton(
          key: const Key('join.submit'),
          onPressed: busy ? null : onJoin,
          child: const Text('Demander à rejoindre'),
        ),
      ),
    };
    return SettingsCard(
      key: const Key('join.card'),
      padding: const EdgeInsets.all(PrivioSpacing.l),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (preview.title != null) ...[
              Row(
                children: [
                  UserAvatar(name: preview.title!, seed: preview.title!, radius: 24),
                  const SizedBox(width: PrivioSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.title!,
                          key: const Key('join.title'),
                          style: theme.textTheme.titleMedium,
                        ),
                        if (preview.memberCount case final n?)
                          Text(
                            '$n membre${n > 1 ? 's' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.m),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  s == JoinStatus.invalid ? Icons.error_outline : Icons.info_outline,
                  size: 20,
                  color: s == JoinStatus.invalid ? theme.colorScheme.error : p.accentText,
                ),
                const SizedBox(width: PrivioSpacing.s),
                Expanded(child: Text(message, key: const Key('join.message'))),
              ],
            ),
            if (action != null) ...[const SizedBox(height: PrivioSpacing.l), action],
          ],
        ),
      ],
    );
  }
}

/// Caméra pour lire le QR code d'un groupe. Le texte lu ne quitte pas le téléphone : seul
/// le code reconnu est renvoyé à l'écran « Rejoindre un groupe ».
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  DateTime? _warnedAt;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = parseInviteCode(b.rawValue);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    final now = DateTime.now();
    if (_warnedAt == null || now.difference(_warnedAt!) > const Duration(seconds: 3)) {
      _warnedAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce QR code n’est pas un code de groupe Privio.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner le QR code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(PrivioSpacing.xl),
                child: Text(
                  'Caméra indisponible. Autorisez l’appareil photo pour Privio dans les '
                  'réglages du téléphone, ou revenez en arrière et tapez le code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(PrivioRadius.large),
                ),
              ),
            ),
          ),
          const Positioned(
            left: PrivioSpacing.xl,
            right: PrivioSpacing.xl,
            bottom: PrivioSpacing.xxl,
            child: Text(
              'Placez le QR code du groupe dans le cadre.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
