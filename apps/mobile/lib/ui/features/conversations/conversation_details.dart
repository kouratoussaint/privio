import '../../../l10n/l10n.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/data_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../../state/profile_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import 'photo_widgets.dart';
import 'voice_widgets.dart';
import 'chat_motion.dart';
import '../../../state/feedback_providers.dart';

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
              tooltip: L.t.changerPhoto,
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
          AsyncError() => Text(
            L.t.photoIndisponible,
            style: const TextStyle(color: Colors.white70),
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
        label: p != null ? L.t.voirPhotoGrand : L.t.photo,
        child: InkWell(
          key: const Key('fiche.avatar'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          // Lot 7.2c1 : pastille appareil photo pour ceux qui peuvent changer la photo.
          child: onEdit == null
              ? avatar
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatar,
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        key: const Key('fiche.avatar.badge'),
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 3,
                          ),
                        ),
                        child: Icon(
                          Icons.photo_camera_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
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
          title: Text(L.t.medias),
          subtitle: Text(
            media.isEmpty ? L.t.aucunePhotoNiVocalPour : L.t.mediaCountErased(media.length),
          ),
          trailing: media.isEmpty ? null : const Icon(Icons.chevron_right),
          onTap: media.isEmpty ? null : openAll,
        ),
        if (media.isNotEmpty) ...[
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
          const SizedBox(height: PrivioSpacing.m),
        ],
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
      // Lot 7.2a : écran en liste, fond blanc (comme Discussions).
      backgroundColor: PrivioPalette.of(context).sheet,
      appBar: AppBar(title: Text(L.t.medias)),
      body: switch (media) {
        AsyncData(:final value) when value.isEmpty => EmptyView(
          icon: Icons.perm_media_outlined,
          title: L.t.aucunMedia,
          message: L.t.photosVocauxEffacentAvecLeurs,
        ),
        AsyncData(:final value) => CustomScrollView(
          key: const Key('media.screen'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.l),
                child: Text(L.t.ilsEffacentAvecLeursMessages, style: theme.textTheme.bodySmall),
              ),
            ),
            if (value.any((m) => m.kind == 'photo')) ...[
              _header(theme, L.t.photos),
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
              _header(theme, L.t.vocaux),
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
            (L.t.n8Heures, const Duration(hours: 8)),
            (L.t.n1Semaine, const Duration(days: 7)),
            (L.t.toujours, const Duration(days: 3650)),
          ])
            ListTile(
              key: Key('mute.${d.inHours}'),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, d),
            ),
          if (s.isMuted(now))
            ListTile(
              key: const Key('mute.off'),
              title: Text(L.t.reactiverNotifications),
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
  if (until == null || !until.isAfter(now)) return L.t.activees;
  if (until.difference(now).inDays > 365) return L.t.desactivees;
  final l = until.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return L.t.desactiveesJusquDayMonthHour(two(l.day), two(l.month), two(l.hour), two(l.minute));
}

// ---------------------------------------------------------------------------
// Lot 7.2a : « Vider la discussion » depuis la fiche (ou la discussion) ; confidentialité
// propre à la discussion.
// ---------------------------------------------------------------------------

/// Choix (chez moi / pour nous deux ou pour tous), confirmation, puis vidage. L'écran
/// appelant reste affiché ; la discussion se recharge si elle est ouverte en dessous.
/// Renvoie 'cleared', 'requested' ou null (annulé, ou échec signalé).
Future<String?> chooseClear(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary s, {
  bool sweep = true,
}) async {
  final everyoneAllowed = s.isGroup ? s.isAdmin : !(s.blocked || s.peerDeleted);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.l,
              0,
              PrivioSpacing.l,
              PrivioSpacing.s,
            ),
            child: Text(L.t.viderDiscussion, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (everyoneAllowed)
            ListTile(
              key: const Key('clear.everyone'),
              leading: const Icon(Icons.group_remove_outlined),
              title: Text(s.isGroup ? L.t.pourTousMembres : L.t.pourNousDeux),
              subtitle: Text(
                s.isGroup
                    ? L.t.tousMessagesVocauxPhotosDisparaissent
                    : L.t.titleDoitAccepterEnsuiteTout(s.title),
              ),
              onTap: () => Navigator.pop(ctx, 'everyone'),
            ),
          ListTile(
            key: const Key('clear.me'),
            leading: const Icon(Icons.person_remove_outlined),
            title: Text(L.t.seulementChezMoi),
            subtitle: Text(
              s.isGroup ? L.t.votreCopieEstVideeAutres : L.t.votreCopieEstVideeTitle(s.title),
            ),
            onTap: () => Navigator.pop(ctx, 'me'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  final everyone = choice == 'everyone';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        everyone
            ? (s.isGroup ? L.t.viderGroupePourTous : L.t.demanderTitleToutVider(s.title))
            : L.t.viderDiscussionChezVous,
      ),
      content: Text(
        everyone && !s.isGroup
            ? L.t.siTitleAccepteTousMessages(s.title)
            : L.t.messagesActuelsDisparaissentDefinitivementVotre,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('clear.confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(everyone && !s.isGroup ? L.t.envoyerDemande : L.t.vider),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await ref.read(messagingApiProvider).clearConversation(s.id, everyone: everyone);
    await ref.read(conversationsProvider.notifier).refresh();
    ref
      ..invalidate(chatProvider(s.id))
      ..invalidate(conversationMediaProvider(s.id));
    // Lot 7.2b2 : son de balayage ; depuis une fiche, le balai traverse l'écran (dans la
    // discussion, ce sont les bulles qui s'effacent en cascade).
    if (r != 'requested') {
      ref.read(feedbackProvider).sound(PrivioSound.cleared);
      if (sweep && context.mounted) showSweep(context);
    }
    messenger.showSnackBar(
      SnackBar(
        key: const Key('clear.done'),
        content: Text(r == 'requested' ? L.t.demandeEnvoyeeTitle(s.title) : L.t.discussionVidee),
      ),
    );
    return r;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    return null;
  }
}

/// Réglages de confidentialité de cette discussion (null : comme dans mes réglages).
final conversationPrivacyProvider = FutureProvider.autoDispose.family<ConversationPrivacy, String>(
  (ref, id) => ref.watch(messagingApiProvider).getConversationPrivacy(id),
);

/// Section « Confidentialité de cette discussion » d'une fiche. Accusés de lecture et
/// « en train d'écrire » partout ; en discussion à deux, aussi en ligne, photo, À propos.
class ConversationPrivacySection extends ConsumerWidget {
  const ConversationPrivacySection({super.key, required this.summary});

  final ConversationSummary summary;

  String _title(String key) => switch (key) {
    'receipts' => L.t.accusesLecture,
    'typing' => L.t.trainEcrire2,
    'presence' => L.t.ligneVu,
    'avatar' => L.t.photoProfil,
    _ => L.t.propos,
  };

  IconData _icon(String key) => switch (key) {
    'receipts' => Icons.done_all,
    'typing' => Icons.keyboard_outlined,
    'presence' => Icons.circle_outlined,
    'avatar' => Icons.account_circle_outlined,
    _ => Icons.info_outline,
  };

  /// Valeur du compte, en clair (« Activés », « Mes contacts »…).
  String _accountValue(String key, PrivacySettings g) => switch (key) {
    'receipts' => g.readReceipts ? L.t.actives : L.t.desactives,
    'typing' => g.typing ? L.t.active : L.t.desactive,
    'presence' => visibilityLabel(g.presence).toLowerCase(),
    'avatar' => visibilityLabel(g.avatar).toLowerCase(),
    _ => visibilityLabel(g.about).toLowerCase(),
  };

  (String, String) _choices(String key) => switch (key) {
    'receipts' => (L.t.actives2, L.t.desactives2),
    'typing' => (L.t.active2, L.t.desactive2),
    _ => (L.t.montreTitle(summary.title), L.t.cacheTitle(summary.title)),
  };

  String _label(String key, bool? v, PrivacySettings? g) {
    final (on, off) = _choices(key);
    if (v == true) return on;
    if (v == false) return off;
    return g == null ? L.t.commeDansMesReglages : L.t.commeDansMesReglagesG(_accountValue(key, g));
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    String key,
    ConversationPrivacy current,
    PrivacySettings? g,
  ) async {
    final (on, off) = _choices(key);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: switch (current.valueOf(key)) {
            true => 'on',
            false => 'off',
            null => 'default',
          },
          onChanged: (v) => Navigator.pop(ctx, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.l,
                  0,
                  PrivioSpacing.l,
                  PrivioSpacing.s,
                ),
                child: Text(_title(key), style: Theme.of(ctx).textTheme.titleMedium),
              ),
              RadioListTile<String>(
                key: Key('conv_privacy.$key.default'),
                value: 'default',
                title: Text(L.t.commeDansMesReglages),
                subtitle: g == null ? null : Text(_accountValue(key, g)),
              ),
              RadioListTile<String>(key: Key('conv_privacy.$key.on'), value: 'on', title: Text(on)),
              RadioListTile<String>(
                key: Key('conv_privacy.$key.off'),
                value: 'off',
                title: Text(off),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final next = current.withValue(key, switch (picked) {
      'on' => true,
      'off' => false,
      _ => null,
    });
    try {
      await ref
          .read(messagingApiProvider)
          .setConversationPrivacy(summary.id, next, group: summary.isGroup);
      ref.invalidate(conversationPrivacyProvider(summary.id));
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final current = ref.watch(conversationPrivacyProvider(summary.id)).value;
    final account = ref.watch(privacyProvider).value;
    final keys = summary.isGroup ? const ['receipts', 'typing'] : ConversationPrivacy.keys;
    return Column(
      key: const Key('conv_privacy'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in keys)
          ListTile(
            key: Key('conv_privacy.$k'),
            enabled: current != null,
            leading: Icon(_icon(k), color: p.accentText),
            title: Text(_title(k)),
            subtitle: Text(_label(k, current?.valueOf(k), account)),
            trailing: const Icon(Icons.chevron_right),
            onTap: current == null ? null : () => _pick(context, ref, k, current, account),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Lot 7.2b1 : supprimer une discussion ou un groupe.
// ---------------------------------------------------------------------------

/// Discussion à deux : « Seulement chez moi » ou « Pour nous deux » (accord de l'autre).
/// Groupe (créateur, administrateurs) : supprimé pour tous. Après suppression, retour à la
/// liste. Renvoie 'deleted', 'requested' ou null.
Future<String?> chooseDelete(BuildContext context, WidgetRef ref, ConversationSummary s) async {
  final bool everyone;
  if (s.isGroup) {
    if (!s.isAdmin) return null;
    everyone = true;
  } else {
    final peerOk = !(s.blocked || s.peerDeleted);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.l,
                0,
                PrivioSpacing.l,
                PrivioSpacing.s,
              ),
              child: Text(L.t.supprimerDiscussion, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (peerOk)
              ListTile(
                key: const Key('delete.everyone'),
                leading: const Icon(Icons.group_remove_outlined),
                title: Text(L.t.pourNousDeux),
                subtitle: Text(L.t.titleDoitAccepterEnsuiteDiscussion(s.title)),
                onTap: () => Navigator.pop(ctx, 'everyone'),
              ),
            ListTile(
              key: const Key('delete.me'),
              leading: const Icon(Icons.person_remove_outlined),
              title: Text(L.t.seulementChezMoi),
              subtitle: Text(L.t.elleDisparaitVotreListeVotre(s.title)),
              onTap: () => Navigator.pop(ctx, 'me'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return null;
    everyone = choice == 'everyone';
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        s.isGroup
            ? L.t.supprimerTitlePourTous(s.title)
            : everyone
            ? L.t.demanderTitleSupprimerDiscussion(s.title)
            : L.t.supprimerDiscussionChezVous,
      ),
      content: Text(
        s.isGroup
            ? L.t.tousMessagesPhotosVocauxSont
            : everyone
            ? L.t.siTitleAccepteTousMessages2(s.title)
            : L.t.messagesDisparaissentDefinitivementVotreTelephone,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('delete.confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(everyone && !s.isGroup ? L.t.envoyerDemande : L.t.supprimer),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final r = await ref.read(messagingApiProvider).deleteConversation(s.id, everyone: everyone);
    await ref.read(conversationsProvider.notifier).refresh();
    if (r == 'deleted') {
      router.go(s.isGroup ? Routes.groups : Routes.discussions);
      messenger.showSnackBar(
        SnackBar(
          key: const Key('delete.done'),
          content: Text(s.isGroup ? L.t.groupeSupprime : L.t.discussionSupprimee),
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(L.t.demandeEnvoyeeTitle(s.title))));
    }
    return r;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    return null;
  }
}
