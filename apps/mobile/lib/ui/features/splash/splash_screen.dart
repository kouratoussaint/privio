import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/privio_brand.dart';
import '../../core/widgets/state_views.dart';

/// Écran 01 — initialisation. La navigation est pilotée par le routeur.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return Scaffold(
      body: session.hasError
          ? ErrorView(
              message: toAppFailure(session.error!).message,
              onRetry: () => ref.invalidate(sessionControllerProvider),
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrivioSymbol(size: 112),
                  SizedBox(height: PrivioSpacing.l),
                  PrivioWordmark(),
                  SizedBox(height: PrivioSpacing.xl),
                  LoadingView(),
                ],
              ),
            ),
    );
  }
}
