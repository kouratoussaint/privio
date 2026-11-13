import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_tokens.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/state_views.dart';

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
              child: const Text('Autoriser les notifications'),
            ),
            const SizedBox(height: PrivioSpacing.s),
            TextButton(
              key: const Key('permissions.later'),
              onPressed: _busy ? null : () => _finish(askNotifications: false),
              child: const Text('Plus tard'),
            ),
          ],
        ),
        children: [
          const SizedBox(height: PrivioSpacing.xxl),
          Icon(Icons.notifications_active_outlined, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: PrivioSpacing.xl),
          Text('Restez informé', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: PrivioSpacing.m),
          Text(
            'Soyez prévenu d’un nouveau message. La notification n’affiche jamais son contenu.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(
            'Le micro et l’appareil photo ne seront demandés que lorsque vous en aurez besoin.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
