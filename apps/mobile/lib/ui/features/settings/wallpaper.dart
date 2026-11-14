import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/photo_picker.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/providers.dart';
import '../../core/widgets/privacy_pattern.dart';

/// Lot 7.3a : fond d'écran des discussions : motifs Privio, couleurs, ou une photo de la
/// galerie qui reste sur le téléphone (jamais envoyée). Un fond par défaut, et un fond
/// propre à une discussion si on le souhaite.

/// Fond par défaut quand rien n'est choisi.
const kDefaultWallpaper = 'pattern:privacy';

/// Couleurs proposées : (nom, clair, sombre).
const kWallpaperColors = <(String, Color, Color)>[
  ('lavande', Color(0xFFEDE7FB), Color(0xFF231C42)),
  ('ciel', Color(0xFFE3EEFC), Color(0xFF14243F)),
  ('menthe', Color(0xFFE2F4EC), Color(0xFF13302A)),
  ('sable', Color(0xFFF6EEDF), Color(0xFF2E2719)),
  ('rose', Color(0xFFFBE6EE), Color(0xFF34192A)),
  ('gris', Color(0xFFECEDF2), Color(0xFF1C1F2B)),
  ('nuit', Color(0xFF1E2547), Color(0xFF0D1126)),
  ('prune', Color(0xFF3B2366), Color(0xFF1E1236)),
];

/// Motifs proposés : (nom, libellé).
const kWallpaperPatterns = <(String, String)>[
  ('privacy', 'Motif Privio'),
  ('dots', 'Points'),
  ('waves', 'Vagues'),
  ('plain', 'Uni'),
];

/// Choix enregistré (null : pas de choix) ; famille par discussion (null : par défaut).
final wallpaperChoiceProvider = FutureProvider.autoDispose.family<String?, String?>(
  (ref, conversationId) => ref.watch(localFlagsProvider).wallpaper(conversationId),
);

/// Fond affiché dans une discussion : le sien, sinon celui par défaut.
final effectiveWallpaperProvider = FutureProvider.autoDispose.family<String, String?>((
  ref,
  conversationId,
) async {
  if (conversationId != null) {
    final own = await ref.watch(wallpaperChoiceProvider(conversationId).future);
    if (own != null) return own;
  }
  final general = await ref.watch(wallpaperChoiceProvider(null).future);
  return general ?? kDefaultWallpaper;
});

Future<void> setWallpaper(WidgetRef ref, String? conversationId, String? value) async {
  final flags = ref.read(localFlagsProvider);
  final old = await flags.wallpaper(conversationId);
  await flags.setWallpaper(conversationId, value);
  // Ancienne photo : effacée du téléphone (sauf si elle est encore utilisée ailleurs).
  if (old != null && old.startsWith('photo:') && old != value) {
    try {
      await File(old.substring(6)).delete();
    } on Object catch (_) {}
  }
  ref
    ..invalidate(wallpaperChoiceProvider(conversationId))
    ..invalidate(effectiveWallpaperProvider);
}

/// Fond d'une discussion, derrière les messages.
class ChatWallpaper extends ConsumerWidget {
  const ChatWallpaper({super.key, required this.conversationId, required this.child});

  final String? conversationId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(effectiveWallpaperProvider(conversationId)).value ?? kDefaultWallpaper;
    return Stack(
      children: [
        Positioned.fill(child: WallpaperBackground(value: value)),
        child,
      ],
    );
  }
}

/// Le dessin d'un fond (aussi en miniature dans le choix).
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (kind, name) = switch (value.split(':')) {
      [final k, ...final rest] => (k, rest.join(':')),
      _ => ('pattern', 'privacy'),
    };
    return ExcludeSemantics(
      child: switch (kind) {
        'color' => ColoredBox(
          color: switch (kWallpaperColors.where((c) => c.$1 == name).firstOrNull) {
            final c? => dark ? c.$3 : c.$2,
            null => p.chatBackground,
          },
        ),
        'photo' => Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(name),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: p.chatBackground),
            ),
            // Assombri en mode sombre, légèrement voilé sinon : les bulles restent lisibles.
            ColoredBox(color: Colors.black.withValues(alpha: dark ? 0.4 : 0.06)),
          ],
        ),
        _ => switch (name) {
          'plain' => ColoredBox(color: p.chatBackground),
          'dots' || 'waves' => ColoredBox(
            color: p.chatBackground,
            child: RepaintBoundary(child: CustomPaint(painter: _SimplePattern(name, p.pattern))),
          ),
          _ => const PrivacyPattern(child: SizedBox.expand()),
        },
      },
    );
  }
}

class _SimplePattern extends CustomPainter {
  _SimplePattern(this.kind, this.color);

  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = kind == 'dots' ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.6;
    if (kind == 'dots') {
      const step = 22.0;
      for (var y = 0.0, row = 0; y < size.height + step; y += step, row++) {
        for (var x = row.isEven ? 0.0 : step / 2; x < size.width + step; x += step) {
          canvas.drawCircle(Offset(x, y), 2.2, paint);
        }
      }
    } else {
      const step = 34.0;
      for (var y = 0.0; y < size.height + step; y += step) {
        final path = Path()..moveTo(0, y);
        for (var x = 0.0; x <= size.width + 12; x += 12) {
          path.lineTo(x, y + 6 * math.sin(x / 24));
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SimplePattern old) => old.kind != kind || old.color != color;
}

/// Choix du fond : par défaut ([conversationId] null) ou pour une discussion.
class WallpaperScreen extends ConsumerWidget {
  const WallpaperScreen({super.key, this.conversationId, this.title});

  final String? conversationId;

  /// Nom de la discussion (titre de l'écran).
  final String? title;

  Future<void> _pickPhoto(BuildContext context, WidgetRef ref) async {
    try {
      final raw = await ref
          .read(appLockProvider.notifier)
          .runExternal(() => ref.read(photoPickerProvider).pick(PhotoSource.gallery));
      if (raw == null) return;
      // Réduite et sans métadonnées, comme une photo envoyée ; gardée sur ce téléphone.
      final photo = await ref.read(photoPreparerProvider)(raw);
      final path = await _savePhoto(photo.bytes);
      await setWallpaper(ref, conversationId, 'photo:$path');
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  Future<String> _savePhoto(Uint8List bytes) async {
    final dir = Directory('${(await wallpaperDirectory()).path}/wallpapers');
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/${conversationId ?? 'defaut'}-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final choice = ref.watch(wallpaperChoiceProvider(conversationId)).value;
    final shown = ref.watch(effectiveWallpaperProvider(conversationId)).value ?? kDefaultWallpaper;
    final selected = choice ?? (conversationId == null ? kDefaultWallpaper : null);
    Widget tile(String key, String label, {required String? value, Widget? preview}) {
      final isSelected = value == selected;
      return InkWell(
        key: Key('wallpaper.$key'),
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        onTap: () => setWallpaper(ref, conversationId, value),
        child: Column(
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PrivioRadius.medium),
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : p.divider,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    preview ?? WallpaperBackground(value: value ?? kDefaultWallpaper),
                    if (isSelected)
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: theme.colorScheme.primary,
                            semanticLabel: 'choisi',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall, maxLines: 1),
          ],
        ),
      );
    }

    final photo = choice != null && choice.startsWith('photo:') ? choice : null;
    return Scaffold(
      appBar: AppBar(title: Text(title == null ? 'Fond d’écran' : 'Fond · $title')),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.l),
        children: [
          // Aperçu avec deux bulles.
          Container(
            key: const Key('wallpaper.preview'),
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(PrivioRadius.large)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                WallpaperBackground(value: shown),
                Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.m),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _PreviewBubble(text: 'Bonjour !', color: p.bubbleIn),
                      ),
                      const SizedBox(height: PrivioSpacing.s),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _PreviewBubble(text: 'Salut, ça va ?', color: p.bubbleOut),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(
            conversationId == null
                ? 'Par défaut pour toutes les discussions. Chaque discussion peut avoir le '
                      'sien (fiche de la discussion).'
                : 'Seulement pour cette discussion. La photo choisie reste sur ce téléphone.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: PrivioSpacing.l),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: PrivioSpacing.m,
            crossAxisSpacing: PrivioSpacing.m,
            childAspectRatio: 0.72,
            children: [
              if (conversationId != null)
                tile(
                  'default',
                  'Par défaut',
                  value: null,
                  preview: Consumer(
                    builder: (context, ref, _) => WallpaperBackground(
                      value: ref.watch(wallpaperChoiceProvider(null)).value ?? kDefaultWallpaper,
                    ),
                  ),
                ),
              for (final (name, label) in kWallpaperPatterns)
                tile(name, label, value: 'pattern:$name'),
              for (final (name, _, _) in kWallpaperColors)
                tile(name, name[0].toUpperCase() + name.substring(1), value: 'color:$name'),
              if (photo != null) tile('photo', 'Ma photo', value: photo),
            ],
          ),
          const SizedBox(height: PrivioSpacing.l),
          OutlinedButton.icon(
            key: const Key('wallpaper.pick_photo'),
            onPressed: () => _pickPhoto(context, ref),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(photo == null ? 'Choisir une photo' : 'Choisir une autre photo'),
          ),
          const SizedBox(height: PrivioSpacing.s),
          Text(
            'La photo n’est jamais envoyée : elle reste sur ce téléphone.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Dossier des photos de fond (remplaçable dans les tests).
Future<Directory> Function() wallpaperDirectory = getApplicationSupportDirectory;

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}
