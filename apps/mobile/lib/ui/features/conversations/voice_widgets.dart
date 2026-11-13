import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/voice_providers.dart';

/// « 0:07 », « 1:05 ».
String formatVoiceDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Libellé lisible par TalkBack : « 12 secondes ».
String spokenVoiceDuration(Duration d) {
  final s = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).round();
  return s <= 1 ? '$s seconde' : '$s secondes';
}

String _speedLabel(double speed) => '${speed == speed.roundToDouble() ? speed.toInt() : '1,5'}×';

/// Fine barre de progression, touchable pour se déplacer dans le son.
class _Track extends StatelessWidget {
  const _Track({
    required this.progress,
    required this.color,
    required this.background,
    this.onSeek,
  });

  final double progress;
  final Color color;
  final Color background;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onSeek == null
          ? null
          : (d) => onSeek!((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 4,
            color: color,
            backgroundColor: background,
          ),
        ),
      ),
    ),
  );
}

/// Contenu d'une bulle vocale : écouter / pause, progression, durée, vitesse.
class VoiceMessageContent extends ConsumerWidget {
  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.outgoing,
    required this.onError,
  });

  final ChatMessage message;
  final bool outgoing;
  final void Function(AppFailure failure) onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final playback = ref.watch(voicePlayerProvider);
    final player = ref.read(voicePlayerProvider.notifier);
    final fg = outgoing ? p.onBubbleOut : p.onBubbleIn;
    final meta = outgoing ? p.bubbleOutMeta : p.bubbleInMeta;
    final current = playback.id == message.id;
    final total = Duration(milliseconds: message.durationMs ?? 0);
    final position = current ? playback.position : Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / total.inMilliseconds;
    final metaStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: meta);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on AppFailure catch (f) {
        onError(f);
      }
    }

    return Semantics(
      label: 'Message vocal, ${spokenVoiceDuration(total)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: current && playback.loading
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                  )
                : IconButton(
                    key: Key('voice.play.${message.id}'),
                    padding: EdgeInsets.zero,
                    tooltip: current && playback.playing ? 'Pause' : 'Écouter le message vocal',
                    onPressed: () => run(() => player.toggle(message)),
                    icon: Icon(
                      current && playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 32,
                      color: fg,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: _Track(
                    progress: progress,
                    color: fg,
                    background: meta.withValues(alpha: 0.35),
                    onSeek: current && !playback.loading
                        ? (f) => run(() => player.seek(total * f))
                        : null,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.mic_none_rounded, size: 13, color: meta),
                    const SizedBox(width: 2),
                    Text(
                      formatVoiceDuration(current && position > Duration.zero ? position : total),
                      key: Key('voice.duration.${message.id}'),
                      style: metaStyle,
                    ),
                    const Spacer(),
                    if (current && !playback.loading)
                      InkWell(
                        key: const Key('voice.speed'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => run(player.cycleSpeed),
                        child: Semantics(
                          button: true,
                          label: 'Vitesse de lecture ${_speedLabel(playback.speed)}',
                          child: ExcludeSemantics(
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 24),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: meta.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _speedLabel(playback.speed),
                                style: metaStyle?.copyWith(fontWeight: FontWeight.w600, color: fg),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulle d'un vocal pas encore parti (file d'envoi).
class PendingVoiceContent extends StatelessWidget {
  const PendingVoiceContent({super.key, required this.durationMs});

  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic_rounded, size: 20, color: p.onBubbleOut),
        const SizedBox(width: 6),
        Text(
          'Message vocal · ${formatVoiceDuration(Duration(milliseconds: durationMs ?? 0))}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: p.onBubbleOut),
        ),
      ],
    );
  }
}

/// Point rouge qui pulse pendant l'enregistrement.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, shape: BoxShape.circle),
    ),
  );
}

/// Bandeau d'enregistrement (à la place du champ de saisie).
class VoiceRecordingStrip extends ConsumerWidget {
  const VoiceRecordingStrip({super.key, required this.recording});

  final VoiceRecording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final ending = recording.remaining <= const Duration(seconds: 5);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      label:
          'Enregistrement en cours, ${spokenVoiceDuration(recording.elapsed)} '
          'sur ${spokenVoiceDuration(recording.max)}',
      child: Row(
        children: [
          if (recording.locked)
            IconButton(
              key: const Key('voice.cancel'),
              tooltip: 'Annuler l’enregistrement',
              onPressed: () => ref.read(voiceRecorderControllerProvider.notifier).cancel(),
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            )
          else
            const SizedBox(width: 18),
          const _RecordingDot(),
          const SizedBox(width: PrivioSpacing.s),
          ExcludeSemantics(
            child: Text(
              formatVoiceDuration(recording.elapsed),
              key: const Key('voice.elapsed'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: ending ? theme.colorScheme.error : theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: PrivioSpacing.m),
          Expanded(
            child: ExcludeSemantics(
              child: recording.locked || ending
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ending
                              ? 'Arrêt dans ${recording.remaining.inSeconds + 1} s'
                              : '${recording.max.inSeconds} s max.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ending ? theme.colorScheme.error : secondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: recording.elapsed.inMilliseconds / recording.max.inMilliseconds,
                            minHeight: 3,
                            color: ending ? theme.colorScheme.error : p.accentText,
                            backgroundColor: p.divider,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Icons.chevron_left, size: 18, color: secondary),
                        Flexible(
                          child: Text(
                            'Glisser pour annuler',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                          ),
                        ),
                        const SizedBox(width: PrivioSpacing.s),
                        Icon(Icons.lock_outline, size: 16, color: secondary),
                        Icon(Icons.keyboard_arrow_up, size: 18, color: secondary),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: PrivioSpacing.s),
        ],
      ),
    );
  }
}

/// Préécoute avant envoi (VOICE-004) : écouter, supprimer ou envoyer.
class VoicePreviewBar extends ConsumerWidget {
  const VoicePreviewBar({
    super.key,
    required this.preview,
    required this.onSend,
    required this.onError,
  });

  final VoicePreview preview;
  final VoidCallback onSend;
  final void Function(AppFailure failure) onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
    final playback = ref.watch(voicePlayerProvider);
    final player = ref.read(voicePlayerProvider.notifier);
    final current = playback.id == kPreviewId;
    final position = current ? playback.position : Duration.zero;
    final total = preview.duration;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on AppFailure catch (f) {
        onError(f);
      } on Object {
        onError(const AppFailure(FailureCode.unknown));
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.s,
          PrivioSpacing.xs,
          PrivioSpacing.s,
          PrivioSpacing.m,
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                key: const Key('voice.preview'),
                padding: const EdgeInsets.only(right: PrivioSpacing.m),
                decoration: BoxDecoration(
                  color: dark ? p.field : p.sheet,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('voice.discard'),
                      tooltip: 'Supprimer l’enregistrement',
                      onPressed: () =>
                          run(ref.read(voiceRecorderControllerProvider.notifier).discard),
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    ),
                    IconButton(
                      key: const Key('voice.preview_play'),
                      tooltip: current && playback.playing ? 'Pause' : 'Écouter avant d’envoyer',
                      onPressed: () => run(() => player.togglePreview(preview.audio)),
                      icon: Icon(
                        current && playback.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: p.accentText,
                        size: 30,
                      ),
                    ),
                    Expanded(
                      child: ExcludeSemantics(
                        child: _Track(
                          progress: total.inMilliseconds == 0
                              ? 0
                              : position.inMilliseconds / total.inMilliseconds,
                          color: p.accentText,
                          background: p.divider,
                          onSeek: current ? (f) => run(() => player.seek(total * f)) : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: PrivioSpacing.s),
                    Text(
                      formatVoiceDuration(current && position > Duration.zero ? position : total),
                      semanticsLabel: spokenVoiceDuration(total),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.s),
            SizedBox(
              width: 50,
              height: 50,
              child: IconButton.filled(
                key: const Key('voice.send'),
                tooltip: 'Envoyer le message vocal',
                style: IconButton.styleFrom(
                  backgroundColor: dark ? PrivioColors.lilac : PrivioColors.purple,
                  foregroundColor: dark ? PrivioColors.navy : Colors.white,
                ),
                onPressed: onSend,
                icon: const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton micro : toucher = enregistrement verrouillé (mains libres, accessible) ;
/// maintenir = enregistrer tant que le doigt reste posé, glisser à gauche pour annuler,
/// vers le haut pour verrouiller ; lever le doigt = préécoute.
class MicButton extends ConsumerWidget {
  const MicButton({super.key, required this.onStart, required this.onRelease});

  final Future<void> Function({required bool locked}) onStart;
  final Future<void> Function() onRelease;

  static const cancelDistance = 90.0;
  static const lockDistance = 70.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final recording = ref.watch(voiceRecorderControllerProvider) is VoiceRecording;
    final ctrl = ref.read(voiceRecorderControllerProvider.notifier);
    final bg = recording
        ? Theme.of(context).colorScheme.error
        : (dark ? PrivioColors.lilac : PrivioColors.purple);
    final fg = recording ? Colors.white : (dark ? PrivioColors.navy : Colors.white);
    return Semantics(
      button: true,
      label: 'Enregistrer un message vocal',
      onTapHint: 'enregistrer',
      child: GestureDetector(
        key: const Key('chat.mic'),
        onTap: () => onStart(locked: true),
        onLongPressStart: (_) {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(onStart(locked: false));
        },
        onLongPressMoveUpdate: (d) {
          if (d.offsetFromOrigin.dx < -cancelDistance) {
            unawaited(ctrl.cancel());
          } else if (d.offsetFromOrigin.dy < -lockDistance) {
            ctrl.lock();
          }
        },
        onLongPressEnd: (_) => unawaited(onRelease()),
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: recording ? 58 : 50,
            height: recording ? 58 : 50,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(Icons.mic_rounded, color: fg, size: recording ? 30 : 26),
          ),
        ),
      ),
    );
  }
}
