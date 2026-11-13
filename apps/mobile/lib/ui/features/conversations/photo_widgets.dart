import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/media/photo_processing.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/photo_picker.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/data_providers.dart';
import '../../../state/messaging_providers.dart';

/// Largeur d'une photo dans une bulle ; la hauteur suit les proportions (bornées).
const double kPhotoBubbleWidth = 236;

double photoBubbleHeight(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) return kPhotoBubbleWidth;
  return (kPhotoBubbleWidth * height / width).clamp(140.0, 320.0);
}

/// « Il vous reste 3 photos aujourd'hui. »
String photoQuotaText(PhotoQuota q) => switch (q.remaining) {
  0 => 'Vous avez envoyé vos ${q.limit} photos du jour. Prochaines photos demain, dès minuit.',
  1 => 'Il vous reste 1 photo aujourd’hui (${q.limit} par jour).',
  final n => 'Il vous reste $n photos aujourd’hui (${q.limit} par jour).',
};

/// Photo dans une bulle (message envoyé, reçu ou en attente). Toucher : plein écran.
class PhotoMessageContent extends ConsumerWidget {
  const PhotoMessageContent({
    super.key,
    required this.photo,
    required this.width,
    required this.height,
    required this.outgoing,
    this.caption,
    this.onOpen,
  });

  final PhotoRef photo;
  final int? width;
  final int? height;
  final bool outgoing;
  final String? caption;
  final void Function(Uint8List bytes)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final fg = outgoing ? p.onBubbleOut : p.onBubbleIn;
    final meta = outgoing ? p.bubbleOutMeta : p.bubbleInMeta;
    final h = photoBubbleHeight(width, height);
    // Économie de données : sans téléchargement automatique, une photo reçue n'est
    // téléchargée que si la personne le demande (DATA-003).
    final download =
        outgoing ||
        ref.watch(photoAutoAllowedProvider) ||
        ref.watch(photoRequestsProvider).contains(photo.key);
    final AsyncValue<Uint8List?> bytes = download
        ? ref.watch(photoBytesProvider(photo))
        : ref.watch(photoLocalProvider(photo));

    final Widget frame = switch (bytes) {
      AsyncData(value: null) => InkWell(
        key: Key('photo.download.${photo.key}'),
        onTap: () => ref.read(photoRequestsProvider.notifier).request(photo.key),
        child: _Placeholder(
          height: h,
          color: meta,
          icon: Icons.download_for_offline_outlined,
          label: 'Photo · toucher pour télécharger',
        ),
      ),
      AsyncData(value: final Uint8List value) => GestureDetector(
        key: Key('photo.open.${photo.key}'),
        onTap: onOpen == null ? null : () => onOpen!(value),
        child: Image.memory(
          value,
          width: kPhotoBubbleWidth,
          height: h,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (kPhotoBubbleWidth * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => _Placeholder(height: h, color: meta, icon: Icons.broken_image),
        ),
      ),
      AsyncError(:final error) => InkWell(
        key: Key('photo.retry.${photo.key}'),
        onTap: () => ref.invalidate(photoBytesProvider(photo)),
        child: _Placeholder(
          height: h,
          color: meta,
          icon: Icons.image_not_supported_outlined,
          label: toAppFailure(error).code == FailureCode.network
              ? 'Hors connexion · toucher pour réessayer'
              : 'Photo indisponible',
        ),
      ),
      _ => _Placeholder(height: h, color: meta, loading: true),
    };

    final notDownloaded = bytes is AsyncData<Uint8List?> && bytes.value == null;
    final what = notDownloaded ? 'Photo non téléchargée' : 'Photo';
    return Semantics(
      label: caption == null || caption!.isEmpty ? what : '$what\u202F: $caption',
      button: onOpen != null || notDownloaded,
      onTapHint: notDownloaded ? 'télécharger' : 'agrandir',
      onTap: notDownloaded
          ? () => ref.read(photoRequestsProvider.notifier).request(photo.key)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ExcludeSemantics(child: frame),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: kPhotoBubbleWidth,
              child: Text(caption!, style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.height,
    required this.color,
    this.icon,
    this.label,
    this.loading = false,
  });

  final double height;
  final Color color;
  final IconData? icon;
  final String? label;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: kPhotoBubbleWidth,
    height: height,
    color: color.withValues(alpha: 0.18),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(PrivioSpacing.m),
    child: loading
        ? SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 32),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(
                  label!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ],
          ),
  );
}

/// Écran 15 — photo en plein écran (zoom). Volontairement AUCUN bouton enregistrer,
/// partager ou transférer (PHOTO-007, SEC-007) ; captures bloquées (FLAG_SECURE).
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({
    super.key,
    required this.bytes,
    required this.title,
    this.caption,
    this.sentAt,
  });

  final Uint8List bytes;
  final String title;
  final String? caption;
  final DateTime? sentAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('photo.viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          key: const Key('photo.viewer.close'),
          tooltip: 'Fermer',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
            if (sentAt != null)
              Text(
                DateFormat('d MMM, HH:mm', 'fr').format(sentAt!.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    semanticLabel: caption == null || caption!.isEmpty ? 'Photo' : caption,
                  ),
                ),
              ),
            ),
            if (caption != null && caption!.isNotEmpty)
              Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: Text(
                  caption!,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Feuille de choix : appareil photo ou galerie, avec le compteur du jour (PHOTO-005).
Future<PhotoSource?> showPhotoSourceSheet(BuildContext context, {PhotoQuota? quota}) {
  final none = quota != null && quota.remaining == 0;
  return showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final p = PrivioPalette.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xl,
                0,
                PrivioSpacing.xl,
                PrivioSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Envoyer une photo', style: theme.textTheme.titleMedium),
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(
                    quota == null
                        ? 'Photos limitées chaque jour. Elles s’effacent comme les messages.'
                        : photoQuotaText(quota),
                    key: const Key('photo.quota'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: none ? theme.colorScheme.error : null,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const Key('photo.camera'),
              enabled: !none,
              leading: Icon(Icons.photo_camera_outlined, color: p.accentText),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, PhotoSource.camera),
            ),
            ListTile(
              key: const Key('photo.gallery'),
              enabled: !none,
              leading: Icon(Icons.photo_library_outlined, color: p.accentText),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, PhotoSource.gallery),
            ),
            const SizedBox(height: PrivioSpacing.s),
          ],
        ),
      );
    },
  );
}

/// Écran 13 — aperçu avant envoi, légende facultative, compteur. Renvoie la légende
/// (éventuellement vide) si la personne envoie, null si elle renonce.
/// Sélection multiple quand le quota du jour est inconnu (hors connexion) :
/// le serveur tranchera à l'envoi.
const kMaxPhotosPerPick = 5;

/// Une photo prête à partir, avec sa légende.
class PhotoDraft {
  const PhotoDraft(this.photo, this.caption);

  final PreparedPhoto photo;
  final String caption;
}

/// Aperçu avant envoi (lot 4.5 : une ou plusieurs photos). On fait défiler les photos,
/// on peut en retirer une, chaque photo a sa légende ; chacune partira comme un message.
/// Renvoie la liste à envoyer, ou null si la personne annule.
class PhotoComposeScreen extends StatefulWidget {
  const PhotoComposeScreen({super.key, required this.photos, this.quota, this.maxCaption = 1000});

  final List<PreparedPhoto> photos;
  final PhotoQuota? quota;
  final int maxCaption;

  @override
  State<PhotoComposeScreen> createState() => _PhotoComposeScreenState();
}

class _PhotoComposeScreenState extends State<PhotoComposeScreen> {
  late final List<PreparedPhoto> _photos = [...widget.photos];
  late final List<String> _captions = List.filled(widget.photos.length, '', growable: true);
  final _caption = TextEditingController();
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _caption.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _show(int i) {
    _captions[_index] = _caption.text;
    setState(() => _index = i);
    _caption.text = _captions[i];
  }

  void _remove(int i) {
    _captions[_index] = _caption.text;
    setState(() {
      _photos.removeAt(i);
      _captions.removeAt(i);
      if (_index >= _photos.length) _index = _photos.length - 1;
    });
    _caption.text = _captions[_index];
    if (_pages.hasClients) _pages.jumpToPage(_index);
  }

  void _send() {
    _captions[_index] = _caption.text;
    Navigator.pop(context, [
      for (final (i, p) in _photos.indexed) PhotoDraft(p, _captions[i].trim()),
    ]);
  }

  String? _quotaText() {
    final q = widget.quota;
    if (q == null) return null;
    final after = q.remaining - _photos.length;
    if (after <= 0) {
      return _photos.length == 1
          ? 'C’est votre dernière photo du jour (${q.limit} par jour).'
          : 'Ce sont vos dernières photos du jour (${q.limit} par jour).';
    }
    return 'Après l’envoi : $after photo${after > 1 ? 's' : ''} aujourd’hui (${q.limit} par jour).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final many = _photos.length > 1;
    final quota = _quotaText();
    return Scaffold(
      key: const Key('photo.compose'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          key: const Key('photo.compose.cancel'),
          tooltip: 'Annuler',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Text(many ? '${_index + 1} sur ${_photos.length}' : 'Envoyer une photo'),
        actions: [
          if (many)
            IconButton(
              key: const Key('photo.compose.remove'),
              tooltip: 'Retirer cette photo',
              onPressed: () => _remove(_index),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                key: const Key('photo.compose.pages'),
                controller: _pages,
                itemCount: _photos.length,
                onPageChanged: _show,
                itemBuilder: (_, i) => Center(
                  child: Image.memory(
                    _photos[i].bytes,
                    fit: BoxFit.contain,
                    semanticLabel: 'Photo ${i + 1} à envoyer',
                  ),
                ),
              ),
            ),
            if (many)
              SizedBox(
                height: 64,
                child: ListView.separated(
                  key: const Key('photo.compose.strip'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.m,
                    vertical: PrivioSpacing.xs,
                  ),
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: PrivioSpacing.s),
                  itemBuilder: (_, i) => GestureDetector(
                    key: Key('photo.compose.thumb.$i'),
                    onTap: () => _pages.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(PrivioRadius.small),
                        border: Border.all(
                          color: i == _index ? PrivioColors.lilac : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(_photos[i].bytes, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            if (quota != null)
              Padding(
                padding: const EdgeInsets.only(top: PrivioSpacing.s),
                child: Text(
                  quota,
                  key: const Key('photo.compose.quota'),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('photo.caption'),
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: widget.maxCaption,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: many ? 'Légende de cette photo' : 'Ajouter une légende',
                        hintStyle: const TextStyle(color: Colors.white60),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: PrivioSpacing.s),
                  Badge(
                    isLabelVisible: many,
                    label: Text('${_photos.length}'),
                    backgroundColor: PrivioColors.navy,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: IconButton.filled(
                        key: const Key('photo.send'),
                        tooltip: many ? 'Envoyer les ${_photos.length} photos' : 'Envoyer la photo',
                        style: IconButton.styleFrom(
                          backgroundColor: dark ? PrivioColors.lilac : PrivioColors.purple,
                          foregroundColor: dark ? PrivioColors.navy : Colors.white,
                        ),
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ),
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
