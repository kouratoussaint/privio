import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/call_engine.dart' show AudioRoute;
import '../../../state/providers.dart';
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
        // Lot 9.2 : dans la petite fenêtre, seule l'image de l'appel (même réduit en bandeau).
        if (call != null && (!call.minimized || call.pip))
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

class _CallView extends ConsumerStatefulWidget {
  const _CallView();

  @override
  ConsumerState<_CallView> createState() => _CallViewState();
}

class _CallViewState extends ConsumerState<_CallView> {
  /// Choix de la sortie du son ouvert (lot 9.1b) : sorties proposées.
  List<AudioRoute>? _routes;

  /// Lot 9.2 : position de ma petite image (déplaçable).
  Offset _preview = const Offset(-1, -1);

  /// Haut-parleur d'un geste ; avec un appareil Bluetooth ou un casque branché, choix de
  /// la sortie du son (panneau dans l'écran d'appel, posé hors du navigateur).
  Future<void> _chooseRoute() async {
    final ctrl = ref.read(callControllerProvider.notifier);
    final routes = await ctrl.audioRoutes();
    if (routes.length <= 2) {
      await ctrl.toggleSpeaker();
    } else if (mounted) {
      setState(() => _routes = routes);
    }
  }

  Future<void> _pick(AudioRoute r) async {
    setState(() => _routes = null);
    await ref.read(callControllerProvider.notifier).selectRoute(r);
  }

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

  /// Ma petite image (déplaçable), avec le bouton pour changer de caméra.
  Widget _localPreview(BuildContext context, Widget local, CallController ctrl) {
    const w = 104.0;
    const h = 156.0;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final maxX = size.width - w - PrivioSpacing.m;
    final maxY = size.height - h - pad.bottom - 220;
    final pos = _preview.dx < 0
        ? Offset(maxX, pad.top + 56)
        : Offset(
            _preview.dx.clamp(PrivioSpacing.m, maxX),
            _preview.dy.clamp(pad.top, maxY < pad.top ? pad.top : maxY),
          );
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _preview = pos + d.delta),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            key: const Key('call.local'),
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: Colors.black, child: local),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const Key('call.flip'),
                      tooltip: L.t.callFlip,
                      iconSize: 20,
                      color: Colors.white,
                      icon: const Icon(Icons.cameraswitch_rounded),
                      onPressed: ctrl.switchCamera,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);
    if (call == null) return const SizedBox.shrink();
    final ctrl = ref.read(callControllerProvider.notifier);
    final theme = Theme.of(context);
    final live = call.phase != CallPhase.ended;
    if (call.pip) return _PipView(call: call, remote: ctrl.remoteView());
    // Privio verrouillé : pas de nom tant que le code n'est pas saisi (décision C).
    final locked = ref.watch(appLockProvider).value?.locked ?? false;
    // Lot 10.2 : discussion cachée : sonnerie neutre, le nom une fois l'appel décroché.
    final secret =
        ref.watch(conversationSummaryProvider(call.info.conversationId))?.secret ?? false;
    final hideName = (locked || secret) && call.phase == CallPhase.incomingRinging;
    final white = theme.textTheme.bodyLarge?.copyWith(color: Colors.white70);
    // Lot 9.2 : image du correspondant en plein écran, la mienne en petit.
    final remote = live && call.peerCamera ? ctrl.remoteView() : null;
    final local = live && call.camera ? ctrl.localView() : null;
    final status = switch (call.phase) {
      CallPhase.incomingRinging => Text(
        call.videoCall ? L.t.callVideoIncoming : L.t.callIncoming,
        style: white,
      ),
      CallPhase.outgoingRinging => Text(L.t.callRinging, style: white),
      CallPhase.connecting => Text(L.t.callConnecting, style: white),
      CallPhase.reconnecting => Text(L.t.callReconnecting, style: white),
      CallPhase.connected => _Ticker(
        since: call.connectedAt ?? DateTime.now(),
        builder: (d) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(d, style: white),
            // Lot 9.1b : pertes ou latence, l'appel continue.
            if (call.weak)
              Padding(
                padding: const EdgeInsets.only(top: PrivioSpacing.s),
                child: Row(
                  key: const Key('call.weak'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.network_check_rounded, color: Color(0xFFFFC857), size: 18),
                    const SizedBox(width: 6),
                    Text(L.t.callWeak, style: white?.copyWith(color: const Color(0xFFFFC857))),
                  ],
                ),
              ),
          ],
        ),
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
        child: Stack(
          children: [
            if (remote != null)
              Positioned.fill(
                child: KeyedSubtree(key: const Key('call.remote'), child: remote),
              ),
            if (remote != null)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x00000000), Color(0xB3000000)],
                      stops: [0, 0.35, 1],
                    ),
                  ),
                ),
              ),
            SafeArea(
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
                  if (remote == null) const Spacer(),
                  if (remote != null)
                    const SizedBox.shrink()
                  else if (hideName)
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
                  if (call.cameraDenied)
                    Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.m),
                      child: Text(
                        L.t.callCameraDenied,
                        key: const Key('call.camera.denied'),
                        textAlign: TextAlign.center,
                        style: white?.copyWith(color: const Color(0xFFFFC857)),
                      ),
                    ),
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
                      _ => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _RoundButton(
                                key: const Key('call.mute'),
                                icon: call.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                                label: call.muted ? L.t.microCoupe : L.t.micro,
                                selected: call.muted,
                                onTap: ctrl.toggleMute,
                              ),
                              // Lot 9.2 : ma caméra, à tout moment (décision A).
                              _RoundButton(
                                key: const Key('call.camera'),
                                icon: call.camera
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                label: call.camera ? L.t.callCamera : L.t.callCameraOff,
                                selected: call.camera,
                                onTap: ctrl.toggleCamera,
                              ),
                              _RoundButton(
                                key: const Key('call.speaker'),
                                icon: routeIcon(call.route),
                                label: switch (call.route) {
                                  AudioRoute.bluetooth => L.t.callRouteBluetooth,
                                  AudioRoute.wired => L.t.callRouteWired,
                                  _ => L.t.hautParleur,
                                },
                                selected: call.route != AudioRoute.earpiece,
                                onTap: _chooseRoute,
                              ),
                            ],
                          ),
                          const SizedBox(height: PrivioSpacing.l),
                          _RoundButton(
                            key: const Key('call.hangup'),
                            icon: Icons.call_end_rounded,
                            label: L.t.raccrocher,
                            color: PrivioColors.error,
                            onTap: () => _run(context, ctrl.hangUp),
                          ),
                        ],
                      ),
                    },
                  ),
                ],
              ),
            ),
            if (local != null) _localPreview(context, local, ctrl),
            if (_routes != null && call.phase != CallPhase.ended) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _routes = null),
                  child: const ColoredBox(color: Colors.black38),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _RoutePanel(routes: _routes!, current: call.route, onPick: _pick),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lot 9.2 : Privio quitté pendant un appel avec image → petite fenêtre : l'image seule.
class _PipView extends StatelessWidget {
  const _PipView({required this.call, required this.remote});

  final CallState call;
  final Widget? remote;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('call.pip'),
    color: Colors.black,
    child: call.peerCamera && remote != null
        ? remote!
        : Center(
            child: UserAvatar(
              name: call.info.peerName,
              avatarPath: call.info.peerAvatar,
              seed: call.info.peerId,
              radius: 32,
            ),
          ),
  );
}

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.routes, required this.current, required this.onPick});

  final List<AudioRoute> routes;
  final AudioRoute current;
  final ValueChanged<AudioRoute> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('call.routes'),
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.l),
              child: Text(L.t.callRouteTitle, style: theme.textTheme.titleMedium),
            ),
            for (final r in routes)
              ListTile(
                key: Key('call.route.${r.name}'),
                leading: Icon(routeIcon(r)),
                title: Text(routeLabel(r)),
                trailing: r == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => onPick(r),
              ),
          ],
        ),
      ),
    );
  }
}

IconData routeIcon(AudioRoute r) => switch (r) {
  AudioRoute.earpiece => Icons.phone_in_talk_rounded,
  AudioRoute.speaker => Icons.volume_up_rounded,
  AudioRoute.bluetooth => Icons.bluetooth_audio_rounded,
  AudioRoute.wired => Icons.headset_rounded,
};

String routeLabel(AudioRoute r) => switch (r) {
  AudioRoute.earpiece => L.t.callRouteEarpiece,
  AudioRoute.speaker => L.t.callRouteSpeaker,
  AudioRoute.bluetooth => L.t.callRouteBluetooth,
  AudioRoute.wired => L.t.callRouteWired,
};

/// Lot 9.1b : Android 14+ demande d'autoriser l'affichage des appels en plein écran
/// (téléphone verrouillé, Privio fermé). Proposé une seule fois.
Future<void> offerFullScreenCalls(BuildContext context, WidgetRef ref) async {
  final flags = ref.read(localFlagsProvider);
  final system = ref.read(callSystemProvider);
  if (await flags.fullScreenCallsAsked() || await system.fullScreenAllowed()) return;
  await flags.setFullScreenCallsAsked();
  if (!context.mounted) return;
  final allow = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      key: const Key('call.fullscreen'),
      title: Text(L.t.callFullScreenTitle),
      content: Text(L.t.callFullScreenBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(L.t.plusTard)),
        FilledButton(
          key: const Key('call.fullscreen.allow'),
          onPressed: () => Navigator.pop(d, true),
          child: Text(L.t.callFullScreenAllow),
        ),
      ],
    ),
  );
  if (allow == true) await system.openFullScreenSettings();
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
Future<void> startCallFrom(
  BuildContext context,
  WidgetRef ref,
  String conversationId, {
  bool video = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(callControllerProvider.notifier)
        .start(conversationId, kind: video ? 'video' : 'audio');
  } on Object catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}
