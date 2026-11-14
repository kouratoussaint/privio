import 'package:flutter/material.dart';

import '../../../core/theme/privio_tokens.dart';
import '../motion/illustrations.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Chargement…'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(label: label, liveRegion: true, child: const CircularProgressIndicator()),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: PrivioSpacing.l),
            Text(message, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: PrivioSpacing.l),
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lot 7.2b2 : l'illustration flotte doucement.
            FloatingIcon(icon: icon, size: 44),
            const SizedBox(height: PrivioSpacing.l),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: PrivioSpacing.s),
            Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'information (ex. « compte ouvert sur un autre appareil »).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final VoidCallback? onClose;

  /// Action unique proposée dans le bandeau (ex. « Débloquer »).
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: PrivioSpacing.m),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  key: const Key('notice.action'),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              if (onClose != null)
                IconButton(onPressed: onClose, tooltip: 'Fermer', icon: const Icon(Icons.close)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mise en page des écrans d'accueil/connexion : défilable, sûre pour le clavier.
class FlowLayout extends StatelessWidget {
  const FlowLayout({super.key, required this.children, this.bottom});

  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PrivioSpacing.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
        if (bottom != null)
          Padding(
            padding: const EdgeInsets.only(
              left: PrivioSpacing.xl,
              right: PrivioSpacing.xl,
              bottom: PrivioSpacing.l,
            ),
            child: bottom,
          ),
      ],
    ),
  );
}
