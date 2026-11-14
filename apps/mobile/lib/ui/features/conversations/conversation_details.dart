import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../state/data_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/profile_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import 'photo_widgets.dart';
import 'voice_widgets.dart';

/// Lot 7.1a : éléments communs aux fiches contact et groupe.

/// Photo de profil (ou de groupe) en grand. Captures interdites (FLAG_SECURE), aucun
/// enregistrement possible ; [onEdit] pour les personnes autorisées à la changer.
class AvatarViewerScreen extends ConsumerWidget {
  const AvatarViewerScreen({super.key, required this.name, required this.path, this.onEdit});

  final String name;
  final String path;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(avatarBytesProvider(path));
    return Scaffold(
      key: const Key('avatar.viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(name),
        actions: [
          if (onEdit != null)
            IconButton(
              key: const Key('avatar.viewer.edit'),
              tooltip: 'Changer la photo',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
      body: Center(
        child: switch (bytes) {
          AsyncData(:final value) => InteractiveViewer(
            maxScale: 4,
            child: Image.memory(value, fit: BoxFit.contain, gaplessPlayback: true),
          ),
          AsyncError() => const Text(
            'Photo indisponible.',
            style: TextStyle(color: Colors.white70),
          ),
          _ => const CircularProgressIndicator(color: Colors.white),
        },
      ),
    );
  }
}

/// Avatar de fiche : toucher ouvre la photo en grand (s'il y en a une).
class FicheAvatar extends StatelessWidget {
  const FicheAvatar({
    super.key,
    required this.name,
    required this.path,
    required this.seed,
    this.icon,
    this.onEdit,
  });

  final String name;
  final String? path;
  final String seed;
  final IconData? icon;

  /// Personne autorisée à changer la photo : sans photo, toucher ouvre directement le choix.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final avatar = UserAvatar(name: name, avatarPath: p, seed: seed, radius: 48, icon: icon);
    final VoidCallback? onTap = p != null
        ? () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AvatarViewerScreen(
                name: name,
                path: p,
                onEdit: onEdit == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onEdit!();
                      },
              ),
            ),
          )
        : onEdit;
    return Center(
      child: Semantics(
        button: onTap != null,
        label: p != null ? 'Voir la photo en grand' : 'Photo',
        child: InkWell(
          key: const Key('fiche.avatar'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: avatar,
        ),
      ),
    );
  }
}

String _duration(int? ms) {
  final s = ((ms ?? 0) / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Section « Médias » d'une fiche : aperçu des derniers médias et « Tout voir ».
class ConversationMediaSection extends ConsumerWidget {
  const ConversationMediaSection({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final media = ref.watch(conversationMediaProvider(conversationId)).value ?? const [];
    void openAll() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationMediaScreen(conversationId: conversationId, title: title),
      ),
    );
    return Column(
      key: const Key('fiche.media'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('fiche.media.all'),
          leading: Icon(Icons.perm_media_outlined, color: p.accentText),
          title: const Text('Médias'),
          subtitle: Text(
            media.isEmpty
                ? 'Aucune photo ni vocal pour l’instant'
                : '${media.length} élément${media.length > 1 ? 's' : ''} · effacés avec les messages',
          ),
          trailing: media.isEmpty ? null : const Icon(Icons.chevron_right),
          onTap: media.isEmpty ? null : openAll,
        ),
        if (media.isNotEmpty)
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
              itemCount: media.length.clamp(0, 8),
              separatorBuilder: (_, _) => const SizedBox(width: PrivioSpacing.s),
              itemBuilder: (_, i) {
                final m = media[i];
                return SizedBox.square(
                  dimension: 76,
                  child: m.kind == 'photo'
                      ? MediaThumb(message: m, title: title)
                      : InkWell(
                          key: Key('fiche.media.voice.${m.id}'),
                          onTap: openAll,
                          borderRadius: BorderRadius.circular(PrivioRadius.small),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(PrivioRadius.small),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.mic_none, color: p.accentText),
                                Text(_duration(m.durationMs), style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Vignette carrée d'une photo : économie de données respectée (toucher pour télécharger),
/// toucher une photo téléchargée l'ouvre en grand.
class MediaThumb extends ConsumerWidget {
  const MediaThumb({super.key, required this.message, required this.title});

  final ChatMessage message;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photo = PhotoRef.message(message);
    final mine = message.senderId == ref.watch(currentUserIdProvider);
    final download =
        mine ||
        ref.watch(photoAutoAllowedProvider) ||
        ref.watch(photoRequestsProvider).contains(photo.key);
    final AsyncValue<Uint8List?> bytes = download
        ? ref.watch(photoBytesProvider(photo))
        : ref.watch(photoLocalProvider(photo));
    final radius = BorderRadius.circular(PrivioRadius.small);
    return ClipRRect(
      borderRadius: radius,
      child: switch (bytes) {
        AsyncData(value: final Uint8List value) => InkWell(
          key: Key('fiche.media.photo.${message.id}'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoViewerScreen(bytes: value, title: title, sentAt: message.sentAt),
            ),
          ),
          child: Image.memory(value, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        AsyncData() => InkWell(
          key: Key('fiche.media.download.${message.id}'),
          onTap: () => ref.read(photoRequestsProvider.notifier).request(photo.key),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.download_for_offline_outlined)),
          ),
        ),
        AsyncError() => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
        _ => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      },
    );
  }
}

/// Tous les médias encore présents : photos en grille, vocaux en liste.
class ConversationMediaScreen extends ConsumerWidget {
  const ConversationMediaScreen({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final me = ref.watch(currentUserIdProvider);
    final media = ref.watch(conversationMediaProvider(conversationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Médias')),
      body: switch (media) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.perm_media_outlined,
          title: 'Aucun média',
          message: 'Les photos et vocaux s’effacent avec leurs messages.',
        ),
        AsyncData(:final value) => CustomScrollView(
          key: const Key('media.screen'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: Text(
                  'Ils s’effacent avec leurs messages et ne peuvent pas être enregistrés.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            if (value.any((m) => m.kind == 'photo')) ...[
              _header(theme, 'Photos'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                sliver: SliverGrid.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: PrivioSpacing.xs,
                  crossAxisSpacing: PrivioSpacing.xs,
                  children: [
                    for (final m in value)
                      if (m.kind == 'photo') MediaThumb(message: m, title: title),
                  ],
                ),
              ),
            ],
            if (value.any((m) => m.kind == 'voice')) ...[
              _header(theme, 'Vocaux'),
              SliverList.list(
                children: [
                  for (final m in value)
                    if (m.kind == 'voice')
                      Padding(
                        key: Key('media.voice.${m.id}'),
                        padding: const EdgeInsets.fromLTRB(
                          PrivioSpacing.l,
                          0,
                          PrivioSpacing.l,
                          PrivioSpacing.s,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: m.senderId == me ? p.bubbleOut : p.bubbleIn,
                            borderRadius: BorderRadius.circular(PrivioRadius.medium),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(PrivioSpacing.s),
                            child: VoiceMessageContent(
                              message: m,
                              outgoing: m.senderId == me,
                              onError: (f) =>
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(f.message))),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: PrivioSpacing.xxl)),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(conversationMediaProvider(conversationId)),
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _header(ThemeData theme, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.s,
      ),
      child: Text(text, style: theme.textTheme.titleSmall),
    ),
  );
}

/// Sourdine d'une discussion (à deux ou de groupe) : 8 h, 1 semaine, toujours.
Future<void> chooseMute(BuildContext context, WidgetRef ref, ConversationSummary s) async {
  final now = DateTime.now();
  final choice = await showModalBottomSheet<Duration?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, d) in [
            ('8 heures', const Duration(hours: 8)),
            ('1 semaine', const Duration(days: 7)),
            ('Toujours', const Duration(days: 3650)),
          ])
            ListTile(
              key: Key('mute.${d.inHours}'),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, d),
            ),
          if (s.isMuted(now))
            ListTile(
              key: const Key('mute.off'),
              title: const Text('Réactiver les notifications'),
              onTap: () => Navigator.pop(ctx, Duration.zero),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    await ref
        .read(messagingApiProvider)
        .setMute(s.id, choice == Duration.zero ? null : now.add(choice));
    await ref.read(conversationsProvider.notifier).refresh();
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }
}

/// Libellé de l'état des notifications d'une discussion.
String muteLabel(ConversationSummary s, DateTime now) {
  final until = s.mutedUntil;
  if (until == null || !until.isAfter(now)) return 'Activées';
  if (until.difference(now).inDays > 365) return 'Désactivées';
  final l = until.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Désactivées jusqu’au ${two(l.day)}/${two(l.month)} à ${two(l.hour)}:${two(l.minute)}';
}
