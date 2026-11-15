import '../../../l10n/l10n.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/voice_providers.dart';

/// Lot 7.3b : messages en vue unique et aperçus des liens.

/// Contenu d'une bulle « vue unique » : jamais de vignette, seulement un libellé.
class ViewOnceContent extends StatelessWidget {
  const ViewOnceContent({
    super.key,
    required this.message,
    required this.outgoing,
    this.isGroup = false,
    this.onOpen,
    this.opening = false,
  });

  final ChatMessage message;
  final bool outgoing;
  final bool isGroup;
  final VoidCallback? onOpen;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final fg = outgoing ? p.onBubbleOut : p.onBubbleIn;
    final muted = outgoing ? p.bubbleOutMeta : p.bubbleInMeta;
    final voice = message.kind == 'voice';
    final what = voice ? L.t.vocal : L.t.photo;
    final (String status, bool done) = outgoing
        ? _senderStatus(voice)
        : (
            message.opened ? (voice ? L.t.ecoute : L.t.ouverte) : L.t.toucherPourOuvrir,
            message.opened,
          );
    final canOpen = !outgoing && !message.opened && onOpen != null;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: done ? muted : fg, width: 2),
          ),
          child: opening
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Text(
                  '1',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: done ? muted : fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    voice ? Icons.mic_rounded : Icons.photo_outlined,
                    size: 18,
                    color: done ? muted : fg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L.t.whatVueUnique(what),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: done ? muted : fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                status,
                key: Key('view_once.status.${message.id}'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: canOpen,
      label: L.t.whatVueUniqueStatus(what, status),
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('view_once.${message.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: canOpen && !opening ? onOpen : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
        ),
      ),
    );
  }

  (String, bool) _senderStatus(bool voice) {
    final n = message.openedCount ?? 0;
    if (n == 0) return (voice ? L.t.pasEncoreEcoute : L.t.pasEncoreOuverte, false);
    if (!isGroup) return (voice ? L.t.ecoute : L.t.ouverte, true);
    return (voice ? L.t.ecouteParN(n) : L.t.ouverteParN(n), true);
  }
}

/// Bulle en attente d'envoi d'un média en vue unique (l'expéditeur ne le revoit pas).
class PendingViewOnceContent extends StatelessWidget {
  const PendingViewOnceContent({super.key, required this.voice});

  final bool voice;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(voice ? Icons.mic_rounded : Icons.photo_outlined, size: 18, color: p.onBubbleOut),
        const SizedBox(width: 6),
        Text(
          voice ? L.t.voiceViewOnce : L.t.photoViewOnce,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.onBubbleOut),
        ),
      ],
    );
  }
}

/// Photo en vue unique en plein écran : aucun bouton, captures bloquées (FLAG_SECURE),
/// fermée automatiquement au bout de 2 minutes (le serveur ne la sert plus ensuite).
class ViewOncePhotoScreen extends StatefulWidget {
  const ViewOncePhotoScreen({super.key, required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  static const limit = Duration(minutes: 2);

  @override
  State<ViewOncePhotoScreen> createState() => _ViewOncePhotoScreenState();
}

class _ViewOncePhotoScreenState extends State<ViewOncePhotoScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(ViewOncePhotoScreen.limit, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('view_once.viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          key: const Key('view_once.viewer.close'),
          tooltip: L.t.fermer,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
            Text(
              L.t.vueUniqueDisparaitFermeture,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.memory(widget.bytes, fit: BoxFit.contain, semanticLabel: L.t.photo),
          ),
        ),
      ),
    );
  }
}

/// Vocal en vue unique : écouté une fois depuis la mémoire, jamais rangé sur l'appareil.
Future<void> showViewOnceVoice(BuildContext context, Uint8List audio) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => _ViewOnceVoiceSheet(audio: audio),
);

class _ViewOnceVoiceSheet extends ConsumerStatefulWidget {
  const _ViewOnceVoiceSheet({required this.audio});

  final Uint8List audio;

  @override
  ConsumerState<_ViewOnceVoiceSheet> createState() => _ViewOnceVoiceSheetState();
}

class _ViewOnceVoiceSheetState extends ConsumerState<_ViewOnceVoiceSheet> {
  late final VoicePlayerController _player = ref.read(voicePlayerProvider.notifier);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_player.togglePreview(widget.audio).catchError((Object _) {}));
    _timer = Timer(ViewOncePhotoScreen.limit, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_player.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = ref.watch(voicePlayerProvider);
    final playing = playback.id == kPreviewId && playback.playing;
    return SafeArea(
      child: Padding(
        key: const Key('view_once.voice'),
        padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.t.vocalVueUnique, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              L.t.ilDisparaitQueVousFermez,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: PrivioSpacing.m),
            IconButton.filled(
              key: const Key('view_once.voice.play'),
              iconSize: 36,
              tooltip: playing ? L.t.pause : L.t.ecouter,
              onPressed: () => unawaited(_player.togglePreview(widget.audio)),
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            const SizedBox(height: PrivioSpacing.s),
            TextButton(
              key: const Key('view_once.voice.close'),
              onPressed: () => Navigator.pop(context),
              child: Text(L.t.fermer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image d'un aperçu de lien (stockage privé, avec le jeton).
final linkImageProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, path) => ref.watch(messagingApiProvider).downloadLinkImage(path),
);

/// Carte d'aperçu d'un lien, préparée par le serveur (l'application ne visite jamais le site).
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({super.key, required this.preview, required this.outgoing});

  final LinkPreview preview;
  final bool outgoing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final fg = outgoing ? p.onBubbleOut : p.onBubbleIn;
    final muted = outgoing ? p.bubbleOutMeta : p.bubbleInMeta;
    final path = preview.imagePath;
    final image = path == null ? null : ref.watch(linkImageProvider(path));
    final site = preview.site ?? Uri.tryParse(preview.url)?.host ?? '';
    return Semantics(
      button: true,
      label: L.t.apercuLienSite(preview.title ?? site),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          key: const Key('link.preview'),
          color: outgoing ? p.quoteOut : p.quoteIn,
          borderRadius: BorderRadius.circular(PrivioRadius.small + 2),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(openLink(context, preview.url)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image case AsyncData(:final value))
                    AspectRatio(
                      aspectRatio: _ratio(),
                      child: Image.memory(
                        value,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preview.title != null)
                          Text(
                            preview.title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (preview.description != null)
                          Text(
                            preview.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        if (site.isNotEmpty)
                          Text(
                            site,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _ratio() {
    final w = preview.imageWidth, h = preview.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return 1.91;
    return (w / h).clamp(1.0, 2.0);
  }
}

/// Ouvre un lien dans le navigateur, après confirmation (rien ne part sans un geste clair).
Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('link.confirm'),
      title: Text(L.t.ouvrirCeLien),
      content: Text(L.t.siteHostOuvriraDansVotre(uri.host)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('link.confirm.open'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.t.ouvrir),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
}

/// Interrupteur « vue unique » (un « 1 » cerclé, plein quand il est activé).
class ViewOnceToggle extends StatelessWidget {
  const ViewOnceToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.color,
    required this.activeColor,
    required this.onActiveColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  final Color activeColor;
  final Color onActiveColor;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: L.t.vueUnique,
    excludeSemantics: true,
    child: IconButton(
      tooltip: value ? L.t.vueUniqueActivee : L.t.vueUnique,
      onPressed: () => onChanged(!value),
      icon: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? activeColor : Colors.transparent,
          border: Border.all(color: value ? activeColor : color, width: 2),
        ),
        child: Text(
          '1',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: value ? onActiveColor : color,
          ),
        ),
      ),
    ),
  );
}
