import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/call_engine.dart' show AudioRoute;
import '../../../domain/models/group_call.dart';
import '../../../l10n/l10n.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/group_call_controller.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import 'call_screen.dart';

/// Lot 9.4 — écran d'un appel de groupe (ADR-052) : sonnerie (« Rejoindre » / « Refuser »),
/// puis mosaïque de 8 personnes au plus (image si la caméra est allumée, sinon photo et
/// nom ; micro coupé signalé). Posé au-dessus de toute l'application, comme l'appel à deux.
class GroupCallView extends ConsumerStatefulWidget {
  const GroupCallView({super.key});

  @override
  ConsumerState<GroupCallView> createState() => _GroupCallViewState();
}

class _GroupCallViewState extends ConsumerState<GroupCallView> {
  List<AudioRoute>? _routes;

  Future<void> _chooseRoute() async {
    final ctrl = ref.read(groupCallControllerProvider.notifier);
    final routes = await ctrl.audioRoutes();
    final call = ref.read(groupCallControllerProvider);
    if (routes.length <= 2) {
      await ctrl.selectRoute(
        call?.route == AudioRoute.speaker ? AudioRoute.earpiece : AudioRoute.speaker,
      );
    } else if (mounted) {
      setState(() => _routes = routes);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } on AppFailure catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _endText(GroupCallState c) => switch (c.endStatus) {
    'failed' => L.t.callFailed,
    'full' => L.t.groupCallFullError,
    'unavailable' => L.t.groupCallUnavailableError,
    _ =>
      c.connectedAt != null
          ? L.t.callEndedDuration(formatCallDuration(DateTime.now().difference(c.connectedAt!)))
          : L.t.callEnded,
  };

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(groupCallControllerProvider);
    if (call == null) return const SizedBox.shrink();
    final ctrl = ref.read(groupCallControllerProvider.notifier);
    final theme = Theme.of(context);
    final summary = ref.watch(conversationSummaryProvider(call.info.conversationId));
    // Privio verrouillé, discussion cachée : sonnerie sans nom (décision C, lot 10.2).
    final locked = ref.watch(appLockProvider).value?.locked ?? false;
    final hideName = (locked || (summary?.secret ?? false)) && call.phase == GroupCallPhase.ringing;
    final title = hideName
        ? (call.video ? L.t.groupCallVideoIncomingLocked : L.t.groupCallIncomingLocked)
        : (summary?.title ?? L.t.groupCallTitle);
    final white = theme.textTheme.bodyLarge?.copyWith(color: Colors.white70);
    final ringing = call.phase == GroupCallPhase.ringing;
    final status = switch (call.phase) {
      GroupCallPhase.ringing => Text(
        call.video ? L.t.groupCallVideoIncoming : L.t.groupCallIncoming,
        style: white,
      ),
      GroupCallPhase.joining => Text(L.t.callConnecting, style: white),
      GroupCallPhase.reconnecting => Text(L.t.callReconnecting, style: white),
      GroupCallPhase.connected => CallTicker(
        since: call.connectedAt ?? DateTime.now(),
        builder: (d) => Text(
          call.weak ? '$d · ${L.t.callWeak}' : d,
          style: call.weak ? white?.copyWith(color: const Color(0xFFFFC857)) : white,
        ),
      ),
      GroupCallPhase.ended => Text(_endText(call), style: white),
    };
    return Material(
      key: const Key('group_call.screen'),
      color: const Color(0xFF1B0B3D),
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
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.s,
                      PrivioSpacing.s,
                      PrivioSpacing.l,
                      0,
                    ),
                    child: Row(
                      children: [
                        if (ringing || !call.live)
                          const SizedBox(width: 48, height: 48)
                        else
                          CallRoundButton(
                            key: const Key('group_call.minimize'),
                            icon: Icons.keyboard_arrow_down_rounded,
                            label: L.t.reduire,
                            small: true,
                            onTap: () => ctrl.setMinimized(true),
                          ),
                        const SizedBox(width: PrivioSpacing.s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                key: const Key('group_call.title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              KeyedSubtree(key: const Key('group_call.status'), child: status),
                            ],
                          ),
                        ),
                        if (!ringing && call.live)
                          Text(
                            L.t.groupCallCount(call.info.joinedCount, call.info.max),
                            key: const Key('group_call.count'),
                            style: white,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ringing
                        ? _Ringing(
                            call: call,
                            hideName: hideName,
                            summaryAvatar: summary?.avatarPath,
                          )
                        : _Grid(call: call),
                  ),
                  if (call.cameraDenied)
                    Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.s),
                      child: Text(
                        L.t.callCameraDenied,
                        key: const Key('group_call.camera.denied'),
                        textAlign: TextAlign.center,
                        style: white?.copyWith(color: const Color(0xFFFFC857)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: PrivioSpacing.xl, top: PrivioSpacing.m),
                    child: switch (call.phase) {
                      GroupCallPhase.ringing => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          CallRoundButton(
                            key: const Key('group_call.decline'),
                            icon: Icons.call_end_rounded,
                            label: L.t.refuser2,
                            color: PrivioColors.error,
                            onTap: () => _run(ctrl.decline),
                          ),
                          CallRoundButton(
                            key: const Key('group_call.accept'),
                            icon: call.video ? Icons.videocam_rounded : Icons.call_rounded,
                            label: L.t.groupCallJoin,
                            color: PrivioColors.success,
                            onTap: () => _run(ctrl.accept),
                          ),
                        ],
                      ),
                      GroupCallPhase.ended => const SizedBox(height: 96),
                      _ => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          CallRoundButton(
                            key: const Key('group_call.mute'),
                            icon: call.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                            label: call.muted ? L.t.microCoupe : L.t.micro,
                            selected: call.muted,
                            onTap: ctrl.toggleMute,
                          ),
                          CallRoundButton(
                            key: const Key('group_call.camera'),
                            icon: call.camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            label: call.camera ? L.t.callCamera : L.t.callCameraOff,
                            selected: call.camera,
                            onTap: ctrl.toggleCamera,
                          ),
                          CallRoundButton(
                            key: const Key('group_call.speaker'),
                            icon: routeIcon(call.route),
                            label: switch (call.route) {
                              AudioRoute.bluetooth => L.t.callRouteBluetooth,
                              AudioRoute.wired => L.t.callRouteWired,
                              _ => L.t.hautParleur,
                            },
                            selected: call.route != AudioRoute.earpiece,
                            onTap: _chooseRoute,
                          ),
                          CallRoundButton(
                            key: const Key('group_call.hangup'),
                            icon: Icons.call_end_rounded,
                            label: L.t.groupCallLeave,
                            color: PrivioColors.error,
                            onTap: () => _run(ctrl.hangUp),
                          ),
                        ],
                      ),
                    },
                  ),
                ],
              ),
            ),
            if (_routes != null && call.live) ...[
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
                child: CallRoutePanel(
                  routes: _routes!,
                  current: call.route,
                  onPick: (r) async {
                    setState(() => _routes = null);
                    await ctrl.selectRoute(r);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sonnerie : photo du groupe, qui a lancé l'appel, qui est déjà dedans.
class _Ringing extends StatelessWidget {
  const _Ringing({required this.call, required this.hideName, this.summaryAvatar});

  final GroupCallState call;
  final bool hideName;
  final String? summaryAvatar;

  @override
  Widget build(BuildContext context) {
    final white = Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70);
    final starter = call.info.starterName;
    final inCall = call.info.joined;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hideName)
          const CircleAvatar(
            radius: 56,
            backgroundColor: Colors.white24,
            child: Icon(Icons.groups_rounded, size: 52, color: Colors.white),
          )
        else
          UserAvatar(
            name: '',
            avatarPath: summaryAvatar,
            seed: call.info.conversationId,
            radius: 56,
          ),
        const SizedBox(height: PrivioSpacing.l),
        if (!hideName && starter != null)
          Text(
            L.t.groupCallStartedBy(starter),
            key: const Key('group_call.starter'),
            style: white,
            textAlign: TextAlign.center,
          ),
        if (!hideName && inCall.isNotEmpty) ...[
          const SizedBox(height: PrivioSpacing.m),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: -8,
            children: [
              for (final p in inCall.take(6))
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF1B0B3D),
                  child: UserAvatar(name: p.name, avatarPath: p.avatar, seed: p.userId, radius: 16),
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(L.t.groupCallInCall(inCall.length), style: white),
        ],
      ],
    );
  }
}

/// Mosaïque : moi d'abord, puis les autres personnes dans l'appel (8 au plus).
class _Grid extends ConsumerWidget {
  const _Grid({required this.call});

  final GroupCallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(groupCallControllerProvider.notifier);
    final me = ref.watch(currentUserIdProvider);
    final others = [
      for (final p in call.info.joined)
        if (p.userId != me) p,
    ];
    GroupCallParticipant? mine;
    for (final p in call.info.participants) {
      if (p.userId == me) mine = p;
    }
    final tiles = <Widget>[
      _Tile(
        key: const Key('group_call.tile.me'),
        name: L.t.groupCallMe,
        userId: me ?? '',
        avatar: mine?.avatar,
        muted: call.muted,
        video: call.live && call.camera ? ctrl.localView() : null,
        onFlip: call.camera ? ctrl.switchCamera : null,
      ),
      for (final p in others)
        _Tile(
          key: Key('group_call.tile.${p.userId}'),
          name: p.name,
          userId: p.userId,
          avatar: p.avatar,
          muted: p.muted,
          video: call.live && p.camera ? ctrl.remoteView(p.userId) : null,
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final n = tiles.length;
        final cols = n <= 2 ? 1 : 2;
        final rows = (n / cols).ceil();
        const gap = 6.0;
        final w = (box.maxWidth - PrivioSpacing.m * 2 - gap * (cols - 1)) / cols;
        final h = math.max(80.0, (box.maxHeight - PrivioSpacing.m * 2 - gap * (rows - 1)) / rows);
        return Padding(
          padding: const EdgeInsets.all(PrivioSpacing.m),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.center,
            children: [for (final t in tiles) SizedBox(width: w, height: h, child: t)],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.name,
    required this.userId,
    required this.muted,
    this.avatar,
    this.video,
    this.onFlip,
  });

  final String name;
  final String userId;
  final String? avatar;
  final bool muted;
  final Widget? video;
  final VoidCallback? onFlip;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: const Color(0x33FFFFFF),
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  video ??
                  Center(
                    child: LayoutBuilder(
                      builder: (_, box) => UserAvatar(
                        name: name,
                        avatarPath: avatar,
                        seed: userId,
                        radius: math.min(44, math.min(box.maxWidth, box.maxHeight) / 3),
                      ),
                    ),
                  ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Row(
                children: [
                  if (muted)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.mic_off_rounded, size: 16, color: Colors.white),
                    ),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label?.copyWith(
                        shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
                  ),
                  if (onFlip != null)
                    InkWell(
                      key: const Key('group_call.flip'),
                      onTap: onFlip,
                      child: const Icon(Icons.cameraswitch_rounded, size: 20, color: Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau en haut de l'écran pendant un appel de groupe réduit.
class GroupCallBar extends ConsumerWidget {
  const GroupCallBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(groupCallControllerProvider)!;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white);
    return Material(
      color: PrivioColors.success,
      child: InkWell(
        key: const Key('group_call.bar'),
        onTap: () => ref.read(groupCallControllerProvider.notifier).setMinimized(false),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: PrivioSpacing.l),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.groups_rounded, color: Colors.white, size: 18),
                const SizedBox(width: PrivioSpacing.s),
                Flexible(
                  child: call.connectedAt == null
                      ? Text(L.t.callConnecting, style: style)
                      : CallTicker(
                          since: call.connectedAt!,
                          builder: (d) =>
                              Text(L.t.groupCallBar(d, call.info.joinedCount), style: style),
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

/// Bandeau d'une discussion de groupe : « Appel de groupe en cours · 3 personnes —
/// Rejoindre » (quand je n'y suis pas).
class GroupCallBanner extends ConsumerWidget {
  const GroupCallBanner({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(groupCallInProvider(conversationId));
    final mine = ref.watch(groupCallControllerProvider);
    if (call == null || !call.active || call.joinedMe || mine?.info.id == call.id) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Material(
      key: const Key('group_call.banner'),
      color: PrivioColors.success.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l, vertical: 6),
        child: Row(
          children: [
            Icon(
              call.video ? Icons.videocam_rounded : Icons.call_rounded,
              color: PrivioColors.success,
              size: 20,
            ),
            const SizedBox(width: PrivioSpacing.s),
            Expanded(
              child: Text(
                L.t.groupCallOngoing(call.joinedCount),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FilledButton(
              key: const Key('group_call.banner.join'),
              style: FilledButton.styleFrom(backgroundColor: PrivioColors.success),
              onPressed: call.full ? null : () => joinGroupCallFrom(context, ref, call.id),
              child: Text(call.full ? L.t.groupCallFullShort : L.t.groupCallJoin),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lance un appel de groupe (bouton 📞 ou 🎥 d'un groupe) ; erreur affichée sur place.
Future<void> startGroupCallFrom(
  BuildContext context,
  WidgetRef ref,
  String conversationId, {
  bool video = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(groupCallControllerProvider.notifier)
        .start(conversationId, kind: video ? 'video' : 'audio');
  } on Object catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

Future<void> joinGroupCallFrom(BuildContext context, WidgetRef ref, String callId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(groupCallControllerProvider.notifier).join(callId);
  } on Object catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}
