import '../../../l10n/l10n.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/photo_picker.dart';
import '../../../domain/models/stickers.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/providers.dart';
import '../../../state/sticker_providers.dart';
import '../../core/widgets/success_snack.dart';

/// Lot 7.4 — créer un autocollant (ADR-051) : photo, détourage automatique sur le
/// téléphone (Google ML Kit), recadrage (pincer, glisser), texte facultatif,
/// « Partageable ». Image finale : PNG transparent de 512 px.

/// Détoure le sujet principal d'une photo (PNG transparent), ou null si impossible
/// (modèle absent, hors connexion au premier usage, aucun sujet trouvé).
typedef SubjectCutout = Future<Uint8List?> Function(Uint8List photo);

final subjectCutoutProvider = Provider<SubjectCutout>((ref) => mlKitCutout);

Future<Uint8List?> mlKitCutout(Uint8List photo) async {
  File? file;
  final segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );
  try {
    final dir = await getTemporaryDirectory();
    file = File('${dir.path}/privio_sticker_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(photo, flush: true);
    final result = await segmenter.processImage(InputImage.fromFilePath(file.path));
    return result.foregroundBitmap;
  } on Object {
    return null;
  } finally {
    unawaited(segmenter.close().catchError((Object _) {}));
    if (file != null) unawaited(file.delete().then((_) {}, onError: (Object _) {}));
  }
}

/// Image du cadre (PNG). Remplacée dans les tests (le rendu réel demande le moteur).
typedef StickerRenderer = Future<Uint8List> Function(GlobalKey boundary);

final stickerRendererProvider = Provider<StickerRenderer>((ref) => renderStickerBoundary);

/// Taille du cadre à l'écran et de l'image finale.
const kStickerFrame = 256.0;
const kStickerPixels = 512;
const kStickerMaxBytes = 500 * 1024;

Future<Uint8List> renderStickerBoundary(GlobalKey boundary) async {
  final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: kStickerPixels / kStickerFrame);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return shrinkSticker(data!.buffer.asUint8List());
}

/// Garde l'image sous 500 Ko (PNG d'une photo non détourée) en réduisant ses côtés.
Uint8List shrinkSticker(Uint8List png) {
  if (png.length <= kStickerMaxBytes) return png;
  final decoded = img.decodePng(png);
  if (decoded == null) return png;
  for (final side in [448, 384, 320, 256]) {
    final out = img.encodePng(img.copyResize(decoded, width: side, height: side), level: 9);
    if (out.length <= kStickerMaxBytes) return out;
  }
  return img.encodePng(img.copyResize(decoded, width: 192, height: 192), level: 9);
}

/// Parcours complet depuis le panneau des autocollants : source, détourage, édition,
/// enregistrement dans ma collection. Renvoie l'autocollant créé, ou null.
Future<StickerItem?> createSticker(BuildContext context, WidgetRef ref) async {
  final source = await showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(L.t.nouvelAutocollant, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text(L.t.nouvelAutocollantAide),
          ),
          ListTile(
            key: const Key('sticker.source.camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(L.t.prendrePhoto),
            onTap: () => Navigator.pop(ctx, PhotoSource.camera),
          ),
          ListTile(
            key: const Key('sticker.source.gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(L.t.choisirDansGalerie),
            onTap: () => Navigator.pop(ctx, PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final raw = await ref
        .read(appLockProvider.notifier)
        .runExternal(() => ref.read(photoPickerProvider).pick(source));
    if (raw == null || !context.mounted) return null;
    // Photo réduite et sans métadonnées, comme pour un envoi.
    final photo = await ref.read(photoPreparerProvider)(raw);
    if (!context.mounted) return null;
    final item = await nav.push<StickerItem>(
      MaterialPageRoute(
        builder: (_) => StickerEditorScreen(photo: photo.bytes),
        fullscreenDialog: true,
      ),
    );
    if (item != null) messenger.showSnackBar(successSnack(L.t.autocollantAjoute));
    return item;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    return null;
  }
}

class StickerEditorScreen extends ConsumerStatefulWidget {
  const StickerEditorScreen({super.key, required this.photo});

  final Uint8List photo;

  @override
  ConsumerState<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends ConsumerState<StickerEditorScreen> {
  final _boundary = GlobalKey();
  final _text = TextEditingController();
  final _view = TransformationController();
  Uint8List? _cutout;
  bool _cutting = true;
  bool _useCutout = true;
  bool _shareable = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_cut());
  }

  Future<void> _cut() async {
    Uint8List? cut;
    try {
      cut = await ref.read(subjectCutoutProvider)(widget.photo);
    } on Object {
      cut = null;
    }
    if (!mounted) return;
    setState(() {
      _cutout = cut;
      _useCutout = cut != null;
      _cutting = false;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _view.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Une image de plus pour que le clavier fermé ne figure pas dans le rendu.
      await WidgetsBinding.instance.endOfFrame;
      final png = await ref.read(stickerRendererProvider)(_boundary);
      final item = await ref.read(myStickersProvider.notifier).add(png, shareable: _shareable);
      if (mounted) Navigator.of(context).pop(item);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final image = _useCutout && _cutout != null ? _cutout! : widget.photo;
    final caption = _text.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(L.t.nouvelAutocollant),
        actions: [
          TextButton(
            key: const Key('sticker.save'),
            onPressed: _cutting || _saving ? null : _save,
            child: Text(L.t.enregistrer),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Damier (fond transparent), hors de l'image enregistrée.
                const _Checkerboard(size: kStickerFrame),
                RepaintBoundary(
                  key: _boundary,
                  child: SizedBox.square(
                    dimension: kStickerFrame,
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            key: const Key('sticker.frame'),
                            transformationController: _view,
                            minScale: 0.5,
                            maxScale: 5,
                            boundaryMargin: const EdgeInsets.all(kStickerFrame),
                            child: Image.memory(
                              image,
                              key: Key(_useCutout ? 'sticker.cutout' : 'sticker.photo'),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                          if (caption.isNotEmpty)
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 10,
                              child: IgnorePointer(child: _OutlinedCaption(caption)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_cutting)
                  Column(
                    key: const Key('sticker.cutting'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: PrivioSpacing.s),
                      Text(L.t.detourageEnCours, style: theme.textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            L.t.autocollantRecadrerAide,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: PrivioSpacing.m),
          SwitchListTile(
            key: const Key('sticker.cutout_switch'),
            contentPadding: EdgeInsets.zero,
            value: _useCutout && _cutout != null,
            onChanged: _cutout == null ? null : (v) => setState(() => _useCutout = v),
            secondary: Icon(Icons.auto_fix_high_outlined, color: p.accentText),
            title: Text(L.t.detourerSujet),
            subtitle: _cutting || _cutout != null ? null : Text(L.t.detourageImpossible),
          ),
          TextField(
            key: const Key('sticker.text'),
            controller: _text,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: L.t.texteFacultatif),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            key: const Key('sticker.shareable'),
            contentPadding: EdgeInsets.zero,
            value: _shareable,
            onChanged: (v) => setState(() => _shareable = v),
            secondary: Icon(Icons.share_outlined, color: p.accentText),
            title: Text(L.t.autocollantPartageable),
            subtitle: Text(
              _shareable ? L.t.autocollantPartageableOui : L.t.autocollantPartageableNon,
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

/// Texte blanc cerné de noir, lisible sur toute image.
class _OutlinedCaption extends StatelessWidget {
  const _OutlinedCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1);
    return Stack(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          key: const Key('sticker.caption'),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: style.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

class _Checkerboard extends StatelessWidget {
  const _Checkerboard({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _CheckerPainter(Theme.of(context).colorScheme.outlineVariant)),
  );
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 16.0;
    final paint = Paint()..color = color.withValues(alpha: 0.35);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x + y) / cell).round().isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => old.color != color;
}

/// Image d'un autocollant personnel (ma collection, ou un message).
class CustomStickerImage extends ConsumerWidget {
  const CustomStickerImage({super.key, required this.path, this.size = 140});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(stickerBytesProvider(path));
    return Semantics(
      label: L.t.stickerNoLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: switch (bytes) {
          AsyncData(:final value) => Image.memory(
            value,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
          AsyncError() => const Center(child: Icon(Icons.broken_image_outlined)),
          _ => const Center(child: Icon(Icons.emoji_emotions_outlined)),
        },
      ),
    );
  }
}
