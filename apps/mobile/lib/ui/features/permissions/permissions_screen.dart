import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/state_views.dart';
import '../../core/motion/illustrations.dart';

/// Écran 07 — autorisations facultatives. Un refus ne bloque jamais l'application.
/// Micro, appareil photo et contacts seront demandés au moment de leur usage.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _busy = false;

  Future<void> _finish({required bool askNotifications}) async {
    setState(() => _busy = true);
    try {
      if (askNotifications) {
        await ref.read(permissionGatewayProvider).requestNotifications();
      }
      await ref.read(sessionControllerProvider.notifier).markPermissionsSeen();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: FlowLayout(
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('permissions.allow'),
              onPressed: _busy ? null : () => _finish(askNotifications: true),
              child: Text(L.t.autoriserNotifications),
            ),
            const SizedBox(height: PrivioSpacing.s),
            TextButton(
              key: const Key('permissions.later'),
              onPressed: _busy ? null : () => _finish(askNotifications: false),
              child: Text(L.t.plusTard),
            ),
          ],
        ),
        children: [
          const SizedBox(height: PrivioSpacing.xxl),
          // Lot 7.2b2 : la cloche sonne.
          const Center(
            child: FloatingIcon(
              icon: Icons.notifications_active_outlined,
              size: 52,
              motion: IconMotion.ring,
            ),
          ),
          const SizedBox(height: PrivioSpacing.xl),
          Text(
            L.t.restezInforme,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.m),
          Text(
            L.t.soyezPrevenuNouveauMessageNotification,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(
            L.t.microAppareilPhotoNeSeront,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
