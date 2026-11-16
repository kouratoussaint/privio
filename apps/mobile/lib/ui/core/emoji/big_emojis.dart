import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../motion/motion.dart';
import 'animated_emoji_assets.g.dart';

/// Lot 8.5b — message fait de 1, 2 ou 3 émojis seulement : affichés en grand et, pour les
/// 150 émojis les plus utilisés, animés (Noto Animated Emoji, Google, CC BY 4.0 — fichiers
/// intégrés à l'application, rien n'est téléchargé). L'animation joue 2 fois puis s'arrête ;
/// toucher l'émoji la rejoue. Les autres émojis restent fixes, en grand.
/// Crédit affiché dans les licences de l'application (Aide › Licences).
const kNotoAnimatedEmojiCredit =
    'Animations des émojis : Noto Animated Emoji, Google. '
    'Licence Creative Commons Attribution 4.0 International (CC BY 4.0), '
    'https://creativecommons.org/licenses/by/4.0/ — '
    'https://googlefonts.github.io/noto-emoji-animation/. '
    'Privio intègre 150 de ces animations ; aucune n’est téléchargée pendant l’utilisation.';

abstract final class BigEmojis {
  /// Taille d'un émoji selon leur nombre dans le message.
  static double sizeFor(int count) => switch (count) {
    1 => 96,
    2 => 72,
    _ => 56,
  };

  /// Clé de l'émoji dans [kAnimatedEmojiAssets] (sans le sélecteur U+FE0F).
  static String keyOf(String emoji) =>
      emoji.runes.where((r) => r != 0xFE0F).map((r) => r.toRadixString(16)).join('_');

  /// Fichier de l'animation, ou null si cet émoji n'est pas animé.
  static String? assetFor(String emoji) {
    final file = kAnimatedEmojiAssets[keyOf(emoji)];
    return file == null ? null : 'assets/emoji/$file.json';
  }

  /// Émojis du message (groupes de caractères visibles).
  static List<String> split(String text) =>
      text.trim().characters.where((g) => g.trim().isNotEmpty).toList();
}

class BigEmojisText extends StatelessWidget {
  const BigEmojisText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final emojis = BigEmojis.split(text);
    final size = BigEmojis.sizeFor(emojis.length);
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Wrap(
          key: const Key('bubble.big_emojis'),
          spacing: 2,
          children: [for (final e in emojis) _BigEmoji(emoji: e, size: size)],
        ),
      ),
    );
  }
}

class _BigEmoji extends StatefulWidget {
  const _BigEmoji({required this.emoji, required this.size});

  final String emoji;
  final double size;

  @override
  State<_BigEmoji> createState() => _BigEmojiState();
}

class _BigEmojiState extends State<_BigEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  int _plays = 0;

  /// Nombre de lectures avant l'arrêt.
  static const plays = 2;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      _plays++;
      if (_plays < plays && mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _replay() {
    if (_c.duration == null || !Motion.loops(context)) return;
    _plays = 0;
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final asset = BigEmojis.assetFor(widget.emoji);
    final still = Text(widget.emoji, style: TextStyle(fontSize: widget.size * 0.82, height: 1.15));
    if (asset == null) {
      return SizedBox(
        key: const Key('emoji.still'),
        height: widget.size,
        child: Center(child: still),
      );
    }
    return GestureDetector(
      key: const Key('emoji.animated'),
      onTap: _replay,
      child: SizedBox.square(
        dimension: widget.size,
        child: Lottie.asset(
          asset,
          controller: _c,
          width: widget.size,
          height: widget.size,
          // Image fixe tant que l'animation n'est pas chargée, ou si elle ne peut pas l'être.
          frameBuilder: (context, child, composition) => composition == null ? still : child,
          errorBuilder: (_, _, _) => still,
          onLoaded: (composition) {
            _c.duration = composition.duration;
            // Animations réduites (réglage du téléphone, tests) : première image seulement.
            if (Motion.loops(context) && !kIsWeb) _c.forward(from: 0);
          },
        ),
      ),
    );
  }
}

/// Lot 8.5c : émoji animé en boucle (illustrations du guide). Image fixe si l'émoji n'est
/// pas animé ou si les animations sont réduites.
class LoopingEmoji extends StatelessWidget {
  const LoopingEmoji(this.emoji, {super.key, this.size = 72});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = BigEmojis.assetFor(emoji);
    final still = Text(emoji, style: TextStyle(fontSize: size * 0.82, height: 1.15));
    if (asset == null) {
      return SizedBox(
        height: size,
        child: Center(child: still),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Lottie.asset(
        asset,
        width: size,
        height: size,
        animate: Motion.loops(context),
        frameBuilder: (context, child, composition) => composition == null ? still : child,
        errorBuilder: (_, _, _) => still,
      ),
    );
  }
}
