import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';

/// Lot 7.3a : émojis et autocollants Privio.

/// Un autocollant intégré à l'application (aucune image n'est envoyée : le message porte
/// seulement « série/nom »).
class StickerInfo {
  const StickerInfo(this.name, this.label);

  final String name;

  /// Texte lu par TalkBack (et montré dans les aperçus).
  final String label;

  String get id => 'privio/$name';
  String get asset => 'assets/stickers/privio/$name.webp';
}

const kPrivioStickers = <StickerInfo>[
  StickerInfo('merci', 'Merci\u202F!'),
  StickerInfo('bravo', 'Bravo\u202F!'),
  StickerInfo('courage', 'Courage\u202F!'),
  StickerInfo('desole', 'Désolé'),
  StickerInfo('bonne_arrivee', 'Bonne arrivée'),
  StickerInfo('on_dit_quoi', 'On dit quoi\u202F?'),
  StickerInfo('ca_va_aller', 'Ça va aller'),
  StickerInfo('bonne_fete', 'Bonne fête\u202F!'),
  StickerInfo('je_t_appelle', 'Je t’appelle'),
  StickerInfo('a_tout', 'À tout’\u202F!'),
  StickerInfo('bonjour', 'Bonjour\u202F!'),
  StickerInfo('bonne_nuit', 'Bonne nuit'),
  StickerInfo('mdr', 'Mdr'),
  StickerInfo('je_t_aime', 'Je t’aime'),
  StickerInfo('d_accord', 'D’accord'),
  StickerInfo('non', 'Non\u202F!'),
  StickerInfo('oups', 'Oups'),
  StickerInfo('waouh', 'Waouh\u202F!'),
  StickerInfo('j_arrive', 'J’arrive\u202F!'),
  StickerInfo('attends', 'Attends…'),
  StickerInfo('felicitations', 'Félicitations\u202F!'),
  StickerInfo('bon_appetit', 'Bon appétit\u202F!'),
  StickerInfo('fatigue', 'Fatigué'),
  StickerInfo('fache', 'Fâché\u202F!'),
];

/// Autocollant connu de cette version de l'application (null : inconnu, p. ex. une série
/// ajoutée dans une version plus récente).
StickerInfo? stickerOf(String? id) => kPrivioStickers.where((s) => s.id == id).firstOrNull;

/// Image d'un autocollant ; inconnu : un remplaçant qui invite à mettre Privio à jour.
class StickerImage extends StatelessWidget {
  const StickerImage({super.key, required this.id, this.size = 140});

  final String? id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = stickerOf(id);
    if (s == null) {
      return SizedBox(
        width: size,
        height: size * 0.6,
        child: Center(
          child: Text(
            'Autocollant indisponible\nMettez Privio à jour',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Image.asset(
      s.asset,
      key: Key('sticker.image.${s.name}'),
      width: size,
      height: size,
      semanticLabel: 'Autocollant « ${s.label} »',
      filterQuality: FilterQuality.medium,
    );
  }
}

// Propriétés Unicode : reconnues par Dart à l'exécution (l'analyseur ne les connaît pas).
// ignore: valid_regexps
final _pictographic = RegExp(r'\p{Extended_Pictographic}|\p{Regional_Indicator}', unicode: true);
final _emojiPart = RegExp(
  // ignore: valid_regexps
  r'^(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier}|\p{Emoji_Component}|\u{FE0F}|\u{200D}|\u{20E3})+$',
  unicode: true,
);

/// Lot 7.3a : un message fait seulement de 1 à 3 émojis s'affiche en grand.
bool isJumboEmoji(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return false;
  final graphemes = t.characters.where((g) => g.trim().isNotEmpty).toList();
  if (graphemes.isEmpty || graphemes.length > 3) return false;
  return graphemes.every((g) => _emojiPart.hasMatch(g) && _pictographic.hasMatch(g));
}

/// Réglages du sélecteur d'émojis aux couleurs de Privio (en français, sans connexion).
Config privioEmojiConfig(BuildContext context, {required double height, bool bottomBar = true}) {
  final theme = Theme.of(context);
  final p = PrivioPalette.of(context);
  return Config(
    height: height,
    locale: const Locale('fr'),
    // Le téléphone retire les émojis qu'il ne sait pas afficher (pas dans les tests).
    checkPlatformCompatibility: !ExpressionPanel.inTests,
    emojiViewConfig: EmojiViewConfig(
      columns: 8,
      emojiSizeMax: 28 * (defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1.0),
      backgroundColor: p.sheet,
      noRecents: Text(
        'Vos émojis récents s’afficheront ici',
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ),
    categoryViewConfig: CategoryViewConfig(
      backgroundColor: p.sheet,
      indicatorColor: theme.colorScheme.primary,
      iconColorSelected: theme.colorScheme.primary,
      iconColor: theme.colorScheme.onSurfaceVariant,
      backspaceColor: theme.colorScheme.primary,
    ),
    bottomActionBarConfig: BottomActionBarConfig(
      enabled: bottomBar,
      backgroundColor: p.sheet,
      buttonColor: p.sheet,
      buttonIconColor: theme.colorScheme.onSurfaceVariant,
    ),
    searchViewConfig: SearchViewConfig(backgroundColor: p.sheet, hintText: 'Rechercher un émoji'),
  );
}

/// Panneau sous la zone de saisie : émojis (insérés dans le texte) et autocollants
/// (envoyés aussitôt).
class ExpressionPanel extends StatelessWidget {
  const ExpressionPanel({
    super.key,
    required this.controller,
    required this.onSticker,
    this.height = 300,
  });

  /// Vrai pendant les tests automatiques (pas de canal natif).
  static bool inTests = false;

  final TextEditingController controller;
  final ValueChanged<StickerInfo> onSticker;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Material(
      key: const Key('expression.panel'),
      color: p.sheet,
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(key: Key('expression.tab.emoji'), text: 'Émojis', height: 40),
                  Tab(key: Key('expression.tab.stickers'), text: 'Autocollants', height: 40),
                ],
              ),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    LayoutBuilder(
                      builder: (context, box) => EmojiPicker(
                        key: const Key('expression.emojis'),
                        textEditingController: controller,
                        config: privioEmojiConfig(context, height: box.maxHeight),
                      ),
                    ),
                    GridView.count(
                      key: const Key('expression.stickers'),
                      crossAxisCount: 4,
                      padding: const EdgeInsets.all(PrivioSpacing.s),
                      mainAxisSpacing: PrivioSpacing.s,
                      crossAxisSpacing: PrivioSpacing.s,
                      children: [
                        for (final s in kPrivioStickers)
                          InkWell(
                            key: Key('sticker.${s.name}'),
                            borderRadius: BorderRadius.circular(PrivioRadius.medium),
                            onTap: () => onSticker(s),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: StickerImage(id: s.id, size: 72),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Réagir avec n'importe quel émoji (lot 7.3a) : renvoie l'émoji choisi.
Future<String?> pickReactionEmoji(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: SizedBox(
      key: const Key('reaction.picker'),
      height: 340,
      child: EmojiPicker(
        onEmojiSelected: (_, emoji) => Navigator.pop(ctx, emoji.emoji),
        config: privioEmojiConfig(ctx, height: 340, bottomBar: false),
      ),
    ),
  ),
);
