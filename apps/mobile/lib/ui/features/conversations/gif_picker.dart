import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/providers.dart';
import 'expression_panel.dart';

/// Lot 7.3b : recherche de GIF (KLIPY). Les vignettes viennent directement de KLIPY
/// (décision C) ; le GIF envoyé est recopié par le serveur dans le stockage privé.
class GifPicker extends ConsumerStatefulWidget {
  const GifPicker({super.key, required this.onGif});

  final ValueChanged<GifResult> onGif;

  @override
  ConsumerState<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends ConsumerState<GifPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<GifResult> _items = const [];
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_search()));
  }

  Future<void> _search() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filter = await ref.read(localFlagsProvider).gifFilter();
      final (items, _) = await ref
          .read(messagingApiProvider)
          .searchGifs(_query.text.trim(), filter: filter);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      final f = e is AppFailure ? e : const AppFailure(FailureCode.unknown);
      setState(() {
        _loading = false;
        _error = f.code == FailureCode.network
            ? f.message
            : const AppFailure(FailureCode.gifUnavailable).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Column(
      key: const Key('expression.gifs'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PrivioSpacing.s, PrivioSpacing.s, PrivioSpacing.s, 0),
          child: TextField(
            key: const Key('gif.search'),
            controller: _query,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Rechercher un GIF',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: p.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PrivioRadius.large),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _body(theme)),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'GIF fournis par KLIPY',
            key: const Key('gif.attribution'),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PrivioSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, key: const Key('gif.error'), textAlign: TextAlign.center),
              TextButton(
                key: const Key('gif.retry'),
                onPressed: () => unawaited(_search()),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Aucun GIF trouvé.',
          key: const Key('gif.empty'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(PrivioSpacing.s),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final g = _items[i];
        return Semantics(
          button: true,
          label: g.title.isEmpty ? 'GIF' : 'GIF ${g.title}',
          child: InkWell(
            key: Key('gif.item.${g.slug}'),
            onTap: () => widget.onGif(g),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PrivioRadius.small),
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: ExpressionPanel.inTests
                    ? const SizedBox.expand()
                    : Image.network(
                        g.url,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const Icon(Icons.gif_box_outlined),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lot 7.3b : image d'un GIF reçu ou envoyé (stockage privé, téléchargée avec le jeton).
final gifBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, path) => ref.watch(messagingApiProvider).downloadGif(path),
);

class GifImage extends ConsumerWidget {
  const GifImage({super.key, required this.message, this.maxWidth = 240});

  final ChatMessage message;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = (message.width ?? 200).toDouble();
    final h = (message.height ?? 150).toDouble();
    final width = maxWidth;
    final height = (width * h / w).clamp(80.0, 320.0);
    final path = message.mediaPath;
    final bytes = path == null ? null : ref.watch(gifBytesProvider(path));
    return Semantics(
      label: 'GIF',
      image: true,
      child: ClipRRect(
        key: Key('gif.bubble.${message.id}'),
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: switch (bytes) {
              AsyncData(:final value) => Image.memory(
                value,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Center(child: Icon(Icons.gif_box_outlined)),
              ),
              AsyncError() => const Center(child: Icon(Icons.broken_image_outlined)),
              _ => const Center(child: Icon(Icons.gif_box_outlined)),
            },
          ),
        ),
      ),
    );
  }
}

/// GIF en attente d'envoi (le serveur le recopie depuis KLIPY).
class PendingGifContent extends StatelessWidget {
  const PendingGifContent({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(PrivioRadius.medium),
    child: SizedBox(
      width: 200,
      height: 150,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.gif_box_outlined, size: 40)),
      ),
    ),
  );
}
