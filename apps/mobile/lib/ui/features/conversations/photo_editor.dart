import '../../../l10n/l10n.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../core/media/photo_processing.dart';
import '../../../core/theme/privio_tokens.dart';

/// Lot 7.3a : retouche d'une photo avant l'envoi : pivoter, recadrer, dessiner.
///
/// Tout se fait sur le téléphone, sur la photo déjà réduite et sans métadonnées ; le
/// résultat est de nouveau un JPEG (mêmes limites de taille).

/// Couleurs du crayon.
const kPenColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF111A42),
  Color(0xFFE63946),
  Color(0xFFFFC43D),
  Color(0xFF13866B),
  Color(0xFF8A35F2),
];

/// Un trait : points en coordonnées relatives à l'image (0 à 1), épaisseur relative à sa
/// largeur.
class PenStroke {
  PenStroke(this.color, this.width);

  final Color color;
  final double width;
  final List<Offset> points = [];
}

PreparedPhoto _encode(img.Image image, int quality) => PreparedPhoto(
  bytes: Uint8List.fromList(img.encodeJpg(image, quality: quality)),
  width: image.width,
  height: image.height,
  quality: quality,
);

img.Image _decode(Uint8List bytes) => img.decodeImage(bytes)!;

/// Pivote d'un quart de tour vers la gauche.
PreparedPhoto rotatePhotoLeft(Uint8List bytes, [int quality = kPhotoQuality]) =>
    _encode(img.copyRotate(_decode(bytes), angle: -90), quality);

/// Recadre selon un rectangle relatif (0 à 1).
PreparedPhoto cropPhoto(
  Uint8List bytes,
  double l,
  double t,
  double r,
  double b, [
  int quality = kPhotoQuality,
]) {
  final image = _decode(bytes);
  final x = (l * image.width).round().clamp(0, image.width - 1);
  final y = (t * image.height).round().clamp(0, image.height - 1);
  final w = ((r - l) * image.width).round().clamp(1, image.width - x);
  final h = ((b - t) * image.height).round().clamp(1, image.height - y);
  return _encode(img.copyCrop(image, x: x, y: y, width: w, height: h), quality);
}

/// Trace les traits dans l'image : (couleur ARGB, épaisseur relative, points relatifs).
PreparedPhoto drawOnPhoto(
  Uint8List bytes,
  List<(int, double, List<(double, double)>)> strokes, [
  int quality = kPhotoQuality,
]) {
  final image = _decode(bytes);
  for (final (argb, width, points) in strokes) {
    final c = img.ColorRgb8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
    final thick = (width * image.width).clamp(2.0, 80.0);
    final pts = [for (final (x, y) in points) (x * image.width, y * image.height)];
    for (var i = 0; i < pts.length; i++) {
      final (x, y) = pts[i];
      img.fillCircle(image, x: x.round(), y: y.round(), radius: (thick / 2).round(), color: c);
      if (i > 0) {
        final (px, py) = pts[i - 1];
        img.drawLine(
          image,
          x1: px.round(),
          y1: py.round(),
          x2: x.round(),
          y2: y.round(),
          color: c,
          thickness: thick,
          antialias: true,
        );
      }
    }
  }
  return _encode(image, quality);
}

/// Une retouche à faire hors du fil de l'interface. Uniquement des données simples : un
/// isolat ne peut recevoir ni l'écran ni ses objets (cause du blocage de la 1re version,
/// où l'opération était une fonction anonyme liée à l'écran).
class PhotoEdit {
  const PhotoEdit.rotate(this.bytes, {this.quality = kPhotoQuality})
    : kind = 'rotate',
      rect = const [],
      strokes = const [];
  const PhotoEdit.crop(this.bytes, this.rect, {this.quality = kPhotoQuality})
    : kind = 'crop',
      strokes = const [];
  const PhotoEdit.draw(this.bytes, this.strokes, {this.quality = kPhotoQuality})
    : kind = 'draw',
      rect = const [];

  const PhotoEdit._(this.kind, this.bytes, this.rect, this.strokes, this.quality);

  /// Lot 10.3 : même qualité JPEG que la photo retouchée (Mode éco).
  PhotoEdit withQuality(int q) => PhotoEdit._(kind, bytes, rect, strokes, q);

  final int quality;
  final String kind;
  final Uint8List bytes;

  /// Recadrage : gauche, haut, droite, bas (0 à 1).
  final List<double> rect;

  /// Traits : (couleur ARGB, épaisseur relative, points relatifs).
  final List<(int, double, List<(double, double)>)> strokes;
}

/// Point d'entrée de l'isolat (fonction de premier niveau).
PreparedPhoto applyPhotoEdit(PhotoEdit e) => switch (e.kind) {
  'rotate' => rotatePhotoLeft(e.bytes, e.quality),
  'crop' => cropPhoto(e.bytes, e.rect[0], e.rect[1], e.rect[2], e.rect[3], e.quality),
  _ => drawOnPhoto(e.bytes, e.strokes, e.quality),
};

enum _Tool { none, crop, draw }

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.photo});

  final PreparedPhoto photo;

  /// Vrai dans les tests : le travail se fait sans isolat.
  static bool inline = false;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  late PreparedPhoto _photo = widget.photo;
  final _strokes = <PenStroke>[];
  _Tool _tool = _Tool.none;
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  Color _color = kPenColors.first;
  bool _busy = false;

  /// Coin ou bord saisi pendant le recadrage (null : on déplace le cadre).
  Alignment? _handle;

  Future<PreparedPhoto> _run(PhotoEdit edit) {
    final e = edit.withQuality(_photo.quality);
    return PhotoEditorScreen.inline ? Future.value(applyPhotoEdit(e)) : compute(applyPhotoEdit, e);
  }

  void _failed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t.retoucheNPasPuEtre)));
  }

  Future<void> _apply(PhotoEdit Function(Uint8List bytes) op) async {
    setState(() => _busy = true);
    try {
      await _burn();
      final next = await _run(op(_photo.bytes));
      if (mounted) setState(() => _photo = next);
    } on Object catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Les traits sont gravés dans la photo avant un pivotement ou un recadrage.
  Future<void> _burn() async {
    if (_strokes.isEmpty) return;
    final bytes = _photo.bytes;
    final data = [
      for (final s in _strokes)
        (s.color.toARGB32(), s.width, [for (final p in s.points) (p.dx, p.dy)]),
    ];
    final next = await _run(PhotoEdit.draw(bytes, data));
    if (!mounted) return;
    setState(() {
      _photo = next;
      _strokes.clear();
    });
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      await _burn();
      if (mounted) Navigator.pop(context, _photo);
    } on Object catch (_) {
      // Jamais d'attente sans fin : on reste sur l'écran, la retouche peut être refaite.
      if (mounted) setState(() => _busy = false);
      _failed();
    }
  }

  void _panStart(Offset local, Size size) {
    final p = Offset(local.dx / size.width, local.dy / size.height);
    if (_tool == _Tool.draw) {
      setState(() => _strokes.add(PenStroke(_color, 0.012)..points.add(p)));
    } else if (_tool == _Tool.crop) {
      const grab = 0.08;
      Alignment? h;
      for (final (a, corner) in [
        (Alignment.topLeft, _crop.topLeft),
        (Alignment.topRight, _crop.topRight),
        (Alignment.bottomLeft, _crop.bottomLeft),
        (Alignment.bottomRight, _crop.bottomRight),
      ]) {
        if ((corner - p).distance < grab) h = a;
      }
      _handle = h;
    }
  }

  void _panUpdate(Offset local, Offset delta, Size size) {
    final p = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    if (_tool == _Tool.draw && _strokes.isNotEmpty) {
      setState(() => _strokes.last.points.add(p));
    } else if (_tool == _Tool.crop) {
      const min = 0.12;
      final c = _crop;
      setState(() {
        _crop = switch (_handle) {
          Alignment.topLeft => Rect.fromLTRB(
            p.dx.clamp(0.0, c.right - min),
            p.dy.clamp(0.0, c.bottom - min),
            c.right,
            c.bottom,
          ),
          Alignment.topRight => Rect.fromLTRB(
            c.left,
            p.dy.clamp(0.0, c.bottom - min),
            p.dx.clamp(c.left + min, 1.0),
            c.bottom,
          ),
          Alignment.bottomLeft => Rect.fromLTRB(
            p.dx.clamp(0.0, c.right - min),
            c.top,
            c.right,
            p.dy.clamp(c.top + min, 1.0),
          ),
          Alignment.bottomRight => Rect.fromLTRB(
            c.left,
            c.top,
            p.dx.clamp(c.left + min, 1.0),
            p.dy.clamp(c.top + min, 1.0),
          ),
          _ => () {
            final dx = (delta.dx / size.width).clamp(-c.left, 1 - c.right);
            final dy = (delta.dy / size.height).clamp(-c.top, 1 - c.bottom);
            return c.shift(Offset(dx, dy));
          }(),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('photo.editor'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          key: const Key('editor.cancel'),
          tooltip: L.t.annulerRetouche,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Text(L.t.retoucher),
        actions: [
          if (_strokes.isNotEmpty)
            IconButton(
              key: const Key('editor.undo'),
              tooltip: L.t.annulerDernierTrait,
              onPressed: () => setState(_strokes.removeLast),
              icon: const Icon(Icons.undo),
            ),
          TextButton(
            key: const Key('editor.done'),
            onPressed: _busy || _tool == _Tool.crop ? null : _done,
            child: Text(L.t.termine, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.m),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final ratio = _photo.width / _photo.height;
                    var w = box.maxWidth;
                    var h = w / ratio;
                    if (h > box.maxHeight) {
                      h = box.maxHeight;
                      w = h * ratio;
                    }
                    final size = Size(w, h);
                    return Center(
                      child: SizedBox.fromSize(
                        size: size,
                        child: GestureDetector(
                          key: const Key('editor.canvas'),
                          onPanStart: (d) => _panStart(d.localPosition, size),
                          onPanUpdate: (d) => _panUpdate(d.localPosition, d.delta, size),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                _photo.bytes,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                semanticLabel: L.t.photoRetoucher,
                              ),
                              CustomPaint(painter: _StrokesPainter(_strokes)),
                              if (_tool == _Tool.crop) CustomPaint(painter: _CropPainter(_crop)),
                              if (_busy)
                                const ColoredBox(
                                  color: Colors.black38,
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_tool == _Tool.draw)
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (i, c) in kPenColors.indexed)
                      GestureDetector(
                        key: Key('editor.color.$i'),
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == _color ? PrivioColors.lilac : Colors.white54,
                              width: c == _color ? 3 : 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.m,
                0,
                PrivioSpacing.m,
                PrivioSpacing.m,
              ),
              child: _tool == _Tool.crop
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('editor.crop.cancel'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: () => setState(() {
                              _tool = _Tool.none;
                              _crop = const Rect.fromLTRB(0, 0, 1, 1);
                            }),
                            child: Text(L.t.annuler),
                          ),
                        ),
                        const SizedBox(width: PrivioSpacing.m),
                        Expanded(
                          child: FilledButton(
                            key: const Key('editor.crop.apply'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final c = _crop;
                                    setState(() => _tool = _Tool.none);
                                    await _apply(
                                      (b) => PhotoEdit.crop(b, [c.left, c.top, c.right, c.bottom]),
                                    );
                                    if (mounted) {
                                      setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1));
                                    }
                                  },
                            child: Text(L.t.recadrer),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ToolButton(
                          key: const Key('editor.rotate'),
                          icon: Icons.rotate_left_rounded,
                          label: L.t.pivoter,
                          onTap: _busy ? null : () => _apply((b) => PhotoEdit.rotate(b)),
                        ),
                        _ToolButton(
                          key: const Key('editor.crop'),
                          icon: Icons.crop_rounded,
                          label: L.t.recadrer,
                          onTap: _busy ? null : () => setState(() => _tool = _Tool.crop),
                        ),
                        _ToolButton(
                          key: const Key('editor.draw'),
                          icon: Icons.brush_rounded,
                          label: L.t.dessiner,
                          selected: _tool == _Tool.draw,
                          onTap: _busy
                              ? null
                              : () => setState(
                                  () => _tool = _tool == _Tool.draw ? _Tool.none : _Tool.draw,
                                ),
                        ),
                      ],
                    ),
            ),
            if (_tool == _Tool.draw)
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.s),
                child: Text(
                  L.t.dessinezSurPhotoAvecDoigt,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PrivioColors.lilac : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PrivioRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);

  final List<PenStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final pts = [for (final p in s.points) Offset(p.dx * size.width, p.dy * size.height)];
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawRect(
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final handle = Paint()..color = Colors.white;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 9, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}
