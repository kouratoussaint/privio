import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/call_controller.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';

/// Lot 9.1a — écran d'appel, posé AU-DESSUS de toute l'application (verrouillage compris :
/// on peut décrocher sans saisir le code, le reste de Privio reste verrouillé — décision E).
/// Réduit, il devient un bandeau en haut de l'écran.
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  @override
  void initState() {
    super.initState();
    // Un appel qui sonne déjà à l'ouverture de Privio.
    if (ref.read(currentUserIdProvider) != null) {
      Future.microtask(() => ref.read(callControllerProvider.notifier).checkOpenCall());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserIdProvider, (prev, next) {
      if (next != null && next != prev) {
        unawaited(ref.read(callControllerProvider.notifier).checkOpenCall());
      }
    });
    final call = ref.watch(callControllerProvider);
    final bar = call != null && call.minimized;
    // Structure constante : l'application (et son état) n'est jamais recréée pendant un appel.
    return Stack(
      children: [
        Column(
          children: [
            if (bar) const _CallBar() else const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                // Bandeau affiché : il occupe déjà la barre d'état.
                removeTop: bar,
                child: widget.child,
              ),
            ),
          ],
        ),
        if (call != null && !call.minimized)
          Positioned.fill(
            // Écran autonome (posé au-dessus du navigateur de l'application).
            child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const _CallView())]),
          ),
      ],
    );
  }
}

String formatCallDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Durée affichée, mise à jour chaque seconde.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.since, required this.builder});

  final DateTime since;
  final Widget Function(String duration) builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(formatCallDuration(DateTime.now().difference(widget.since)));
}

class _CallBar extends ConsumerWidget {
  const _CallBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(color: Colors.white);
    return Material(
      color: PrivioColors.success,
      child: InkWell(
        key: const Key('call.bar'),
        onTap: () => ref.read(callControllerProvider.notifier).setMinimized(false),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: PrivioSpacing.l),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.call, color: Colors.white, size: 18),
                const SizedBox(width: PrivioSpacing.s),
                Flexible(
                  child: call.connectedAt == null
                      ? Text(L.t.callBarRinging, style: style)
                      : _Ticker(
                          since: call.connectedAt!,
                          builder: (d) => Text(L.t.callBar(d), style: style),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallView extends ConsumerWidget {
  const _CallView();

  String _endText(CallState c) {
    final answered = c.info.answeredAt;
    return switch (c.endStatus) {
      'declined' => L.t.callDeclined,
      'busy' => L.t.callBusy,
      'failed' || 'lost' => L.t.callFailed,
      'cancelled' => c.info.outgoing ? L.t.callCancelled : L.t.callMissed,
      'missed' => c.info.outgoing ? L.t.callNoAnswer : L.t.callMissed,
      _ =>
        answered != null && c.connectedAt != null
            ? L.t.callEndedDuration(formatCallDuration(DateTime.now().difference(c.connectedAt!)))
            : L.t.callEnded,
    };
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    if (call == null) return const SizedBox.shrink();
    final ctrl = ref.read(callControllerProvider.notifier);
    final theme = Theme.of(context);
    // Privio verrouillé : pas de nom tant que le code n'est pas saisi (décision C).
    final locked = ref.watch(appLockProvider).value?.locked ?? false;
    final hideName = locked && call.phase == CallPhase.incomingRinging;
    final white = theme.textTheme.bodyLarge?.copyWith(color: Colors.white70);
    final status = switch (call.phase) {
      CallPhase.incomingRinging => Text(L.t.callIncoming, style: white),
      CallPhase.outgoingRinging => Text(L.t.callRinging, style: white),
      CallPhase.connecting => Text(L.t.callConnecting, style: white),
      CallPhase.reconnecting => Text(L.t.callReconnecting, style: white),
      CallPhase.connected => _Ticker(
        since: call.connectedAt ?? DateTime.now(),
        builder: (d) => Text(d, style: white),
      ),
      CallPhase.ended => Text(_endText(call), style: white),
    };
    return Material(
      key: const Key('call.screen'),
      color: const Color(0xFF2A0F5C),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B1FB8), Color(0xFF1B0B3D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: call.phase == CallPhase.ended || call.phase == CallPhase.incomingRinging
                    ? const SizedBox(height: 48)
                    : _RoundButton(
                        key: const Key('call.minimize'),
                        icon: Icons.keyboard_arrow_down_rounded,
                        label: L.t.reduire,
                        small: true,
                        onTap: () => ctrl.setMinimized(true),
                      ),
              ),
              const Spacer(),
              if (hideName)
                const CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.call, size: 48, color: Colors.white),
                )
              else
                UserAvatar(
                  name: call.info.peerName,
                  avatarPath: call.info.peerAvatar,
                  seed: call.info.peerId,
                  radius: 56,
                ),
              const SizedBox(height: PrivioSpacing.l),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xl),
                child: Text(
                  hideName ? L.t.callIncomingLocked : call.info.peerName,
                  key: const Key('call.name'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: PrivioSpacing.s),
              KeyedSubtree(key: const Key('call.status'), child: status),
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
                child: switch (call.phase) {
                  CallPhase.incomingRinging => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        key: const Key('call.decline'),
                        icon: Icons.call_end_rounded,
                        label: L.t.refuser2,
                        color: PrivioColors.error,
                        onTap: () => _run(context, ctrl.decline),
                      ),
                      _RoundButton(
                        key: const Key('call.accept'),
                        icon: Icons.call_rounded,
                        label: L.t.decrocher,
                        color: PrivioColors.success,
                        onTap: () => _run(context, ctrl.accept),
                      ),
                    ],
                  ),
                  CallPhase.ended => const SizedBox(height: 96),
                  _ => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        key: const Key('call.mute'),
                        icon: call.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                        label: call.muted ? L.t.microCoupe : L.t.micro,
                        selected: call.muted,
                        onTap: ctrl.toggleMute,
                      ),
                      _RoundButton(
                        key: const Key('call.hangup'),
                        icon: Icons.call_end_rounded,
                        label: L.t.raccrocher,
                        color: PrivioColors.error,
                        onTap: () => _run(context, ctrl.hangUp),
                      ),
                      _RoundButton(
                        key: const Key('call.speaker'),
                        icon: call.speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: L.t.hautParleur,
                        selected: call.speaker,
                        onTap: ctrl.toggleSpeaker,
                      ),
                    ],
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.selected = false,
    this.small = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool selected;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (selected ? Colors.white : Colors.white24);
    final fg = color != null ? Colors.white : (selected ? const Color(0xFF2A0F5C) : Colors.white);
    final size = small ? 44.0 : 68.0;
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: fg, size: small ? 28 : 32),
              ),
            ),
          ),
          if (!small) ...[
            const SizedBox(height: PrivioSpacing.s),
            ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lance un appel audio depuis une discussion à deux (bouton 📞) ; erreur affichée sur place.
Future<void> startCallFrom(BuildContext context, WidgetRef ref, String conversationId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(callControllerProvider.notifier).start(conversationId);
  } on Object catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}
