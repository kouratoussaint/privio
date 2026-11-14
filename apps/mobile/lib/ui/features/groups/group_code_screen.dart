import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/join_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/settings_card.dart';

/// Code d'invitation d'un groupe (administrateurs), créé à la première ouverture.
final groupInviteCodeProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, conversationId) => ref.watch(messagingApiProvider).getGroupInviteCode(conversationId),
);

/// Lot 7.1b — « Inviter avec un code » : le code PRV-XXXXXX et son QR code, à montrer ou à
/// transmettre hors de l'application. Aucun lien web. « Changer le code » rend l'ancien
/// (et son QR code) inutilisable aussitôt.
class GroupCodeScreen extends ConsumerStatefulWidget {
  const GroupCodeScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<GroupCodeScreen> createState() => _GroupCodeScreenState();
}

class _GroupCodeScreenState extends ConsumerState<GroupCodeScreen> {
  String? _reset;
  bool _busy = false;

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _toast('Code copié.');
  }

  Future<void> _change() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer le code ?'),
        content: const Text(
          'L’ancien code et l’ancien QR code ne fonctionneront plus. Les demandes déjà '
          'envoyées restent à traiter.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('code.reset.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final code = await ref.read(messagingApiProvider).resetGroupInviteCode(widget.conversationId);
      if (!mounted) return;
      setState(() => _reset = code);
      _toast('Nouveau code créé.');
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = ref.watch(groupInviteCodeProvider(widget.conversationId));
    final approval =
        ref.watch(groupJoinSettingsProvider(widget.conversationId)).value?.approvalRequired ?? true;
    return Scaffold(
      appBar: AppBar(title: const Text('Inviter avec un code')),
      body: switch (code) {
        AsyncValue(:final value?) => _body(context, theme, _reset ?? value, approval),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(groupInviteCodeProvider(widget.conversationId)),
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(
    BuildContext context,
    ThemeData theme,
    String code,
    bool approval,
  ) => SettingsListView(
    children: [
      SettingsCard(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        children: [
          Center(
            // Fond blanc dans tous les thèmes : les lecteurs de QR code en ont besoin.
            child: Container(
              padding: const EdgeInsets.all(PrivioSpacing.l),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(PrivioRadius.large),
              ),
              child: QrImageView(
                key: const Key('code.qr'),
                data: code,
                size: 220,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR code du groupe',
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Center(
            child: Text(
              code,
              key: const Key('code.value'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(
            approval
                ? 'Une personne qui entre ce code (Groupes → Rejoindre un groupe) ou scanne ce QR '
                      'code vous envoie une demande ; un administrateur l’accepte ou la refuse.'
                : 'Une personne qui entre ce code (Groupes → Rejoindre un groupe) ou scanne ce QR '
                      'code rejoint le groupe directement.',
            key: const Key('code.help'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            'Donnez-le seulement aux personnes que vous voulez inviter. Les captures d’écran sont '
            'bloquées : montrez le QR code ou recopiez le code dans un message.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      const SizedBox(height: PrivioSpacing.xl),
      FilledButton.icon(
        key: const Key('code.copy'),
        onPressed: () => _copy(code),
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copier le code'),
      ),
      const SizedBox(height: PrivioSpacing.s),
      OutlinedButton.icon(
        key: const Key('code.reset'),
        onPressed: _busy ? null : _change,
        icon: const Icon(Icons.autorenew_rounded),
        label: const Text('Changer le code'),
      ),
    ],
  );
}
