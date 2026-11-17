import '../../../l10n/l10n.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/models/messaging.dart';
import '../../../domain/models/stickers.dart';
import '../../../state/sticker_providers.dart';
import '../../core/widgets/success_snack.dart';
import 'sticker_creator.dart';
import 'gif_picker.dart';

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

List<StickerInfo> get kPrivioStickers => <StickerInfo>[
  StickerInfo('merci', L.t.merci),
  StickerInfo('bravo', L.t.bravo),
  StickerInfo('courage', L.t.courage),
  StickerInfo('desole', L.t.desole),
  StickerInfo('bonne_arrivee', L.t.bonneArrivee),
  StickerInfo('on_dit_quoi', L.t.onDitQuoi),
  StickerInfo('ca_va_aller', L.t.caVaAller),
  StickerInfo('bonne_fete', L.t.bonneFete),
  StickerInfo('je_t_appelle', L.t.jeTAppelle),
  StickerInfo('a_tout', L.t.tout),
  StickerInfo('bonjour', L.t.bonjour),
  StickerInfo('bonne_nuit', L.t.bonneNuit),
  StickerInfo('mdr', L.t.mdr),
  StickerInfo('je_t_aime', L.t.jeTAime),
  StickerInfo('d_accord', L.t.accord),
  StickerInfo('non', L.t.non),
  StickerInfo('oups', L.t.oups),
  StickerInfo('waouh', L.t.waouh),
  StickerInfo('j_arrive', L.t.jArrive),
  StickerInfo('attends', L.t.attends),
  StickerInfo('felicitations', L.t.felicitations),
  StickerInfo('bon_appetit', L.t.bonAppetit),
  StickerInfo('fatigue', L.t.fatigue),
  StickerInfo('fache', L.t.fache),
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
            L.t.autocollantIndisponibleMettezPrivioJour,
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
      semanticLabel: L.t.autocollantLabel(s.label),
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
        L.t.vosEmojisRecentsAfficherontIci,
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
    searchViewConfig: SearchViewConfig(backgroundColor: p.sheet, hintText: L.t.rechercherEmoji),
  );
}

/// Panneau sous la zone de saisie : émojis (insérés dans le texte) et autocollants
/// (envoyés aussitôt).
class ExpressionPanel extends StatelessWidget {
  const ExpressionPanel({
    super.key,
    required this.controller,
    required this.onSticker,
    this.onCustomSticker,
    this.onGif,
    this.height = 300,
  });

  /// Lot 7.4 : mes autocollants (créer, envoyer, retirer) ; absent si null.
  final ValueChanged<StickerItem>? onCustomSticker;

  /// Vrai pendant les tests automatiques (pas de canal natif).
  static bool inTests = false;

  final TextEditingController controller;
  final ValueChanged<StickerInfo> onSticker;

  /// Lot 7.3b : onglet GIF (absent si null).
  final ValueChanged<GifResult>? onGif;
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
          length: onGif == null ? 2 : 3,
          child: Column(
            children: [
              TabBar(
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: [
                  Tab(key: const Key('expression.tab.emoji'), text: L.t.emojis, height: 40),
                  Tab(
                    key: const Key('expression.tab.stickers'),
                    text: L.t.autocollants,
                    height: 40,
                  ),
                  if (onGif != null)
                    const Tab(key: Key('expression.tab.gifs'), text: 'GIF', height: 40),
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
                    StickersTab(onSticker: onSticker, onCustomSticker: onCustomSticker),
                    if (onGif case final onGif?) GifPicker(onGif: onGif),
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

/// Onglet des autocollants : lot 7.4, mes autocollants (créer, envoyer, retirer par un
/// appui long), puis ceux de Privio.
class StickersTab extends ConsumerWidget {
  const StickersTab({super.key, required this.onSticker, this.onCustomSticker});

  final ValueChanged<StickerInfo> onSticker;
  final ValueChanged<StickerItem>? onCustomSticker;

  Future<void> _remove(BuildContext context, WidgetRef ref, StickerItem s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.retirerAutocollant),
        content: Text(L.t.retirerAutocollantConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('sticker.remove.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.retirer),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(myStickersProvider.notifier).remove(s.id);
      messenger.showSnackBar(successSnack(L.t.autocollantRetire));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final custom = onCustomSticker;
    final mine = custom == null
        ? const <StickerItem>[]
        : (ref.watch(myStickersProvider).value ?? const <StickerItem>[]);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.s, PrivioSpacing.m, 0),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: p.accentText)),
    );
    return CustomScrollView(
      key: const Key('expression.stickers'),
      slivers: [
        if (custom != null) ...[
          SliverToBoxAdapter(child: title(L.t.mesAutocollants)),
          // Bande horizontale : « + » puis mes autocollants (60 au plus).
          SliverToBoxAdapter(
            child: SizedBox(
              height: 84,
              child: ListView.separated(
                key: const Key('sticker.mine_strip'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: PrivioSpacing.s,
                  vertical: PrivioSpacing.xs,
                ),
                itemCount: mine.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: PrivioSpacing.s),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Semantics(
                      button: true,
                      label: L.t.creerAutocollant,
                      child: InkWell(
                        key: const Key('sticker.create'),
                        borderRadius: BorderRadius.circular(PrivioRadius.medium),
                        onTap: () => createSticker(context, ref),
                        child: Container(
                          width: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(PrivioRadius.medium),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Icon(Icons.add_photo_alternate_outlined, color: p.accentText),
                        ),
                      ),
                    );
                  }
                  final s = mine[i - 1];
                  return InkWell(
                    key: Key('sticker.mine.${s.id}'),
                    borderRadius: BorderRadius.circular(PrivioRadius.medium),
                    onTap: () => custom(s),
                    onLongPress: () => _remove(context, ref, s),
                    child: CustomStickerImage(path: s.path, size: 72),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(child: title(L.t.autocollantsPrivio)),
        ],
        SliverPadding(
          padding: const EdgeInsets.all(PrivioSpacing.s),
          sliver: SliverGrid.count(
            crossAxisCount: 4,
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
        ),
      ],
    );
  }
}
