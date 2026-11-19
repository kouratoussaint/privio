import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/media/waveform.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/voice_providers.dart';
import 'rich_messages.dart';

/// « 0:07 », « 1:05 ».
String formatVoiceDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Libellé lisible par TalkBack : « 12 secondes ».
String spokenVoiceDuration(Duration d) {
  final s = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).round();
  return L.t.secondsSpoken(s);
}

String _speedLabel(double speed) => '${speed == speed.roundToDouble() ? speed.toInt() : '1,5'}×';

/// Spectre d'un vocal (lot 4.5) : barres tirées du profil sonore, colorées jusqu'à la
/// position d'écoute ; toucher ou glisser fait sauter à cet endroit.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.waveform,
    required this.progress,
    required this.color,
    required this.background,
    this.onSeek,
    this.height = 28,
  });

  /// Profil 0..100 (null : spectre neutre, ancien vocal).
  final List<int>? waveform;
  final double progress;
  final Color color;
  final Color background;
  final ValueChanged<double>? onSeek;
  final double height;

  static const barWidth = 3.0;
  static const gap = 2.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = ((box.maxWidth + gap) / (barWidth + gap)).floor().clamp(8, 64);
      void seek(Offset at) => onSeek?.call((at.dx / box.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
        onHorizontalDragUpdate: onSeek == null ? null : (d) => seek(d.localPosition),
        child: SizedBox(
          height: height + 8,
          width: box.maxWidth,
          child: CustomPaint(
            painter: _BarsPainter(
              bars: displayBars(waveform, count),
              progress: progress.clamp(0.0, 1.0),
              color: color,
              background: background,
            ),
          ),
        ),
      );
    },
  );
}

/// Spectre en direct pendant l'enregistrement : les derniers niveaux, alignés à droite.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({super.key, required this.levels, required this.color, this.height = 24});

  final List<double> levels;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count =
          ((box.maxWidth + VoiceWaveform.gap) / (VoiceWaveform.barWidth + VoiceWaveform.gap))
              .floor()
              .clamp(4, 96);
      final shown = levels.length > count ? levels.sublist(levels.length - count) : levels;
      final bars = [
        for (var i = 0; i < count - shown.length; i++) 0.06,
        for (final l in shown) l.clamp(0.06, 1.0),
      ];
      return SizedBox(
        key: const Key('voice.live_waveform'),
        height: height,
        width: box.maxWidth,
        child: CustomPaint(
          painter: _BarsPainter(bars: bars, progress: 1, color: color, background: color),
        ),
      );
    },
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.bars,
    required this.progress,
    required this.color,
    required this.background,
  });

  final List<double> bars;
  final double progress;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final step = size.width / bars.length;
    final w = (step - VoiceWaveform.gap).clamp(1.5, VoiceWaveform.barWidth);
    final played = Paint()..color = color;
    final rest = Paint()..color = background;
    for (var i = 0; i < bars.length; i++) {
      final h = (bars[i] * size.height).clamp(2.0, size.height);
      final x = i * step + (step - w) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, w, h),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(rect, (i + 0.5) / bars.length <= progress ? played : rest);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.background != background ||
      !_sameBars(old.bars, bars);

  static bool _sameBars(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
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
      label: L.t.messageVocalTotal(spokenVoiceDuration(total)),
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
                    tooltip: current && playback.playing ? L.t.pause : L.t.ecouterMessageVocal,
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
                  child: VoiceWaveform(
                    key: Key('voice.waveform.${message.id}'),
                    waveform: message.waveform,
                    progress: progress,
                    color: fg,
                    background: meta.withValues(alpha: 0.45),
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
                          label: L.t.vitesseLectureSpeed(_speedLabel(playback.speed)),
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
        // Lot 6.1 : grands caractères / bulle étroite → le texte se coupe au lieu de déborder.
        Flexible(
          child: Text(
            L.t.messageVocalDurationms2(
              formatVoiceDuration(Duration(milliseconds: durationMs ?? 0)),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: p.onBubbleOut),
          ),
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
  const VoiceRecordingStrip({super.key, required this.recording, this.onListen});

  final VoiceRecording recording;

  /// Lot 9.3 : envoi direct → « Arrêter et écouter » dans le bandeau (enregistrement
  /// verrouillé), le bouton de droite envoyant le vocal.
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final ending = recording.remaining <= const Duration(seconds: 5);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final ctrl = ref.read(voiceRecorderControllerProvider.notifier);
    return Semantics(
      liveRegion: true,
      label: (recording.paused ? L.t.recordingPaused : L.t.recordingRunning)(
        spokenVoiceDuration(recording.elapsed),
        spokenVoiceDuration(recording.max),
      ),
      child: Row(
        children: [
          if (recording.locked)
            IconButton(
              key: const Key('voice.cancel'),
              tooltip: L.t.annulerEnregistrement,
              onPressed: () => ref.read(voiceRecorderControllerProvider.notifier).cancel(),
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            )
          else
            const SizedBox(width: 18),
          if (recording.paused)
            Icon(Icons.pause_rounded, size: 14, color: secondary)
          else
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
                          recording.paused
                              ? L.t.pause2
                              : ending
                              ? L.t.arretDansInseconds(recording.remaining.inSeconds + 1)
                              : L.t.insecondsMax(recording.max.inSeconds),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ending && !recording.paused
                                ? theme.colorScheme.error
                                : secondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        LiveWaveform(
                          levels: recording.levels,
                          color: recording.paused
                              ? p.divider
                              : (ending ? theme.colorScheme.error : p.accentText),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Icons.chevron_left, size: 18, color: secondary),
                        Flexible(
                          child: Text(
                            L.t.glisserPourAnnuler,
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
          if (recording.locked && onListen != null)
            IconButton(
              key: const Key('voice.stop'),
              tooltip: L.t.arreterEcouter,
              onPressed: onListen,
              icon: Icon(Icons.hearing_rounded, color: p.accentText),
            ),
          if (recording.locked)
            IconButton(
              key: const Key('voice.pause'),
              tooltip: recording.paused ? L.t.reprendreEnregistrement : L.t.mettrePause,
              onPressed: () => unawaited(ctrl.togglePause()),
              icon: Icon(
                recording.paused ? Icons.fiber_manual_record : Icons.pause_rounded,
                color: recording.paused ? theme.colorScheme.error : p.accentText,
              ),
            )
          else
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
    this.viewOnce = false,
    this.onViewOnce,
  });

  final VoicePreview preview;
  final VoidCallback onSend;

  /// Lot 7.3b : vocal en vue unique (null : pas d'interrupteur).
  final bool viewOnce;
  final ValueChanged<bool>? onViewOnce;
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
                      tooltip: L.t.supprimerEnregistrement,
                      onPressed: () =>
                          run(ref.read(voiceRecorderControllerProvider.notifier).discard),
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    ),
                    IconButton(
                      key: const Key('voice.preview_play'),
                      tooltip: current && playback.playing ? L.t.pause : L.t.ecouterAvantEnvoyer,
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
                        child: VoiceWaveform(
                          key: const Key('voice.preview_waveform'),
                          waveform: preview.waveform,
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
                    if (onViewOnce != null)
                      ViewOnceToggle(
                        key: const Key('voice.once'),
                        value: viewOnce,
                        onChanged: onViewOnce!,
                        color: theme.colorScheme.onSurfaceVariant,
                        activeColor: p.accentText,
                        onActiveColor: theme.colorScheme.surface,
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
                tooltip: L.t.envoyerMessageVocal,
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
      label: L.t.enregistrerMessageVocal,
      onTapHint: L.t.hintRecord,
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
