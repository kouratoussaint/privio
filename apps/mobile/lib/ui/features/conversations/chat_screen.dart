import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/reactions.dart';
import '../../../core/util/time_format.dart';
import '../../../data/services/audio/voice_recorder.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/join_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../../state/providers.dart';
import '../../../state/voice_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/swipe_actions.dart';
import '../../core/widgets/state_views.dart';
import '../home/discussions_tab.dart' show OfflineBanner;
import '../home/hidden_conversations.dart' show setConversationHidden;
import '../../../data/services/photo_picker.dart' show PhotoSource;
import '../../core/widgets/ttl_picker.dart';
import '../groups/mentions.dart';
import 'photo_widgets.dart';
import 'report_sheet.dart';
import 'voice_widgets.dart';
import 'conversation_details.dart';
import 'chat_motion.dart';
import '../../core/motion/motion.dart';
import '../../../state/feedback_providers.dart';
import '../../core/motion/illustrations.dart';
import 'message_extras.dart';
import 'expression_panel.dart';
import '../settings/wallpaper.dart';
import 'rich_messages.dart';
import 'gif_picker.dart';
import 'person_card.dart';
import 'bubble_shape.dart';

import 'package:flutter/semantics.dart';

import '../../../state/session_controller.dart';
import '../groups/group_screens.dart';
import '../calls/call_screen.dart';
import '../../../state/contact_labels_providers.dart';
import 'verify_in_person.dart';
import 'polls.dart';
import '../../core/widgets/privio_menu.dart';
import '../../core/emoji/big_emojis.dart';

/// État d'un message envoyé, déduit des pointeurs d'accusés du correspondant.
enum Delivery { sent, delivered, read }

Delivery deliveryOf(ChatMessage m, ConversationSummary? s) {
  if (s?.peerReadUpTo != null && !s!.peerReadUpTo!.isBefore(m.sentAt)) return Delivery.read;
  if (s?.peerDeliveredUpTo != null && !s!.peerDeliveredUpTo!.isBefore(m.sentAt)) {
    return Delivery.delivered;
  }
  return Delivery.sent;
}

/// Écran 10 — conversation. Appui long sur un message : réagir, répondre, modifier
/// (60 min), supprimer pour moi ou pour tout le monde. Volontairement AUCUNE action
/// « copier » ni « transférer » (SEC-007/SEC-008) et aucun texte sélectionnable.
/// Micro (champ vide) : message vocal de 30 s au plus, toujours préécouté avant envoi.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;
  Timer? _poll;

  /// Lot 10.1 : réveil à la seconde près quand un message « effacer après lecture » arrive
  /// à échéance (le réveil régulier ne passe que toutes les 15 s).
  Timer? _eraseTimer;
  DateTime? _eraseAt;

  void _scheduleErase(List<ChatMessage> messages, DateTime now) {
    DateTime? next;
    for (final m in messages) {
      if (m.readEraseSeconds == null || !m.expiresAt.isAfter(now)) continue;
      if (m.expiresAt.difference(now) > const Duration(minutes: 2)) continue;
      if (next == null || m.expiresAt.isBefore(next)) next = m.expiresAt;
    }
    if (next == null || next == _eraseAt) return;
    _eraseAt = next;
    _eraseTimer?.cancel();
    _eraseTimer = Timer(next.difference(now) + const Duration(milliseconds: 50), () {
      _eraseAt = null;
      if (mounted) setState(() {});
    });
  }

  ChatMessage? _replyTo;
  ChatMessage? _editing;
  int? _nextTtl;
  bool _searching = false;
  bool _preparingPhoto = false;
  final _searchCtrl = TextEditingController();

  /// Liste des messages : défilement et clés stables par message (citations).
  final _listScroll = ScrollController();
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedId;
  Timer? _highlightTimer;

  // Lot 7.2b2 : suivi des messages pour les animer (apparition, dissolution).
  final _seen = <String>{};
  bool _seeded = false;
  List<ChatMessage> _shown = const [];
  String _shownQuery = '';
  final _ghosts = <String, (ChatMessage, int)>{};

  // Lot 7.3a : panneau des émojis et autocollants (à la place du clavier).
  bool _panel = false;

  void _togglePanel() {
    if (_panel) {
      setState(() => _panel = false);
      _focus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _panel = true);
    }
  }

  double _panelHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.38).clamp(220.0, 320.0);
  }

  Future<void> _sendSticker(StickerInfo s) async {
    final replyTo = _replyTo;
    final ttl = _nextTtl;
    setState(() {
      _replyTo = null;
      _nextTtl = null;
    });
    ref.read(feedbackProvider).sound(PrivioSound.sent);
    await _guard(() => _chat.sendSticker(s.id, replyToId: replyTo?.id, ttlSeconds: ttl));
  }

  /// Lot 7.3b : GIF choisi dans la recherche.
  Future<void> _sendGif(GifResult g) async {
    final replyTo = _replyTo;
    final ttl = _nextTtl;
    setState(() {
      _replyTo = null;
      _nextTtl = null;
    });
    ref.read(feedbackProvider).sound(PrivioSound.sent);
    await _guard(() => _chat.sendGif(g, replyToId: replyTo?.id, ttlSeconds: ttl));
  }

  // Lot 7.2c2 : sélection multiple, bandeau des épinglés, retour depuis les favoris.
  final _selected = <String>{};
  int _pinIndex = 0;
  bool _jumping = false;
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(ChatMessage m) {
    if (m.isDeleted || m.isSystem) return;
    setState(() => _selected.contains(m.id) ? _selected.remove(m.id) : _selected.add(m.id));
  }

  bool _isShown(String id) {
    final now = DateTime.now();
    return (ref.read(chatProvider(widget.conversationId)).value?.messages ?? const []).any(
      (m) => m.id == id && m.isVisibleAt(now) && !m.isDeleted,
    );
  }

  /// Bandeau des épinglés : montre le message affiché, puis passe au suivant.
  Future<void> _openPinned(List<MessageRef> pins) async {
    final r = pins[_pinIndex % pins.length];
    setState(() => _pinIndex = (_pinIndex + 1) % pins.length);
    if (_isShown(r.id)) {
      await _scrollToMessage(r.id);
    } else {
      await showMessageRef(context, r, title: L.t.messageEpingle);
    }
  }

  Future<void> _togglePin(ChatMessage m, {required bool pinned}) async {
    await _guard(() async {
      await ref.read(messagingApiProvider).pinMessage(m.id, pin: !pinned);
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
      ref.read(feedbackProvider).haptic(Haptic.light);
      if (mounted) _toast(pinned ? L.t.messageDesepingle : L.t.messageEpingle2);
    });
  }

  Future<void> _setFavorite(List<ChatMessage> ms, {required bool on}) async {
    final ids = [
      for (final m in ms)
        if (!m.isDeleted && !m.isSystem) m.id,
    ];
    if (ids.isEmpty) return;
    await _guard(() async {
      await ref.read(messagingApiProvider).setFavorites(ids, on: on);
      ref.invalidate(favoriteMessagesProvider(widget.conversationId));
      ref.read(feedbackProvider).haptic(Haptic.light);
      if (!mounted) return;
      final n = ids.length;
      _toast(
        on
            ? (n > 1 ? L.t.nMessagesAjoutesFavoris(n) : L.t.ajouteFavoris)
            : (n > 1 ? L.t.nMessagesRetiresFavoris(n) : L.t.retireFavoris),
      );
    });
  }

  /// Sélection : supprimer pour moi, ou pour tout le monde si chaque message le permet.
  Future<void> _deleteSelection(List<ChatMessage> chosen, ConversationSummary? summary) async {
    if (chosen.isEmpty) return;
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final me = ref.read(currentUserIdProvider);
    final now = DateTime.now();
    final adminGroup = (summary?.isGroup ?? false) && (summary?.isAdmin ?? false);
    final canAll = chosen.every(
      (m) => !m.isDeleted && (m.senderId == me ? rules.canDeleteForAll(m, now) : adminGroup),
    );
    final n = chosen.length;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('select.delete_me'),
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(n > 1 ? L.t.supprimerNMessagesPourMoi(n) : L.t.supprimerPourMoi),
              onTap: () => Navigator.pop(ctx, 'me'),
            ),
            if (canAll)
              ListTile(
                key: const Key('select.delete_all'),
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(
                  n > 1 ? L.t.supprimerNMessagesPourTout(n) : L.t.supprimerPourToutMonde,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'all'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'all') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(n > 1 ? L.t.supprimerNMessagesPourTout2(n) : L.t.supprimerPourToutMonde2),
          content: Text(L.t.ilsSerontRemplacesParMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
            FilledButton(
              key: const Key('select.delete_all.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t.supprimer),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      ref.read(feedbackProvider).sound(PrivioSound.deletedForAll);
    }
    setState(_selected.clear);
    await _guard(() async {
      for (final m in chosen) {
        if (choice == 'all') {
          await _chat.deleteForEveryone(m.id);
        } else {
          await _chat.deleteForMe(m.id);
        }
      }
    });
  }

  PreferredSizeWidget _selectionBar(
    List<ChatMessage> chosen,
    Set<String> favoriteIds,
    ConversationSummary? summary,
  ) {
    final n = chosen.length;
    final allFavorite = chosen.isNotEmpty && chosen.every((m) => favoriteIds.contains(m.id));
    return AppBar(
      key: const Key('select.bar'),
      toolbarHeight: 64,
      leading: IconButton(
        key: const Key('select.close'),
        tooltip: L.t.annulerSelection,
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text(L.t.selectedCount(n), key: const Key('select.count')),
      actions: [
        IconButton(
          key: const Key('select.favorite'),
          tooltip: allFavorite ? L.t.retirerFavoris : L.t.ajouterFavoris,
          icon: Icon(allFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
          onPressed: () async {
            await _setFavorite(chosen, on: !allFavorite);
            if (mounted) setState(_selected.clear);
          },
        ),
        IconButton(
          key: const Key('select.delete'),
          tooltip: L.t.supprimer,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteSelection(chosen, summary),
        ),
      ],
    );
  }

  // Lot 7.2c1 : repère « X messages non lus » et bouton « descendre ».
  final _openedAt = DateTime.now();
  int? _unreadAtOpen;
  bool _scrolledToMarker = false;
  bool _awayFromBottom = false;
  int _newBelow = 0;

  /// Premier message non lu à l'ouverture (parmi ceux arrivés avant l'ouverture) et nombre
  /// de non lus. Stable pendant que la discussion reste ouverte.
  (String, int)? _unreadMarker(List<ChatMessage> visible, String? me) {
    final n = _unreadAtOpen ?? 0;
    if (n <= 0) return null;
    final incoming = [
      for (final m in visible)
        if (m.senderId != me &&
            !m.isSystem &&
            !m.isDeleted &&
            !m.sentAt.isAfter(_openedAt.add(const Duration(seconds: 5))))
          m,
    ];
    if (incoming.isEmpty) return null;
    final count = n < incoming.length ? n : incoming.length;
    return (incoming[incoming.length - count].id, count);
  }

  void _onListScroll() {
    if (!_listScroll.hasClients) return;
    // Liste à l'envers : 0 = tout en bas (derniers messages).
    final away = _listScroll.offset > 320;
    if (away != _awayFromBottom || (!away && _newBelow > 0)) {
      setState(() {
        _awayFromBottom = away;
        if (!away) _newBelow = 0;
      });
    }
  }

  Future<void> _scrollToBottom() async {
    if (!_listScroll.hasClients) return;
    setState(() => _newBelow = 0);
    final d = _listScroll.offset > 4000 ? Duration.zero : Motion.of(context, Motion.slow);
    if (d == Duration.zero) {
      _listScroll.jumpTo(0);
    } else {
      await _listScroll.animateTo(0, duration: d, curve: Motion.enter);
    }
  }

  /// À l'ouverture : la discussion se place sur le premier message non lu, s'il n'est pas
  /// déjà à l'écran.
  Future<void> _scrollToMarker(String id) async {
    BuildContext? target = _messageKeys[id]?.currentContext;
    for (var i = 0; target == null && i < 60 && _listScroll.hasClients; i++) {
      final pos = _listScroll.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      _listScroll.jumpTo(
        (pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent).toDouble(),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      target = _messageKeys[id]?.currentContext;
    }
    if (target == null || !target.mounted) return;
    final box = target.findRenderObject() as RenderBox?;
    final viewport = _listScroll.position.context.storageContext.findRenderObject() as RenderBox?;
    if (box == null || viewport == null) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    // Déjà entièrement visible : on ne bouge pas.
    if (top >= 0 && top + box.size.height <= viewport.size.height) return;
    await Scrollable.ensureVisible(target, alignment: 0.85);
  }

  /// Compare les messages affichés à la fois précédente : renvoie ceux qui viennent
  /// d'arriver (et joue le son de réception), garde ceux qui viennent de disparaître le
  /// temps de leur dissolution.
  Set<String> _track(List<ChatMessage> visible, String query, String? me) {
    final ids = {for (final m in visible) m.id};
    final appearing = <String>{};
    if (!_seeded) {
      _seen.addAll(ids);
      _seeded = true;
    } else {
      for (final m in visible) {
        if (_seen.add(m.id) && m.senderId != me && !m.isSystem) appearing.add(m.id);
      }
      if (query.isEmpty && _shownQuery.isEmpty) {
        final gone =
            _shown
                .where((m) => !ids.contains(m.id) && !m.isSystem && !_ghosts.containsKey(m.id))
                .toList()
              ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
        final cascade = gone.length >= 3;
        for (final (i, m) in gone.take(40).indexed) {
          _ghosts[m.id] = (m, cascade ? i : 0);
        }
      }
    }
    _shown = visible;
    _shownQuery = query;
    // Lot 7.2c1 : remonté dans la discussion : les nouveaux messages s'ajoutent au bouton
    // « descendre ».
    if (appearing.isNotEmpty && _awayFromBottom) _newBelow += appearing.length;
    if (appearing.isNotEmpty && ref.read(chatOnScreenProvider) == widget.conversationId) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(feedbackProvider).sound(PrivioSound.received),
      );
    }
    return appearing;
  }

  /// Photo à côté des messages reçus : celle du contact, ou celle du membre du groupe.
  ({String name, String? path, String seed})? _avatarOf(
    String senderId,
    ConversationSummary? summary,
    List<GroupMember> members,
  ) {
    if (summary == null) return null;
    if (!summary.isGroup) {
      return (name: summary.title, path: summary.peerAvatarPath, seed: summary.peerId ?? senderId);
    }
    final m = members.where((x) => x.userId == senderId).firstOrNull;
    return (name: m?.shownName ?? '?', path: m?.avatarPath, seed: senderId);
  }

  /// Lot 8.1b : nom et photo d'une personne qui a réagi.
  ({String name, String? path, String seed}) _reactorOf(
    String userId,
    ConversationSummary? summary,
    List<GroupMember> members,
  ) {
    if (userId == ref.read(currentUserIdProvider)) {
      final profile = ref.read(sessionControllerProvider).value?.account?.profile;
      return (name: profile?.displayName ?? L.t.vous, path: profile?.avatarPath, seed: userId);
    }
    // Lot 10.5 : dans un groupe « Annonces », un membre ne voit pas qui d'autre a réagi.
    if (userId.isEmpty) return (name: L.t.unMembre, path: null, seed: 'membre');
    final w = _avatarOf(userId, summary, members);
    if (w == null || w.name == '?') return (name: L.t.ancienMembre, path: null, seed: userId);
    return w;
  }

  /// Lot 7.1b : personnes choisies dans la liste « @ » (identifiant → nom inséré).
  final _mentionPicks = <String, String>{};
  bool _mentionOpen = false;

  ChatController get _chat => ref.read(chatProvider(widget.conversationId).notifier);
  VoiceRecorderController get _voice => ref.read(voiceRecorderControllerProvider.notifier);
  late final AppLifecycleListener _lifecycle;

  /// Lot 7.2b1 : la discussion n'est « lue » que si elle est vraiment à l'écran.
  late final ChatOnScreen _onScreen;
  bool _appShown = true;
  bool? _wasOnScreen;

  void _syncOnScreen(bool onScreen) {
    if (_wasOnScreen == onScreen) return;
    _wasOnScreen = onScreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      onScreen ? _onScreen.show(widget.conversationId) : _onScreen.hide(widget.conversationId);
    });
  }

  @override
  void initState() {
    super.initState();
    _onScreen = ref.read(chatOnScreenProvider.notifier);
    _listScroll.addListener(_onListScroll);
    // Lot 7.3a : toucher le champ de saisie ferme le panneau des émojis.
    _focus.addListener(() {
      if (_focus.hasFocus && _panel && mounted) setState(() => _panel = false);
    });
    // Application mise en arrière-plan pendant un enregistrement : arrêt et préécoute.
    _lifecycle = AppLifecycleListener(
      // Lot 7.2b1 : application cachée (réduite, téléphone verrouillé) : plus « à l'écran ».
      onShow: () => setState(() => _appShown = true),
      onHide: () {
        // Pas d'image affichée quand l'application est cachée : on retire tout de suite
        // (sans attendre la prochaine image).
        _appShown = false;
        _wasOnScreen = false;
        _onScreen.hide(widget.conversationId);
        setState(() {});
        if (ref.read(voiceRecorderControllerProvider) is VoiceRecording) {
          unawaited(_voice.stop().then(_afterVoiceStop));
        }
      },
    );
    // Expiration à la seconde près côté affichage, même sans réseau.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    // Filet de sécurité si la connexion temps réel est coupée (réseaux instables) :
    // une conversation ouverte reste à jour à 5 secondes près.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _chat.reload();
    });
  }

  @override
  void dispose() {
    final id = widget.conversationId;
    final onScreen = _onScreen;
    unawaited(Future<void>.microtask(() => onScreen.hide(id)));
    _lifecycle.dispose();
    _tick?.cancel();
    _poll?.cancel();
    _eraseTimer?.cancel();
    _composer.dispose();
    _searchCtrl.dispose();
    _listScroll.dispose();
    _highlightTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // Lot 7.2c2 : un nouveau message remplace le précédent (pas de file d'attente : après
  // trois « Message épinglé. », l'erreur du quatrième s'affiche tout de suite).
  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    }
  }

  Future<void> _submit() async {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    final editing = _editing;
    final replyTo = _replyTo;
    _composer.clear();
    setState(() {
      _editing = null;
      _replyTo = null;
    });
    if (editing != null) {
      await _guard(() => _chat.edit(editing.id, text));
    } else {
      final ttl = _nextTtl;
      // Seules les mentions encore présentes dans le texte comptent.
      final mentions = mentionedIds(text, _mentionPicks);
      _mentionPicks.clear();
      setState(() => _nextTtl = null);
      ref.read(feedbackProvider).sound(PrivioSound.sent);
      await _guard(
        () => _chat.send(text, replyToId: replyTo?.id, ttlSeconds: ttl, mentions: mentions),
      );
    }
  }

  /// Une mention commence (« @ » tapé) : la liste des membres est relue une fois.
  void _onMentionInput(bool isGroup) {
    if (!isGroup) return;
    final open = activeMention(_composer.value) != null;
    if (open && !_mentionOpen) ref.invalidate(mentionMembersProvider(widget.conversationId));
    _mentionOpen = open;
  }

  void _pickMention(MentionQuery q, GroupMember m) {
    _composer.value = insertMention(_composer.value, q, m.displayName);
    _mentionPicks[m.userId] = m.displayName;
    _mentionOpen = false;
    _focus.requestFocus();
  }

  Future<void> _chooseConversationTtl(ConversationSummary? summary) async {
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final current = summary?.ttlSeconds ?? rules.maxTtlSeconds;
    final picked = await showTtlPicker(
      context,
      title: L.t.dureeMessages,
      help: (summary?.isGroup ?? false)
          ? L.t.pourProchainsMessagesGroupe
          : L.t.pourProchainsMessagesChezVous,
      current: current,
      min: rules.minTtlSeconds,
      max: rules.maxTtlSeconds,
    );
    if (picked == null || picked == current || !mounted) return;
    await _guard(() => _chat.setTtl(picked));
  }

  /// Lot 10.1 : effacer après lecture (30 s, 5 min, 1 h ou désactivé).
  Future<void> _chooseReadErase(ConversationSummary s) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ReadEraseSheet(current: s.readEraseSeconds, isGroup: s.isGroup),
    );
    if (picked == null || !mounted) return;
    final seconds = picked == 0 ? null : picked;
    if (seconds == s.readEraseSeconds) return;
    await _guard(() => _chat.setReadErase(seconds));
  }

  Future<void> _chooseMessageTtl(ConversationSummary? summary) async {
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final cap = summary?.ttlSeconds ?? rules.maxTtlSeconds;
    final picked = await showTtlPicker(
      context,
      title: L.t.dureeCeMessage,
      help: L.t.pourCeMessageSeulementPlus(formatTtl(cap)),
      current: _nextTtl ?? cap,
      min: rules.minTtlSeconds,
      max: cap,
    );
    if (picked == null || !mounted) return;
    setState(() => _nextTtl = picked == cap ? null : picked);
  }

  Future<void> _retry(PendingMessage p) => _guard(() => _chat.retry(p.clientId));

  // ---------------------------------------------------------------- photos
  /// Choisir (appareil photo ou galerie), préparer (rotation, taille, AUCUNE
  /// métadonnée), aperçu avec légende et compteur, puis envoi.
  Future<void> _pickPhoto() async {
    FocusScope.of(context).unfocus();
    PhotoQuota? quota;
    try {
      // Toujours relu : le compteur affiché dans la saisie peut dater (autre appareil).
      quota = await ref.refresh(photoQuotaProvider.future);
    } on Object {
      quota = null; // hors connexion : le serveur tranchera à l'envoi
    }
    if (!mounted) return;
    final source = await showPhotoSourceSheet(context, quota: quota);
    if (source == null || !mounted) return;
    try {
      final picker = ref.read(photoPickerProvider);
      final lock = ref.read(appLockProvider.notifier);
      // Galerie : plusieurs photos, au plus celles qui restent aujourd'hui (lot 4.5).
      final raws = source == PhotoSource.gallery
          ? await lock.runExternal(
              () => picker.pickMany(limit: quota?.remaining ?? kMaxPhotosPerPick),
            )
          : [?await lock.runExternal(() => picker.pick(source))];
      if (raws.isEmpty || !mounted) return;
      setState(() => _preparingPhoto = true);
      final prepare = ref.read(photoPreparerProvider);
      // Lot 10.3 : Mode éco → photos allégées (1 024 px, qualité 65).
      final eco = ref.read(ecoOnProvider);
      final photos = [for (final raw in raws) await prepare(raw, eco: eco)];
      if (!mounted) return;
      setState(() => _preparingPhoto = false);
      final drafts = await Navigator.of(context).push<List<PhotoDraft>>(
        MaterialPageRoute(
          builder: (_) => PhotoComposeScreen(photos: photos, quota: quota),
        ),
      );
      if (drafts == null || drafts.isEmpty || !mounted) return;
      final replyTo = _replyTo;
      final ttl = _nextTtl;
      setState(() {
        _replyTo = null;
        _nextTtl = null;
      });
      ref.read(feedbackProvider).sound(PrivioSound.sent);
      // Un message par photo ; un échec n'empêche pas les suivantes (« Non envoyé »).
      for (final (i, d) in drafts.indexed) {
        await _chat.sendPhoto(
          d.photo,
          caption: d.caption,
          replyToId: i == 0 ? replyTo?.id : null,
          ttlSeconds: ttl,
          viewOnce: d.viewOnce,
        );
      }
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    } finally {
      if (mounted && _preparingPhoto) setState(() => _preparingPhoto = false);
      if (mounted) ref.invalidate(photoQuotaProvider);
    }
  }

  /// Lot 7.3b : ouvrir une photo / un vocal en vue unique, puis le refermer pour de bon.
  String? _openingViewOnce;

  Future<void> _openViewOnce(ChatMessage m, String? peerName) async {
    if (_openingViewOnce != null) return;
    setState(() => _openingViewOnce = m.id);
    Uint8List bytes;
    try {
      bytes = await _chat.openViewOnce(m);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _openingViewOnce = null);
        _toast(toAppFailure(e).message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingViewOnce = null);
    if (m.kind == 'voice') {
      await showViewOnceVoice(context, bytes);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ViewOncePhotoScreen(bytes: bytes, title: m.senderName ?? peerName ?? L.t.photo),
        ),
      );
    }
    await _chat.closeViewOnce(m.id);
  }

  void _openPhoto(ChatMessage m, Uint8List bytes, String? peerName) {
    final me = ref.read(currentUserIdProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(
          bytes: bytes,
          title: m.senderId == me ? L.t.vous : (m.senderName ?? peerName ?? L.t.photo),
          caption: m.body,
          sentAt: m.sentAt,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- vocaux
  Future<void> _startVoice({required bool locked}) async {
    FocusScope.of(context).unfocus();
    ref.read(feedbackProvider)
      ..sound(PrivioSound.voiceStart)
      ..haptic(Haptic.medium);
    try {
      final permission = await _voice.start(locked: locked);
      if (!mounted) return;
      switch (permission) {
        case MicPermission.granted:
          break;
        case MicPermission.denied:
          _toast(const AppFailure(FailureCode.microphoneDenied).message);
        case MicPermission.permanentlyDenied:
          await _askMicrophoneSettings();
      }
    } on Object catch (e) {
      if (mounted) _toast(toAppFailure(e).message);
    }
  }

  Future<void> _releaseVoice() async => _afterVoiceStop(await _voice.release());

  void _afterVoiceStop(VoiceStopResult result) {
    if (!mounted) return;
    ref.read(feedbackProvider).sound(PrivioSound.voiceStop);
    if (result == VoiceStopResult.tooShort) {
      _toast(const AppFailure(FailureCode.voiceTooShort).message);
    } else if (result == VoiceStopResult.failed) {
      _toast(const AppFailure(FailureCode.microphoneUnavailable).message);
    }
  }

  Future<void> _askMicrophoneSettings() async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.autoriserMicro),
        content: Text(L.t.microEstDesactivePourPrivio),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.plusTard)),
          FilledButton(
            key: const Key('voice.open_settings'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.ouvrirReglages),
          ),
        ],
      ),
    );
    if (open == true) await openMicrophoneSettings();
  }

  /// Lot 7.3b : le prochain vocal part en vue unique.
  bool _voiceOnce = false;

  Future<void> _sendVoice() async {
    final preview = await _voice.take();
    if (preview == null || !mounted) return;
    final replyTo = _replyTo;
    final ttl = _nextTtl;
    final once = _voiceOnce;
    setState(() {
      _replyTo = null;
      _nextTtl = null;
      _voiceOnce = false;
    });
    ref.read(feedbackProvider).sound(PrivioSound.sent);
    await _guard(
      () => _chat.sendVoice(
        preview.audio,
        durationMs: preview.duration.inMilliseconds,
        waveform: preview.waveform,
        replyToId: replyTo?.id,
        ttlSeconds: ttl,
        viewOnce: once,
      ),
    );
  }

  /// Bouton de droite : envoyer (texte saisi ou modification), micro (champ vide),
  /// ou arrêter (enregistrement verrouillé). Le micro garde la même place pendant un
  /// enregistrement maintenu, pour ne pas interrompre le geste.
  String _trailingKind(TextEditingValue value, VoiceRecState rec) {
    if (rec is VoiceRecording && rec.locked) return 'stop';
    if (rec is VoiceRecording ||
        (ref.read(appFeaturesProvider).voice && value.text.trim().isEmpty && _editing == null)) {
      return 'mic';
    }
    return _editing != null ? 'edit' : 'send';
  }

  Widget _trailing(TextEditingValue value, VoiceRecState rec, bool dark) {
    // Lot 5.5 : vocaux désactivés dans la console → bouton d'envoi (inactif sans texte).
    final voiceOn = ref.watch(appFeaturesProvider).voice;
    if (rec is VoiceRecording && rec.locked) {
      return SizedBox(
        width: 50,
        height: 50,
        child: IconButton.filled(
          key: const Key('voice.stop'),
          tooltip: L.t.arreterEcouter,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => unawaited(_voice.stop().then(_afterVoiceStop)),
          icon: const Icon(Icons.stop_rounded),
        ),
      );
    }
    if (rec is VoiceRecording || (voiceOn && value.text.trim().isEmpty && _editing == null)) {
      return MicButton(onStart: _startVoice, onRelease: _releaseVoice);
    }
    final empty = value.text.trim().isEmpty && _editing == null;
    return SizedBox(
      width: 50,
      height: 50,
      child: IconButton.filled(
        key: const Key('chat.send'),
        tooltip: _editing != null ? L.t.enregistrerModification : L.t.envoyer,
        style: IconButton.styleFrom(
          backgroundColor: dark ? PrivioColors.lilac : PrivioColors.purple,
          foregroundColor: dark ? PrivioColors.navy : Colors.white,
        ),
        onPressed: empty ? null : _submit,
        icon: Icon(_editing != null ? Icons.check : Icons.send),
      ),
    );
  }

  // ---------------------------------------------------------------- Lot 2.F : gestes
  void _startReply(ChatMessage m) {
    // Lot 10.5 : on ne répond pas à un sondage (on y vote).
    if (m.isDeleted || m.isSystem || m.isPoll) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _editing = null;
      _replyTo = m;
    });
    _focus.requestFocus();
  }

  /// Double appui : réaction par défaut (réglable) ; un second double appui la retire.
  Future<void> _quickReact(ChatMessage m) async {
    if (m.isDeleted || m.isSystem) return;
    final emoji = ref.read(quickReactionProvider).value ?? '❤️';
    // Lot 7.2b2 : l'émoji s'envole au-dessus de la bulle.
    showReactionBurst(context, _messageKeys[m.id], emoji);
    ref.read(feedbackProvider)
      ..haptic(Haptic.light)
      ..sound(PrivioSound.reaction);
    await _guard(() => _chat.toggleReaction(m.id, emoji));
  }

  /// Glisser vers la gauche : supprimer, avec choix et confirmation (jamais d'office).
  Future<void> _swipeDelete(ChatMessage m) async {
    final mine = m.senderId == ref.read(currentUserIdProvider);
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final forAll = mine && !m.isSystem && rules.canDeleteForAll(m, DateTime.now());
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.supprimerCeMessage),
        content: Text(forAll ? L.t.pourVousSeulementOuPour : L.t.messageNeSeraPlusAffiche),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.t.annuler)),
          TextButton(
            key: const Key('swipe.delete_me'),
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: Text(L.t.pourMoi),
          ),
          if (forAll)
            FilledButton(
              key: const Key('swipe.delete_all'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: Text(L.t.pourToutMonde),
            ),
        ],
      ),
    );
    if (choice == 'me') await _guard(() => _chat.deleteForMe(m.id));
    if (choice == 'all') {
      ref.read(feedbackProvider).sound(PrivioSound.deletedForAll);
      await _guard(() => _chat.deleteForEveryone(m.id));
    }
  }

  /// Vider la discussion (lot 4.3) : chez moi, ou pour tout le monde (1:1 : avec l'accord
  /// de l'autre ; groupe : administrateurs).
  /// Lot 7.2a : même parcours que depuis la fiche (choix, confirmation, vidage).
  /// Lot 8.1b : menu ⋮ d'une discussion ou d'un groupe.
  List<PrivioMenuItem<String>> _menuItems(ConversationSummary s, bool canSetTtl) {
    final now = DateTime.now();
    PrivioMenuItem<String> item(
      String v,
      IconData icon,
      String label, {
      Color? tint,
      bool danger = false,
    }) => PrivioMenuItem<String>(
      key: Key(v == 'clear' ? 'chat.clear' : 'chat.menu.$v'),
      value: v,
      icon: icon,
      label: label,
      tint: tint,
      danger: danger,
    );
    // Lot 8.5a : carte flottante ; au-delà de 6 actions, « Voir plus ».
    return [
      item(
        'info',
        Icons.info_outline,
        s.isGroup ? L.t.infosGroupe : L.t.voirFiche,
        tint: MenuTint.violet,
      ),
      // Lot 10.5 : sondage éphémère (groupes, pour qui peut écrire).
      if (s.canSendPoll) item('poll', Icons.poll_outlined, L.t.nouveauSondage, tint: MenuTint.teal),
      item('search', Icons.search, L.t.rechercher, tint: MenuTint.blue),
      item('media', Icons.perm_media_outlined, L.t.medias, tint: MenuTint.teal),
      item('favorites', Icons.star_outline_rounded, L.t.messagesFavoris, tint: MenuTint.pink),
      if (!s.isGroup && canSetTtl)
        item('ttl', Icons.timer_outlined, L.t.dureeMessages, tint: MenuTint.amber),
      // Lot 10.1
      if (s.canSetReadErase)
        item(
          'erase',
          Icons.local_fire_department_outlined,
          L.t.effacerApresLecture,
          tint: MenuTint.pink,
        ),
      if (s.isGroup)
        item('notifications', Icons.notifications_outlined, L.t.notifications, tint: MenuTint.blue)
      else
        item(
          'mute',
          s.isMuted(now) ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          s.isMuted(now) ? L.t.reactiverNotifications : L.t.sourdine,
          tint: MenuTint.blue,
        ),
      item('wallpaper', Icons.wallpaper_outlined, L.t.fondEcran, tint: MenuTint.green),
      // Lot 10.2
      item(
        'secret',
        s.secret ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        s.secret ? L.t.nePlusMasquer : L.t.masquerDiscussion,
        tint: MenuTint.gray,
      ),
      if (s.isGroup && s.isAdmin)
        item('invite', Icons.person_add_alt_1_outlined, L.t.inviter, tint: MenuTint.violet),
      item('clear', Icons.cleaning_services_outlined, L.t.viderDiscussion, tint: MenuTint.gray),
      if (s.isGroup)
        item('leave', Icons.logout_rounded, L.t.quitterGroupe, danger: true)
      else if (!s.blocked && s.peerId != null)
        item('block', Icons.block, L.t.bloquer, danger: true),
      item('report', Icons.flag_outlined, L.t.signaler, danger: true),
    ];
  }

  Future<void> _menu(String v, ConversationSummary s, bool canSetTtl) async {
    final nav = Navigator.of(context);
    switch (v) {
      case 'info':
        await context.push(Routes.contact(s.id));
      case 'poll':
        final ttl = _nextTtl;
        setState(() => _nextTtl = null);
        await createPoll(context, ref, s.id, ttlSeconds: ttl);
      case 'search':
        setState(() {
          _searching = true;
          _searchCtrl.clear();
        });
      case 'media':
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationMediaScreen(conversationId: s.id, title: s.title),
          ),
        );
      case 'favorites':
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => FavoritesScreen(conversationId: s.id, title: s.title),
          ),
        );
      case 'ttl':
        await _chooseConversationTtl(s);
      case 'erase':
        await _chooseReadErase(s);
      case 'secret':
        await setConversationHidden(context, ref, s, !s.secret);
      case 'mute':
        await chooseMute(context, ref, s);
      case 'notifications':
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const Key('chat.menu.mute'),
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(s.isMuted(DateTime.now()) ? L.t.sourdineActivee : L.t.mettreSourdine),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(chooseMute(context, ref, s));
                  },
                ),
                MentionsOnlyTile(conversationId: s.id),
              ],
            ),
          ),
        );
      case 'wallpaper':
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => WallpaperScreen(conversationId: s.id, title: s.title),
          ),
        );
      case 'invite':
        await context.push(Routes.groupInvite(s.id));
      case 'clear':
        await _chooseClear(s);
      case 'leave':
        if (await confirmLeaveGroup(context, ref, s) && mounted) context.go(Routes.groups);
      case 'block':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L.t.bloquerTitle(s.title)),
            content: Text(L.t.vousNePourrezPlusVous),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
              FilledButton(
                key: const Key('chat.block.confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(L.t.bloquer),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        await _guard(() => setBlocked(ref, s.peerId!, blocked: true));
        if (mounted) _toast(L.t.titleEstBloque(s.title));
      case 'report':
        await showReportSheet(
          context,
          reportedUserId: s.isGroup ? null : s.peerId,
          reportedName: s.title,
          conversationId: s.id,
        );
    }
  }

  Future<void> _chooseClear(ConversationSummary s) async {
    final r = await chooseClear(context, ref, s, sweep: false);
    if (r != null && mounted) await _afterClear();
  }

  Future<void> _respondClear(bool? accept) async {
    final api = ref.read(messagingApiProvider);
    try {
      if (accept == null) {
        await api.cancelClearRequest(widget.conversationId);
        _toast(L.t.demandeAnnulee);
      } else {
        final r = await api.respondClearRequest(widget.conversationId, accept: accept);
        if (r == 'deleted') {
          // Lot 7.2b1 : demande de suppression acceptée : retour à la liste.
          await ref.read(conversationsProvider.notifier).refresh();
          if (!mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          context.go(Routes.discussions);
          messenger.showSnackBar(SnackBar(content: Text(L.t.discussionSupprimee)));
          return;
        }
        _toast(r == 'cleared' ? L.t.discussionVidee : L.t.demandeRefusee);
      }
    } on Object catch (e) {
      _toast(toAppFailure(e).message);
    }
    await _afterClear();
  }

  Future<void> _afterClear() async {
    await ref.read(conversationsProvider.notifier).refresh();
    await _chat.reload();
  }

  /// Toucher une citation : remonter au message d'origine s'il est encore là.
  ///
  /// La liste ne construit que les messages proches de l'écran : si l'original est plus
  /// haut, on remonte par pas jusqu'à ce qu'il soit construit, puis on le centre et on le
  /// met brièvement en évidence.
  Future<void> _scrollToMessage(String id) async {
    final now = DateTime.now();
    final present = (ref.read(chatProvider(widget.conversationId)).value?.messages ?? const []).any(
      (m) => m.id == id && m.isVisibleAt(now) && !m.isDeleted,
    );
    if (!present) {
      _toast(L.t.ceMessageEteEfface);
      return;
    }
    BuildContext? target = _messageKeys[id]?.currentContext;
    for (var i = 0; target == null && i < 60 && _listScroll.hasClients; i++) {
      final pos = _listScroll.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      _listScroll.jumpTo(
        (pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent).toDouble(),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      target = _messageKeys[id]?.currentContext;
    }
    if (target == null || !target.mounted) {
      _toast(L.t.ceMessageEteEfface);
      return;
    }
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      alignment: 0.5,
    );
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightedId = id);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  Future<void> _showActions(ChatMessage m, {required bool mine}) async {
    if (m.isDeleted) return;
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final now = DateTime.now();
    final me = ref.read(currentUserIdProvider);
    final myReaction = m.reactions.where((r) => r.userId == me).firstOrNull?.emoji;
    final summary = ref.read(conversationSummaryProvider(widget.conversationId));
    final adminDelete = !mine && (summary?.isGroup ?? false) && (summary?.isAdmin ?? false);
    // Lot 7.2c2 : épingler (à deux : les deux ; groupe : administrateurs), favori, infos.
    final canPin = !(summary?.isGroup ?? false) || (summary?.isAdmin ?? false);
    final pinned = (ref.read(pinnedMessagesProvider(widget.conversationId)).value ?? const []).any(
      (r) => r.id == m.id,
    );
    final favorite = (ref.read(favoriteMessagesProvider(widget.conversationId)).value ?? const [])
        .any((r) => r.id == m.id);
    final action = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in kQuickReactions)
                      IconButton(
                        key: Key('react.$e'),
                        tooltip: e == myReaction ? L.t.retirerE(e) : L.t.reagirE(e),
                        isSelected: e == myReaction,
                        // Sept boutons sur un écran étroit (320 dp).
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(ctx, 'react:$e'),
                        icon: Text(e, style: Theme.of(ctx).textTheme.headlineSmall),
                      ),
                    // Lot 7.3a : n'importe quel émoji.
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      key: const Key('react.more'),
                      tooltip: L.t.autresEmojis,
                      onPressed: () => Navigator.pop(ctx, 'react_more'),
                      icon: const Icon(Icons.add_reaction_outlined),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (!m.isPoll)
                ListTile(
                  key: const Key('action.reply'),
                  leading: const Icon(Icons.reply),
                  title: Text(L.t.repondre),
                  onTap: () => Navigator.pop(ctx, 'reply'),
                ),
              // Lot 10.5 : le créateur ferme son sondage.
              if (mine && m.isPoll && m.poll != null && !m.poll!.closed)
                ListTile(
                  key: const Key('action.close_poll'),
                  leading: const Icon(Icons.lock_outline),
                  title: Text(L.t.sondageFermer),
                  onTap: () => Navigator.pop(ctx, 'close_poll'),
                ),
              if (mine && rules.canEdit(m, now))
                ListTile(
                  key: const Key('action.edit'),
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(L.t.modifier),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              if (canPin)
                ListTile(
                  key: const Key('action.pin'),
                  leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  title: Text(pinned ? L.t.desepingler : L.t.epingler),
                  onTap: () => Navigator.pop(ctx, 'pin'),
                ),
              ListTile(
                key: const Key('action.favorite'),
                leading: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded),
                title: Text(favorite ? L.t.retirerFavoris : L.t.ajouterFavoris),
                onTap: () => Navigator.pop(ctx, 'favorite'),
              ),
              if (mine)
                ListTile(
                  key: const Key('action.info'),
                  leading: const Icon(Icons.info_outline),
                  title: Text(L.t.infos),
                  onTap: () => Navigator.pop(ctx, 'info'),
                ),
              ListTile(
                key: const Key('action.select'),
                leading: const Icon(Icons.checklist_rounded),
                title: Text(L.t.selectionner),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
              ListTile(
                key: const Key('action.delete_me'),
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(L.t.supprimerPourMoi),
                onTap: () => Navigator.pop(ctx, 'delete_me'),
              ),
              if (!mine)
                ListTile(
                  key: const Key('action.report'),
                  leading: Icon(Icons.flag_outlined, color: Theme.of(ctx).colorScheme.error),
                  title: Text(L.t.signaler),
                  onTap: () => Navigator.pop(ctx, 'report'),
                ),
              if ((mine && rules.canDeleteForAll(m, now)) || adminDelete)
                ListTile(
                  key: const Key('action.delete_all'),
                  leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    L.t.supprimerPourToutMonde,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete_all'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'react_more') {
      final emoji = await pickReactionEmoji(context);
      if (emoji == null || !mounted) return;
      ref.read(feedbackProvider).sound(PrivioSound.reaction);
      await _guard(() => _chat.toggleReaction(m.id, emoji));
    } else if (action.startsWith('react:')) {
      ref.read(feedbackProvider).sound(PrivioSound.reaction);
      await _guard(() => _chat.toggleReaction(m.id, action.substring(6)));
    } else if (action == 'reply') {
      _startReply(m);
    } else if (action == 'close_poll') {
      await confirmClosePoll(context, ref, m, widget.conversationId);
    } else if (action == 'pin') {
      await _togglePin(m, pinned: pinned);
    } else if (action == 'favorite') {
      await _setFavorite([m], on: !favorite);
    } else if (action == 'info') {
      await showMessageInfo(context, m, group: summary?.isGroup ?? false);
    } else if (action == 'select') {
      _toggleSelect(m);
    } else if (action == 'edit') {
      setState(() {
        _replyTo = null;
        _editing = m;
        _composer.text = m.body ?? '';
      });
      _focus.requestFocus();
    } else if (action == 'report') {
      if (m.senderId == null) return;
      await showReportSheet(
        context,
        reportedUserId: m.senderId!,
        reportedName: m.senderName ?? summary?.title ?? L.t.ceContact,
        conversationId: widget.conversationId,
        messageId: m.id,
      );
    } else if (action == 'delete_me') {
      await _guard(() => _chat.deleteForMe(m.id));
    } else if (action == 'delete_all') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L.t.supprimerPourToutMonde2),
          content: Text(
            adminDelete
                ? L.t.deleteGroupMessageForAll(m.senderName ?? L.t.ceMembre)
                : (summary?.isGroup ?? false)
                ? L.t.messageSeraSupprimePourTous
                : L.t.messageSeraSupprimePourVous,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
            FilledButton(
              key: const Key('action.delete_all.confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t.supprimer),
            ),
          ],
        ),
      );
      if (ok == true) {
        ref.read(feedbackProvider).sound(PrivioSound.deletedForAll);
        await _guard(() => _chat.deleteForEveryone(m.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lot 5.5 : fonctionnalités activées dans la console.
    final features = ref.watch(appFeaturesProvider);
    final summary = ref.watch(conversationSummaryProvider(widget.conversationId));
    final chat = ref.watch(chatProvider(widget.conversationId));
    ref.watch(messagingRulesProvider);
    // Préchargée : le tout premier double appui utilise déjà la réaction choisie.
    ref.watch(quickReactionProvider);
    final me = ref.watch(currentUserIdProvider);
    final p = PrivioPalette.of(context);
    final now = DateTime.now();
    final title = summary?.title ?? L.t.discussion;
    final isGroup = summary?.isGroup ?? false;
    // Lot 10.4 : vérification en personne du correspondant (badge, avis à revérifier).
    final label = isGroup ? null : ref.watch(contactLabelsProvider)[summary?.peerId];
    // Statut « en ligne » / « vu à » du correspondant, s'il le montre (lot 4.3).
    final peerId = summary?.peerId;
    final presence = isGroup || peerId == null || (summary?.blocked ?? false)
        ? ''
        : presenceLabel(
            ref.watch(presenceProvider(peerId)).value ?? const UserPresence(),
            DateTime.now(),
          );
    // Groupe : la durée est réglable par qui peut modifier le groupe ; on ne peut écrire
    // que si l'envoi n'est pas réservé aux administrateurs.
    final canPost = summary?.canPost ?? true;
    final canSetTtl = !(summary?.blocked ?? false) && (!isGroup || summary!.canEditInfo);
    final typing =
        !(summary?.blocked ?? false) && ref.watch(typingProvider).contains(widget.conversationId);
    final offline = ref.watch(offlineProvider);
    final query = _searchCtrl.text.trim().toLowerCase();
    final voice = ref.watch(voiceRecorderControllerProvider);
    // Lot 7.2b1 : à l'écran = application visible, Privio déverrouillé, discussion au-dessus
    // (ni fiche, ni feuille, ni fenêtre par-dessus).
    _syncOnScreen(
      _appShown &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          !(ref.watch(appLockProvider).value?.locked ?? false),
    );
    // Lot 7.1b : membres du groupe, pour proposer et mettre en valeur les @mentions.
    final mentionMembers = isGroup
        ? ref.watch(mentionMembersProvider(widget.conversationId)).value ?? const <GroupMember>[]
        : const <GroupMember>[];
    // Lot 7.2b2 : messages affichés, nouveaux (fondu) et disparus (dissolution).
    final visible = chat.value?.messages
        .where((m) => m.isVisibleAt(now))
        .where(
          (m) =>
              query.isEmpty ||
              (!m.isDeleted &&
                  !m.isSystem &&
                  !m.isSticker &&
                  (m.body ?? '').toLowerCase().contains(query)),
        )
        .toList();
    if (visible != null) _scheduleErase(visible, now);
    final appearing = visible == null ? const <String>{} : _track(visible, query, me);
    // Lot 7.2c1 : nombre de non lus à l'ouverture (avant que la discussion soit marquée lue).
    _unreadAtOpen ??= summary?.unreadCount;
    final marker = visible == null || query.isNotEmpty ? null : _unreadMarker(visible, me);
    if (marker != null && !_scrolledToMarker && chat.hasValue) {
      _scrolledToMarker = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scrollToMarker(marker.$1));
      });
    }
    _voice.onAutoStop = _afterVoiceStop;
    _voice.onNearEnd = () => unawaited(HapticFeedback.mediumImpact());
    // Lot 7.2c2 : épinglés, favoris, sélection.
    final pins =
        ref.watch(pinnedMessagesProvider(widget.conversationId)).value ?? const <MessageRef>[];
    final favoriteIds = <String>{
      for (final f
          in ref.watch(favoriteMessagesProvider(widget.conversationId)).value ??
              const <MessageRef>[])
        f.id,
    };
    final pinnedIds = {for (final r in pins) r.id};
    if (visible != null && _selected.isNotEmpty) {
      final ids = {
        for (final m in visible)
          if (!m.isDeleted) m.id,
      };
      _selected.removeWhere((id) => !ids.contains(id));
    }
    final chosen = [
      for (final m in visible ?? const <ChatMessage>[])
        if (_selected.contains(m.id)) m,
    ];
    // Retour depuis les favoris : la discussion montre le message.
    final jump = ref.watch(jumpToMessageProvider);
    if (jump != null && jump.$1 == widget.conversationId && chat.hasValue && !_jumping) {
      _jumping = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(jumpToMessageProvider.notifier).clear();
        await _scrollToMessage(jump.$2);
        _jumping = false;
      });
    }

    // Lot 7.2c2 : « retour » annule d'abord la sélection.
    return PopScope(
      canPop: !_selecting && !_panel,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          setState(_selected.clear);
        } else if (_panel) {
          setState(() => _panel = false);
        }
      },
      child: Scaffold(
        backgroundColor: p.chatBackground,
        appBar: _selecting
            ? _selectionBar(chosen, favoriteIds, summary)
            : AppBar(
                titleSpacing: 0,
                toolbarHeight: 64,
                actions: [
                  // Lot 9.1a / 9.2 : appel audio et vidéo (discussion à deux, contact non bloqué).
                  // Lot 5.5 : masqués quand la console les désactive.
                  if (summary != null &&
                      !summary.isGroup &&
                      !summary.blocked &&
                      !summary.peerDeleted &&
                      !_searching &&
                      features.video)
                    IconButton(
                      key: const Key('chat.video'),
                      tooltip: L.t.callVideoButton,
                      onPressed: () => startCallFrom(context, ref, summary.id, video: true),
                      icon: const Icon(Icons.videocam_outlined),
                    ),
                  if (summary != null &&
                      !summary.isGroup &&
                      !summary.blocked &&
                      !summary.peerDeleted &&
                      !_searching &&
                      features.callsAudio)
                    IconButton(
                      key: const Key('chat.call'),
                      tooltip: L.t.appeler,
                      onPressed: () => startCallFrom(context, ref, summary.id),
                      icon: const Icon(Icons.call_outlined),
                    ),
                  // Lot 8.5a : la loupe a quitté la barre (« Rechercher » est dans ⋮) ; seul
                  // le bouton pour fermer la recherche reste.
                  if (_searching)
                    IconButton(
                      key: const Key('chat.search'),
                      tooltip: L.t.fermerRecherche,
                      onPressed: () => setState(() {
                        _searching = false;
                        _searchCtrl.clear();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  if (canSetTtl && !_searching)
                    _TtlPill(
                      ttlSeconds: summary?.ttlSeconds ?? 259200,
                      onTap: () => _chooseConversationTtl(summary),
                    ),
                  if (summary != null && !_searching)
                    PrivioMenuButton<String>(
                      key: const Key('chat.menu'),
                      onSelected: (v) => unawaited(_menu(v, summary, canSetTtl)),
                      items: () => _menuItems(summary, canSetTtl),
                    ),
                ],
                title: _searching
                    ? TextField(
                        key: const Key('chat.search_input'),
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: p.onHeader),
                        cursorColor: p.onHeader,
                        decoration: InputDecoration(
                          hintText: L.t.rechercherDansMessages,
                          hintStyle: TextStyle(color: p.onHeaderMuted),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      )
                    : InkWell(
                        key: const Key('chat.contact'),
                        borderRadius: BorderRadius.circular(PrivioRadius.medium),
                        onTap: summary == null || (!isGroup && summary.peerId == null)
                            ? null
                            // Lot 7.2a : « Vider » se fait sur la fiche ; la discussion se recharge.
                            : () => context.push(Routes.contact(widget.conversationId)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xs),
                          child: LayoutBuilder(
                            // Écran étroit et grande police : l'avatar s'efface avant le nom.
                            builder: (context, box) => Row(
                              children: [
                                if (box.maxWidth >= 120) ...[
                                  UserAvatar(
                                    name: title,
                                    avatarPath: summary?.avatarPath,
                                    seed: isGroup
                                        ? widget.conversationId
                                        : (summary?.peerId ?? widget.conversationId),
                                    radius: 20,
                                    ring: p.onHeaderMuted,
                                    icon: isGroup ? Icons.groups_rounded : null,
                                  ),
                                  const SizedBox(width: PrivioSpacing.m),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(title, overflow: TextOverflow.ellipsis),
                                          ),
                                          if (label?.verified ?? false) ...[
                                            const SizedBox(width: 4),
                                            Tooltip(
                                              message: L.t.verifieEnPersonne,
                                              child: Icon(
                                                Icons.verified_user,
                                                key: const Key('chat.verified'),
                                                size: 16,
                                                color: p.onHeader,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (typing)
                                        // Lot 7.2b2 : trois points qui sautillent.
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TypingDots(color: p.onHeaderMuted),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                isGroup ? L.t.quelquEcrit : L.t.trainEcrire,
                                                key: const Key('chat.typing'),
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: p.onHeaderMuted,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        )
                                      else if (isGroup)
                                        Text(
                                          summary!.announcement
                                              ? L.t.annoncesSousTitre(
                                                  L.t.membersCount(summary.memberCount),
                                                )
                                              : L.t.membersCount(summary.memberCount),
                                          key: const Key('chat.members'),
                                          style: Theme.of(context).textTheme.bodySmall
                                              ?.copyWith(color: p.onHeaderMuted),
                                        )
                                      else if (presence.isNotEmpty)
                                        Text(
                                          presence,
                                          key: const Key('chat.presence'),
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall
                                              ?.copyWith(color: p.onHeaderMuted),
                                        )
                                      else if (summary?.peerHandle != null)
                                        Text(
                                          '@${summary!.peerHandle}',
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall
                                              ?.copyWith(color: p.onHeaderMuted),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
        // Lot 7.3a : fond choisi (motif Privio par défaut).
        body: ChatWallpaper(
          conversationId: widget.conversationId,
          child: Column(
            children: [
              if (offline)
                const Padding(
                  padding: EdgeInsets.only(top: PrivioSpacing.s),
                  child: OfflineBanner(),
                ),
              if (summary?.clearRequestBy != null && !isGroup)
                _ClearRequestBanner(summary: summary!, me: me, onRespond: _respondClear),
              // Lot 10.1 : effacement après lecture actif.
              if (summary?.readEraseSeconds case final erase? when query.isEmpty)
                _EraseBanner(
                  seconds: erase,
                  onTap: summary!.canSetReadErase ? () => _chooseReadErase(summary) : null,
                ),
              // Lot 10.4 : le contact vérifié a changé de téléphone ou de numéro.
              if (label != null && label.notice && summary != null && query.isEmpty)
                VerificationNoticeBanner(
                  label: label,
                  name: summary.title,
                  onVerify: () => openVerifyInPerson(context, summary.peerId!, summary.title),
                  onClose: () => unawaited(
                    ref.read(contactLabelsProvider.notifier).dismissNotice(label.userId),
                  ),
                ),
              // Lot 7.2c2 : messages épinglés.
              if (pins.isNotEmpty && query.isEmpty && !_selecting)
                PinnedBanner(pins: pins, index: _pinIndex, onTap: () => _openPinned(pins)),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: switch (chat) {
                        AsyncData(:final value) => _MessageList(
                          eco: ref.watch(ecoOnProvider),
                          messages: visible!,
                          unreadMarker: marker,
                          pinnedIds: pinnedIds,
                          favoriteIds: favoriteIds,
                          selectedIds: _selected,
                          onToggleSelect: _toggleSelect,
                          ghosts: [for (final g in _ghosts.values) g],
                          onGhostGone: (id) {
                            if (mounted) setState(() => _ghosts.remove(id));
                          },
                          appearing: appearing,
                          avatarOf: (id) => _avatarOf(id, summary, mentionMembers),
                          searching: query.isNotEmpty,
                          offline: offline,
                          pending: query.isEmpty ? value.pending : const [],
                          me: me,
                          now: now,
                          summary: summary,
                          onRetry: _retry,
                          onLongPress: (m) => _showActions(m, mine: m.senderId == me),
                          onSwipeReply: _startReply,
                          onSwipeDelete: _swipeDelete,
                          onDoubleTap: _quickReact,
                          onQuoteTap: (id) => unawaited(_scrollToMessage(id)),
                          scrollController: _listScroll,
                          messageKeys: _messageKeys,
                          highlightedId: _highlightedId,
                          onReactionTap: (m, emoji) {
                            ref.read(feedbackProvider).sound(PrivioSound.reaction);
                            unawaited(_guard(() => _chat.toggleReaction(m.id, emoji)));
                          },
                          onVoiceError: (f) => _toast(f.message),
                          onOpenPhoto: (m, bytes) => _openPhoto(m, bytes, summary?.title),
                          onOpenViewOnce: (m) => unawaited(_openViewOnce(m, summary?.title)),
                          onShowReactions: (m) => unawaited(
                            showReactionsSheet(
                              context,
                              reactions: m.reactions,
                              me: me,
                              who: (id) => _reactorOf(id, summary, mentionMembers),
                              onRemoveMine: (emoji) =>
                                  unawaited(_guard(() => _chat.toggleReaction(m.id, emoji))),
                            ),
                          ),
                          openingViewOnce: _openingViewOnce,
                          onOpenPerson: (m) => unawaited(
                            openPerson(
                              context,
                              ref,
                              userId: m.senderId!,
                              name: m.senderName,
                              groupId: isGroup ? widget.conversationId : null,
                            ),
                          ),
                          ttlSeconds: summary?.ttlSeconds ?? 259200,
                          peerName: summary?.title ?? L.t.votreContact,
                          onTtlTap: canSetTtl ? () => _chooseConversationTtl(summary) : null,
                          isGroup: isGroup,
                          memberNames: {for (final m in mentionMembers) m.userId: m.displayName},
                        ),
                        AsyncError(:final error) => ErrorView(
                          message: toAppFailure(error).message,
                          onRetry: () => ref.invalidate(chatProvider(widget.conversationId)),
                        ),
                        _ => const SkeletonList(bubbles: true, rows: 6),
                      },
                    ),
                    // Lot 7.2c1 : bouton « descendre », avec les nouveaux messages arrivés.
                    Positioned(
                      right: PrivioSpacing.m,
                      bottom: PrivioSpacing.m,
                      child: _ScrollDownButton(
                        visible: _awayFromBottom && query.isEmpty,
                        count: _newBelow,
                        onTap: _scrollToBottom,
                      ),
                    ),
                  ],
                ),
              ),
              if (chat case AsyncError(:final error)
                  when toAppFailure(error).code == FailureCode.notMember)
                Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.l),
                  child: NoticeBanner(
                    key: const Key('chat.not_member'),
                    message: L.t.vousNeFaitesPlusPartie,
                  ),
                )
              else if (summary?.isClosed ?? false)
                Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.l),
                  child: NoticeBanner(
                    key: const Key('chat.group_closed'),
                    message: L.t.ceGroupeEteFermePar3,
                  ),
                )
              else if (isGroup && !canPost)
                Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.l),
                  child: NoticeBanner(
                    key: const Key('chat.posting_restricted'),
                    message: summary?.announcement ?? false
                        ? L.t.annoncesComposer
                        : L.t.seulsAdministrateursPeuventEnvoyerMessages,
                  ),
                )
              else if (summary?.blocked ?? false)
                _BlockedBanner(peerId: summary?.peerId, name: summary?.title ?? '')
              else ...[
                if (_replyTo != null || _editing != null)
                  _ComposerContext(
                    label: _editing != null ? L.t.modifierMessage : L.t.repondre2,
                    text: switch ((_editing ?? _replyTo)!) {
                      ChatMessage(isVoice: true, :final durationMs) => L.t.messageVocalDurationms(
                        formatVoiceDuration(Duration(milliseconds: durationMs ?? 0)),
                      ),
                      ChatMessage(isPhoto: true, :final body) => quoteLabel('photo', body)!,
                      ChatMessage(isGif: true) => 'GIF',
                      ChatMessage(isSticker: true, :final body) => quoteLabel('sticker', body)!,
                      final m => m.body ?? '',
                    },
                    onCancel: () => setState(() {
                      if (_editing != null) _composer.clear();
                      _editing = null;
                      _replyTo = null;
                    }),
                  ),
                if (_nextTtl != null && _editing == null)
                  _ComposerContext(
                    key: const Key('composer.ttl_chip'),
                    icon: Icons.timer_outlined,
                    label: L.t.ceMessage,
                    text: formatTtl(_nextTtl!),
                    compact: true,
                    onCancel: () => setState(() => _nextTtl = null),
                  ),
                if (isGroup && _editing == null && voice is! VoiceRecording)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _composer,
                    builder: (context, value, _) {
                      final q = activeMention(value);
                      if (q == null) return const SizedBox.shrink();
                      final candidates = mentionCandidates(mentionMembers, q.query, me: me);
                      if (candidates.isEmpty) return const SizedBox.shrink();
                      return MentionSuggestions(
                        candidates: candidates,
                        onPick: (m) => _pickMention(q, m),
                      );
                    },
                  ),
                if (voice is VoicePreview)
                  VoicePreviewBar(
                    preview: voice,
                    onSend: _sendVoice,
                    onError: (f) => _toast(f.message),
                    viewOnce: _voiceOnce,
                    onViewOnce: (v) => setState(() => _voiceOnce = v),
                  )
                else
                  _Composer(
                    controller: _composer,
                    focusNode: _focus,
                    onChanged: (_) {
                      _chat.notifyTyping();
                      _onMentionInput(isGroup);
                    },
                    onTtlTap: _editing != null || voice is VoiceRecording
                        ? null
                        : () => _chooseMessageTtl(summary),
                    onPhotoTap:
                        _editing != null ||
                            voice is VoiceRecording ||
                            _preparingPhoto ||
                            !features.photo
                        ? null
                        : _pickPhoto,
                    busy: _preparingPhoto,
                    onEmojiTap: voice is VoiceRecording ? null : _togglePanel,
                    panelOpen: _panel,
                    photosLeft: ref.watch(photoQuotaProvider).value?.remaining,
                    ttlActive: _nextTtl != null,
                    strip: voice is VoiceRecording ? VoiceRecordingStrip(recording: voice) : null,
                    trailing: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _composer,
                      // Lot 7.2b2 : le micro se change en bouton d'envoi (et inversement).
                      builder: (context, value, _) => AnimatedSwitcher(
                        duration: Motion.of(context, Motion.fast),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale: Tween(begin: 0.6, end: 1.0).animate(a),
                            child: RotationTransition(
                              turns: Tween(begin: -0.08, end: 0.0).animate(a),
                              child: child,
                            ),
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_trailingKind(value, voice)),
                          child: _trailing(
                            value,
                            voice,
                            Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Lot 7.3a : émojis et autocollants, à la place du clavier.
                if (_panel && voice is! VoiceRecording)
                  ExpressionPanel(
                    controller: _composer,
                    onSticker: (s) => unawaited(_sendSticker(s)),
                    // Lot 10.3 : Mode éco → onglet GIF masqué.
                    onGif: features.gif && !ref.watch(ecoOnProvider)
                        ? (g) => unawaited(_sendGif(g))
                        : null,
                    height: _panelHeight(context),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Citation d'un message : texte, « Message vocal » ou « 📷 Photo » (avec sa légende).
String? quoteLabel(String? kind, String? preview) => switch (kind) {
  'voice' => L.t.messageVocal,
  'sticker' =>
    stickerOf(preview) == null
        ? L.t.stickerNoLabel
        : L.t.stickerWithLabel(stickerOf(preview)!.label),
  'photo' => preview == null || preview.isEmpty ? L.t.photo2 : '📷 $preview',
  'gif' => 'GIF',
  _ => preview,
};

/// Libellé du séparateur de jour : « Aujourd'hui », « Hier », sinon la date.
String dayLabel(DateTime at, DateTime now) {
  final a = at.toLocal();
  final n = now.toLocal();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(a.year, a.month, a.day)).inDays;
  if (days == 0) return L.t.aujourdHui;
  if (days == 1) return L.t.hier;
  return toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr').format(a));
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    this.eco = false,
    this.pinnedIds = const {},
    this.favoriteIds = const {},
    this.selectedIds = const {},
    this.onToggleSelect,
    required this.onSwipeReply,
    required this.onSwipeDelete,
    required this.onDoubleTap,
    required this.onQuoteTap,
    required this.scrollController,
    required this.messageKeys,
    required this.messages,
    required this.pending,
    required this.me,
    required this.now,
    required this.summary,
    required this.onRetry,
    required this.onLongPress,
    required this.onReactionTap,
    required this.ttlSeconds,
    required this.peerName,
    required this.onTtlTap,
    required this.onVoiceError,
    required this.onOpenPhoto,
    this.searching = false,
    this.offline = false,
    this.isGroup = false,
    this.highlightedId,
    this.memberNames = const {},
    this.ghosts = const [],
    this.onGhostGone,
    this.appearing = const {},
    this.avatarOf,
    this.unreadMarker,
    this.onOpenViewOnce,
    this.openingViewOnce,
    this.onOpenPerson,
    this.onShowReactions,
  });

  /// Lot 8.1b : liste des réactions d'un message.
  final void Function(ChatMessage m)? onShowReactions;

  /// Lot 8.1a : toucher le nom ou la photo de l'auteur ouvre sa carte.
  final void Function(ChatMessage m)? onOpenPerson;

  /// Lot 7.3b : ouvrir une photo ou un vocal reçu en vue unique.
  final void Function(ChatMessage m)? onOpenViewOnce;
  final String? openingViewOnce;

  /// Lot 7.2c1 : premier message non lu à l'ouverture, et nombre de non lus.
  final (String, int)? unreadMarker;

  /// Lot 7.2c2 : messages épinglés, favoris, sélectionnés (sélection multiple).
  final Set<String> pinnedIds;
  final Set<String> favoriteIds;
  final Set<String> selectedIds;
  final void Function(ChatMessage m)? onToggleSelect;

  final bool isGroup;

  /// Noms des membres (identifiant → nom) pour mettre en valeur les @mentions.
  final Map<String, String> memberNames;

  /// Lot 7.2b2 : messages qui viennent de disparaître (expirés, vidés, supprimés chez
  /// moi), affichés le temps de leur dissolution ; avec leur ordre dans la cascade.
  final List<(ChatMessage, int)> ghosts;
  final void Function(String id)? onGhostGone;

  /// Messages reçus à l'instant : ils apparaissent en fondu.
  final Set<String> appearing;

  /// Photo de l'auteur d'un message reçu (null : pas de photo à côté des messages).
  final ({String name, String? path, String seed})? Function(String senderId)? avatarOf;
  final ScrollController scrollController;

  /// Une clé par message, gardée par l'écran (les clés « objet » comparent l'identité,
  /// pas le texte : une chaîne recréée ne retrouverait jamais le message).
  final Map<String, GlobalKey> messageKeys;
  final String? highlightedId;
  final void Function(AppFailure failure) onVoiceError;
  final void Function(ChatMessage message, Uint8List bytes) onOpenPhoto;
  final bool searching;
  final bool offline;

  final int ttlSeconds;
  final String peerName;
  final VoidCallback? onTtlTap;
  final List<ChatMessage> messages;
  final List<PendingMessage> pending;
  final String? me;
  final DateTime now;
  final ConversationSummary? summary;
  final void Function(PendingMessage) onRetry;
  final void Function(ChatMessage) onLongPress;
  final void Function(ChatMessage) onSwipeReply;
  final void Function(ChatMessage) onSwipeDelete;
  final void Function(ChatMessage) onDoubleTap;
  final void Function(String messageId) onQuoteTap;
  final void Function(ChatMessage, String) onReactionTap;

  /// Lot 10.3 : Mode éco (aperçus des liens masqués).
  final bool eco;

  @override
  Widget build(BuildContext context) {
    if (searching && messages.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: L.t.aucunMessageNeCorrespond,
        message: L.t.recherchePorteSurMessagesEncore,
      );
    }
    if (messages.isEmpty && pending.isEmpty && ghosts.isEmpty) {
      return EmptyView(
        icon: Icons.timer_outlined,
        title: L.t.aucunMessage,
        message: L.t.vosMessagesEffacerontTtlsecondsApres(formatTtl(ttlSeconds)),
      );
    }
    final items = <Widget>[];
    String? lastDay;
    final error = Theme.of(context).colorScheme.error;
    // Lot 7.2b2 : les messages en train de disparaître restent à leur place le temps de
    // se dissoudre.
    final ghostOrder = {for (final (g, i) in ghosts) g.id: i};
    final entries = [...messages, for (final (g, _) in ghosts) g]
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    for (final (index, m) in entries.indexed) {
      final ghost = ghostOrder[m.id];
      final day = dayLabel(m.sentAt, now);
      if (day != lastDay) {
        items.add(_DayChip(label: day));
        lastDay = day;
      }
      if (unreadMarker case (final id, final n) when id == m.id && ghost == null) {
        items.add(_UnreadDivider(count: n));
      }
      if (m.isSystem) {
        if (ghost != null) continue;
        final ttl = m.systemTtlSeconds;
        final erase = m.systemEraseSeconds;
        if (erase != null) {
          final who = m.senderId == me ? L.t.vousAvez : '${m.senderName ?? peerName} a';
          items.add(
            _SystemNotice(
              key: Key('system.${m.id}'),
              text: erase == 0
                  ? L.t.systemEraseOff(who)
                  : L.t.systemEraseOn(who, formatErase(erase)),
              icon: Icons.local_fire_department_outlined,
            ),
          );
        } else if (ttl != null) {
          final who = m.senderId == me ? L.t.vousAvez : '${m.senderName ?? peerName} a';
          items.add(
            _SystemNotice(
              key: Key('system.${m.id}'),
              text: L.t.whoRegleDureeMessagesSur(who, formatTtl(ttl)),
            ),
          );
        } else if (groupEventText(m, me: me) case final text?) {
          items.add(
            _SystemNotice(key: Key('system.${m.id}'), text: text, icon: Icons.groups_outlined),
          );
        }
        continue;
      }
      final outgoing = m.senderId == me;
      // Lot 8.1b : photo de l’auteur à côté du premier message de sa suite.
      final prev = index > 0 ? entries[index - 1] : null;
      // Dans un groupe, le nom de l'auteur en tête de sa suite seulement.
      final firstOfRun =
          prev == null ||
          prev.isSystem ||
          prev.senderId != m.senderId ||
          dayLabel(prev.sentAt, now) != day;
      final who = outgoing || avatarOf == null ? null : avatarOf!(m.senderId ?? '');
      final bubble = _Bubble(
        key: ghost == null ? Key('message.${m.id}') : null,
        // Pas de double appui sur un vocal : il retarderait de 300 ms ses boutons
        // (lecture, vitesse) ; on y réagit par l'appui long.
        onDoubleTap: ghost != null || m.isDeleted || m.hasPlayableVoice
            ? null
            : () => onDoubleTap(m),
        onQuoteTap: m.replyToId == null ? null : () => onQuoteTap(m.replyToId!),
        outgoing: outgoing,
        sender: isGroup && !outgoing && firstOfRun ? (m.senderName ?? L.t.ancienMembre) : null,
        onSenderTap: ghost == null && m.senderId != null && onOpenPerson != null
            ? () => onOpenPerson!(m)
            : null,
        text: m.isDeleted ? L.t.messageSupprime : (m.body ?? ''),
        mentions: {for (final id in m.mentions) ?memberNames[id]: id == me},
        // Lot 7.3a : autocollant, ou grands émojis.
        bare:
            !m.isDeleted && (m.isSticker || m.isGif || (m.kind == 'text' && isJumboEmoji(m.body))),
        jumbo: !m.isDeleted && m.kind == 'text' && m.mentions.isEmpty && isJumboEmoji(m.body),
        // Lot 7.3b : aperçu du lien au-dessus du texte.
        // Lot 10.3 : Mode éco → pas d'aperçu (le lien reste cliquable dans le texte).
        attachment: m.linkPreview != null && !m.isDeleted && !eco
            ? LinkPreviewCard(preview: m.linkPreview!, outgoing: outgoing)
            : null,
        content: m.isPoll && !m.isDeleted && summary != null
            ? PollContent(
                message: m,
                conversationId: summary!.id,
                outgoing: outgoing,
                nameOf: (id) {
                  if (id == me) return L.t.vous;
                  final w = avatarOf?.call(id);
                  return w != null && w.name != '?'
                      ? w.name
                      : (memberNames[id] ?? L.t.ancienMembre);
                },
              )
            : m.isSticker && !m.isDeleted
            ? StickerImage(id: m.body, size: 140)
            : m.viewOnce && !m.isDeleted
            ? ViewOnceContent(
                message: m,
                outgoing: outgoing,
                isGroup: isGroup,
                opening: openingViewOnce == m.id,
                onOpen: ghost == null && onOpenViewOnce != null ? () => onOpenViewOnce!(m) : null,
              )
            : m.isGif && !m.isDeleted
            ? GifImage(message: m)
            : m.hasPlayableVoice
            ? VoiceMessageContent(message: m, outgoing: outgoing, onError: onVoiceError)
            : m.hasViewablePhoto
            ? PhotoMessageContent(
                photo: PhotoRef.message(m),
                width: m.width,
                height: m.height,
                outgoing: outgoing,
                caption: m.body,
                onOpen: (bytes) => onOpenPhoto(m, bytes),
              )
            : null,
        italic: m.isDeleted,
        quote: m.isDeleted ? null : quoteLabel(m.replyKind, m.replyPreview),
        time: DateFormat.Hm('fr').format(m.sentAt.toLocal()),
        edited: m.editedAt != null && !m.isDeleted,
        remaining: formatRemaining(m.expiresAt, now: now),
        erase: m.readEraseSeconds != null && !m.isDeleted,
        // Lot 8.4b : 4 h avant l'effacement d'un message de 12 h ou plus.
        expiringSoon: expiringSoon(m.sentAt, m.expiresAt, now: now) && !m.isDeleted,
        delivery: outgoing && !m.isDeleted ? deliveryOf(m, summary) : null,
        reactions: m.reactions,
        me: me,
        onLongPress: ghost == null ? () => onLongPress(m) : null,
        pinned: pinnedIds.contains(m.id),
        favorite: favoriteIds.contains(m.id),
        onReactionTap: ghost == null ? (emoji) => onReactionTap(m, emoji) : null,
        onShowReactions: ghost == null && onShowReactions != null
            ? () => onShowReactions!(m)
            : null,
        tail: firstOfRun,
        avatar: who == null
            ? null
            : (firstOfRun
                  ? GestureDetector(
                      onTap: ghost == null && m.senderId != null && onOpenPerson != null
                          ? () => onOpenPerson!(m)
                          : null,
                      child: Semantics(
                        button: true,
                        label: L.t.voirName(who.name),
                        child: UserAvatar(
                          key: Key('message.avatar.${m.id}'),
                          name: who.name,
                          avatarPath: who.path,
                          seed: who.seed,
                          radius: 14,
                        ),
                      ),
                    )
                  : const SizedBox.shrink()),
      );
      if (ghost != null) {
        items.add(
          IgnorePointer(
            key: ValueKey('ghost.${m.id}'),
            child: DissolveOut(
              // Discussion vidée : cascade du plus récent au plus ancien.
              delay: Duration(milliseconds: 45 * ghost),
              onDone: () => onGhostGone?.call(m.id),
              child: bubble,
            ),
          ),
        );
        continue;
      }
      items.add(
        AnimatedContainer(
          key: messageKeys.putIfAbsent(m.id, GlobalKey.new),
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: m.id == highlightedId || selectedIds.contains(m.id)
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          // Lot 7.2c2 : en sélection, toucher un message le coche ou le décoche.
          child: selectedIds.isNotEmpty
              ? Semantics(
                  selected: selectedIds.contains(m.id),
                  child: GestureDetector(
                    key: Key('select.${m.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onToggleSelect?.call(m),
                    onLongPress: () => onToggleSelect?.call(m),
                    child: AbsorbPointer(child: bubble),
                  ),
                )
              : SwipeActions(
                  right: m.isDeleted
                      ? null
                      : SwipeAction(
                          icon: Icons.reply,
                          label: L.t.repondre,
                          onTriggered: () => onSwipeReply(m),
                        ),
                  left: SwipeAction(
                    icon: Icons.delete_outline,
                    label: L.t.supprimer,
                    color: error,
                    onTriggered: () => onSwipeDelete(m),
                  ),
                  // Lot 7.2b2 : message reçu à l'instant (fondu) ; supprimé pour tout le monde
                  // (la bulle se froisse).
                  child: AppearIn(
                    animate: appearing.contains(m.id),
                    offset: const Offset(-0.04, 0.1),
                    scale: 0.96,
                    child: CrumpleSwitch(deleted: m.isDeleted, child: bubble),
                  ),
                ),
        ),
      );
    }
    // Lot 8.1b : le premier envoi en attente porte la queue si le dernier message
    // affiché n'est pas de moi.
    final lastShown = entries.where((e) => !e.isSystem).lastOrNull;
    for (final (pi, pm) in pending.indexed) {
      final pendingTail = pi == 0 && (lastShown == null || lastShown.senderId != me);
      items.add(
        // Lot 7.2b2 : la bulle monte depuis la zone de saisie.
        AppearIn(
          key: ValueKey('pending-in.${pm.clientId}'),
          offset: const Offset(0.05, 0.6),
          child: _Bubble(
            key: Key('pending.${pm.clientId}'),
            outgoing: true,
            tail: pendingTail,
            text: pm.body,
            bare: pm.isSticker || pm.isGif,
            content: pm.isSticker
                ? StickerImage(id: pm.body, size: 140)
                : pm.viewOnce
                ? PendingViewOnceContent(voice: pm.isVoice)
                : pm.isGif
                ? const PendingGifContent()
                : pm.isVoice
                ? PendingVoiceContent(durationMs: pm.durationMs)
                : pm.isPhoto
                ? PhotoMessageContent(
                    photo: PhotoRef.pending(pm.clientId),
                    width: pm.width,
                    height: pm.height,
                    outgoing: true,
                    caption: pm.body,
                  )
                : null,
            status: pm.failed
                ? L.t.nonEnvoyeToucherPourReessayer
                : (offline ? L.t.attenteReseau : L.t.envoi),
            failed: pm.failed,
            onTap: () => onRetry(pm),
          ),
        ),
      );
    }
    // Lot 4.6 : une ligne discrète tout en haut de la discussion (au lieu d'une carte en bas).
    if (!searching) {
      items.insert(0, _ExpiryNotice(ttlSeconds: ttlSeconds, onTap: onTtlTap));
    }
    return ListView(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.m,
        PrivioSpacing.s,
        PrivioSpacing.m,
        PrivioSpacing.s,
      ),
      children: items.reversed.toList(),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: p.notice, borderRadius: BorderRadius.circular(14)),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

/// Rappel de la durée de vie (lot 4.6) : une ligne discrète en haut de la discussion,
/// comme le séparateur des jours ; touchable pour la régler quand c'est permis.
class _ExpiryNotice extends StatelessWidget {
  const _ExpiryNotice({required this.ttlSeconds, required this.onTap});

  final int ttlSeconds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
        child: Material(
          color: p.notice,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const Key('chat.expiry_notice'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: color),
                  const SizedBox(width: PrivioSpacing.xs),
                  Flexible(
                    child: Text(
                      L.t.messagesEffacesApresTtlseconds(formatTtl(ttlSeconds)),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lot 10.1 : délai d'effacement après lecture, en toutes lettres.
String formatErase(int seconds) => switch (seconds) {
  30 => L.t.erase30s,
  300 => L.t.erase5min,
  3600 => L.t.erase1h,
  _ => formatTtl(seconds),
};

/// Lot 10.1 : bandeau « Effacement après lecture : 5 minutes » sous l'en-tête.
class _EraseBanner extends StatelessWidget {
  const _EraseBanner({required this.seconds, this.onTap});

  final int seconds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, PrivioSpacing.s, PrivioSpacing.l, 0),
      child: Material(
        color: MenuTint.pink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
        child: InkWell(
          key: const Key('chat.erase_banner'),
          borderRadius: BorderRadius.circular(PrivioRadius.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.m, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, size: 18, color: MenuTint.pink),
                const SizedBox(width: PrivioSpacing.s),
                Expanded(
                  child: Text(
                    L.t.eraseBanner(formatErase(seconds)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.accentText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null) Icon(Icons.tune_rounded, size: 16, color: p.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lot 10.1 : choix du délai (0 : désactivé).
class _ReadEraseSheet extends StatelessWidget {
  const _ReadEraseSheet({required this.current, required this.isGroup});

  final int? current;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(int value, String label, IconData icon) {
      final selected = (current ?? 0) == value;
      return ListTile(
        key: Key('erase.option.$value'),
        leading: Icon(icon, color: selected ? MenuTint.pink : null),
        title: Text(label),
        trailing: selected ? const Icon(Icons.check_rounded, color: MenuTint.pink) : null,
        selected: selected,
        onTap: () => Navigator.of(context).pop(value),
      );
    }

    return SafeArea(
      child: Column(
        key: const Key('erase.sheet'),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t.effacerApresLecture, style: theme.textTheme.titleLarge),
                const SizedBox(height: PrivioSpacing.xs),
                Text(L.t.effacerApresLectureAide, style: theme.textTheme.bodySmall),
                if (isGroup) ...[
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(L.t.effacerApresLectureGroupeAdmins, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          option(0, L.t.eraseOff, Icons.block_outlined),
          option(30, L.t.erase30s, Icons.local_fire_department_outlined),
          option(300, L.t.erase5min, Icons.local_fire_department_outlined),
          option(3600, L.t.erase1h, Icons.local_fire_department_outlined),
          const SizedBox(height: PrivioSpacing.s),
        ],
      ),
    );
  }
}

/// Durée des messages dans l'en-tête (lot 4.6) : « ⏱ 24 h », touchable pour la régler.
class _TtlPill extends StatelessWidget {
  const _TtlPill({required this.ttlSeconds, required this.onTap});

  final int ttlSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onPrimary;
    final label = formatTtl(ttlSeconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xs),
      child: Tooltip(
        message: L.t.dureeMessagesLabel(label),
        child: Semantics(
          button: true,
          label: L.t.dureeMessagesLabel(label),
          excludeSemantics: true,
          child: Material(
            color: fg.withValues(alpha: 0.16),
            shape: const StadiumBorder(),
            child: InkWell(
              key: const Key('chat.ttl'),
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: fg),
                      const SizedBox(width: PrivioSpacing.xs),
                      Text(
                        label,
                        // Étiquette courte à taille fixe : laisse la place au nom (écran étroit).
                        textScaler: TextScaler.noScaling,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({super.key, required this.text, this.icon = Icons.timer_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(color: p.notice, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: p.accentText),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle à la largeur de son contenu le plus large (utile quand une ligne s'aligne à gauche).
class _FitWidth extends StatelessWidget {
  const _FitWidth({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled ? IntrinsicWidth(child: child) : child;
}

/// Taille des informations hors message (heure, minuterie, « modifié ») : plus petite
/// et plus discrète que le texte (contraste ≥ 4,5:1 vérifié par les tests).
const double kBubbleMetaSize = 11;

class _Bubble extends StatelessWidget {
  const _Bubble({
    this.onDoubleTap,
    this.onQuoteTap,
    super.key,
    required this.outgoing,
    required this.text,
    this.sender,
    this.content,
    this.time,
    this.edited = false,
    this.remaining,
    this.expiringSoon = false,
    this.erase = false,
    this.status,
    this.italic = false,
    this.failed = false,
    this.quote,
    this.delivery,
    this.reactions = const [],
    this.me,
    this.onTap,
    this.onLongPress,
    this.onReactionTap,
    this.mentions = const {},
    this.avatar,
    this.pinned = false,
    this.favorite = false,
    this.bare = false,
    this.jumbo = false,
    this.attachment,
    this.onSenderTap,
    this.tail = false,
    this.onShowReactions,
  });

  /// Lot 8.1b : premier message d'une suite (queue en haut, du côté de l'auteur).
  final bool tail;

  /// Lot 8.1b : appui simple sur une réaction : la liste des réactions.
  final VoidCallback? onShowReactions;

  /// Lot 8.1a : toucher le nom de l'auteur (groupe) ouvre sa carte.
  final VoidCallback? onSenderTap;

  /// Lot 7.3b : aperçu d'un lien, au-dessus du texte.
  final Widget? attachment;

  /// Lot 7.3a : autocollant ou grands émojis : sans fond de bulle (heure dans une pastille).
  final bool bare;

  /// Lot 7.3a : 1 à 3 émojis seuls, affichés en grand.
  final bool jumbo;

  final bool outgoing;
  final String text;

  /// Lot 7.2c2 : petites icônes à côté de l'heure.
  final bool pinned;
  final bool favorite;

  /// Lot 7.2b2 : photo de l'auteur à gauche d'un message reçu (vide : place gardée pour
  /// aligner les messages d'une même suite) ; null : pas de colonne de photo.
  final Widget? avatar;

  /// Lot 7.1b : noms mentionnés dans [text] (vrai : c'est moi).
  final Map<String, bool> mentions;

  /// Nom de l'auteur, affiché en tête des messages reçus dans un groupe.
  final String? sender;

  /// Contenu autre que du texte (vocal) ; remplace [text] s'il est fourni.
  final Widget? content;
  final String? time;
  final bool edited;
  final String? remaining;

  /// Lot 8.4b : s'efface bientôt (compte à rebours mis en valeur).
  final bool expiringSoon;

  /// Lot 10.1 : effacé après lecture (petite flamme à côté de l'heure).
  final bool erase;
  final String? status;
  final bool italic;
  final bool failed;
  final String? quote;
  final Delivery? delivery;
  final List<Reaction> reactions;
  final String? me;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onQuoteTap;
  final void Function(String emoji)? onReactionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final bg = outgoing ? p.bubbleOut : p.bubbleIn;
    final fg = outgoing ? p.onBubbleOut : p.onBubbleIn;
    final meta = outgoing && !bare ? p.bubbleOutMeta : p.bubbleInMeta;
    // Lot 8.4b : sur le violet, le jaune des coches « lu » ; ailleurs, la couleur d'alerte.
    final soonColor = outgoing && !bare
        ? PrivioColors.readTick
        : theme.brightness == Brightness.dark
        ? PrivioColors.errorDark
        : PrivioColors.error;
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: kBubbleMetaSize,
      fontWeight: FontWeight.w400,
      height: 1.2,
      color: failed ? theme.colorScheme.error : meta,
    );
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final mine = reactions.where((r) => r.userId == me).firstOrNull?.emoji;
    // Lot 8.1b : arrondis de 10, queue en haut du premier message d'une suite.
    final shape = BubbleShape(
      outgoing: outgoing,
      tail: tail && !bare,
      side: failed ? BorderSide(color: theme.colorScheme.error, width: 1.5) : BorderSide.none,
    );
    const tw = BubbleShape.tailWidth;

    final bubble = Material(
      key: tail && !bare ? const Key('bubble.tail') : null,
      color: bare ? Colors.transparent : bg,
      elevation: bare || outgoing || theme.brightness == Brightness.dark ? 0 : 0.5,
      shadowColor: PrivioColors.navy.withValues(alpha: 0.3),
      shape: shape,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        customBorder: shape,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12 + (outgoing ? 0 : tw), 7, 10 + (outgoing ? tw : 0), 5),
          // Une bulle = une annonce TalkBack complète (texte, heure, état).
          child: MergeSemantics(
            // Groupe : le nom de l'auteur reste à gauche sans élargir la bulle.
            child: _FitWidth(
              enabled: sender != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (sender != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: GestureDetector(
                          onTap: onSenderTap,
                          child: Text(
                            sender!,
                            key: const Key('bubble.sender'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: p.accentText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (quote != null)
                    GestureDetector(
                      onTap: onQuoteTap,
                      child: Container(
                        key: const Key('bubble.quote'),
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: outgoing ? p.quoteOut : p.quoteIn,
                          borderRadius: BorderRadius.circular(PrivioRadius.small + 2),
                        ),
                        child: Text(
                          quote!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: meta),
                        ),
                      ),
                    ),
                  ?attachment,
                  Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child:
                        content ??
                        // Lot 8.5b : 1 à 3 émojis seuls → grands et animés.
                        (jumbo
                            ? BigEmojisText(text)
                            : mentions.isEmpty
                            ? Text(
                                text,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: fg,
                                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                                ),
                              )
                            : Text.rich(
                                key: const Key('bubble.mentions'),
                                mentionSpan(
                                  text,
                                  names: mentions,
                                  style: theme.textTheme.bodyLarge?.copyWith(color: fg),
                                  mention: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: outgoing ? fg : p.accentText,
                                  ),
                                  mine: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: outgoing ? fg : p.accentText,
                                    backgroundColor: (outgoing ? fg : p.accentText).withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                ),
                              )),
                  ),
                  const SizedBox(height: 2),
                  if (status != null)
                    _MetaPill(
                      bare: bare,
                      child: Text(status!, style: metaStyle),
                    )
                  else
                    _MetaPill(
                      bare: bare,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Lot 7.2c2 : épinglé, favori.
                          if (pinned) ...[
                            Icon(
                              Icons.push_pin_rounded,
                              key: const Key('bubble.pinned'),
                              size: 11,
                              color: meta,
                              semanticLabel: L.t.epingle,
                            ),
                            const SizedBox(width: 3),
                          ],
                          if (favorite) ...[
                            Icon(
                              Icons.star_rounded,
                              key: const Key('bubble.favorite'),
                              size: 12,
                              color: meta,
                              semanticLabel: L.t.semFavorite,
                            ),
                            const SizedBox(width: 3),
                          ],
                          if (erase) ...[
                            Icon(
                              Icons.local_fire_department_rounded,
                              key: const Key('bubble.erase'),
                              size: 12,
                              color: meta,
                              semanticLabel: L.t.bubbleErase,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Text('${time ?? ''}${edited ? L.t.editedSuffix : ''}', style: metaStyle),
                          if (remaining != null) ...[
                            const SizedBox(width: 5),
                            if (expiringSoon) ...[
                              Icon(
                                Icons.hourglass_bottom_rounded,
                                key: const Key('bubble.soon'),
                                size: 12,
                                color: soonColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                remaining!,
                                semanticsLabel: L.t.bubbleSoon(remaining!),
                                style: metaStyle?.copyWith(
                                  color: soonColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ] else ...[
                              Icon(Icons.timer_outlined, size: 11, color: meta),
                              const SizedBox(width: 2),
                              Text(
                                remaining!,
                                semanticsLabel: L.t.expireDansRemaining(remaining!),
                                style: metaStyle,
                              ),
                            ],
                          ],
                          if (delivery != null) ...[
                            const SizedBox(width: 4),
                            _DeliveryIcon(
                              delivery: delivery!,
                              color: meta,
                              // Lot 8.1b : « lu » en jaune doux sur le violet.
                              readColor: outgoing && !bare ? PrivioColors.readTick : p.accentText,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final body = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8 - (avatar == null ? 0 : 34),
      ),
      child: Padding(
        // Réaction présente : sa place est réservée DANS la zone de la bulle (sinon
        // elle serait visible mais impossible à toucher) ; elle ne recouvre ni le
        // texte, ni le message suivant.
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: counts.isEmpty
            ? bubble
            : Stack(
                children: [
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: bubble),
                  Positioned(
                    bottom: 0,
                    left: outgoing ? 10 : null,
                    right: outgoing ? null : 10 + BubbleShape.tailWidth,
                    child: _ReactionPill(
                      counts: counts,
                      mine: mine,
                      onDoubleTap: onReactionTap,
                      onTap: onShowReactions,
                    ),
                  ),
                ],
              ),
      ),
    );
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: avatar == null
          ? body
          // Lot 8.1b : photo en haut à gauche, à côté de la queue de la bulle.
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SizedBox(width: 28, child: avatar),
                ),
                const SizedBox(width: 2),
                Flexible(child: body),
              ],
            ),
    );
  }
}

/// Réactions : petite pastille sans contour, accrochée au coin inférieur de la bulle.
/// La réaction de l'utilisateur est signalée par un fond teinté (pas par un contour).
class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.counts,
    required this.mine,
    required this.onTap,
    required this.onDoubleTap,
  });

  final Map<String, int> counts;
  final String? mine;

  /// Lot 8.1b : appui simple : qui a réagi ; double appui : ajouter / retirer la mienne.
  final VoidCallback? onTap;
  final void Function(String emoji)? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in counts.entries)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            // Lot 7.2b2 : la réaction « pop » quand elle apparaît ou change de nombre.
            child: PopOnChange(
              value: '${e.key}${e.value}',
              child: Semantics(
                button: true,
                label: L.t.reactionKeyVoirQuiReagi(e.key),
                onTapHint: L.t.voirQuiReagi,
                customSemanticsActions: onDoubleTap == null
                    ? null
                    : {
                        CustomSemanticsAction(
                          label: e.key == mine ? L.t.retirerMaReaction : L.t.reagirKey(e.key),
                        ): () =>
                            onDoubleTap!(e.key),
                      },
                child: GestureDetector(
                  key: Key('reaction.${e.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap!(e.key),
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.key == mine
                          ? Color.alphaBlend(p.accentText.withValues(alpha: 0.18), p.sheet)
                          : (dark ? p.field : p.sheet),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: PrivioColors.navy.withValues(alpha: dark ? 0.4 : 0.14),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        e.value > 1 ? '${e.key} ${e.value}' : e.key,
                        style: const TextStyle(fontSize: 12, height: 1.1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.delivery, required this.color, required this.readColor});

  final Delivery delivery;
  final Color color;
  final Color readColor;

  @override
  Widget build(BuildContext context) {
    final (icon, label, tint) = switch (delivery) {
      Delivery.sent => (Icons.done, L.t.envoye, color),
      Delivery.delivered => (Icons.done_all, L.t.recu, color),
      Delivery.read => (Icons.done_all, L.t.lu, readColor),
    };
    // Lot 7.2b2 : les coches se dessinent quand l'état change.
    return Semantics(
      label: label,
      child: AnimatedTicks(
        key: Key('delivery.${delivery.name}'),
        twice: icon == Icons.done_all,
        color: tint,
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    super.key,
    required this.label,
    required this.text,
    required this.onCancel,
    this.icon = Icons.reply,
    this.compact = false,
  });

  final String label;
  final String text;
  final VoidCallback onCancel;
  final IconData icon;

  /// Une seule ligne (lot 4.6) : « ⏱ Ce message : 30 min ✕ ».
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.xs, PrivioSpacing.m, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            backgroundColor: p.notice,
            side: BorderSide.none,
            avatar: Icon(icon, size: 16, color: p.accentText),
            label: Text(L.t.labelColonText(label, text)),
            onDeleted: onCancel,
            deleteButtonTooltipMessage: L.t.annuler,
            deleteIcon: const Icon(Icons.close, size: 16, key: Key('composer.ttl_cancel')),
          ),
        ),
      );
    }
    return Container(
      key: key == null ? const Key('composer.context') : null,
      margin: const EdgeInsets.fromLTRB(PrivioSpacing.m, PrivioSpacing.xs, PrivioSpacing.m, 0),
      padding: const EdgeInsets.only(left: PrivioSpacing.m),
      decoration: BoxDecoration(
        color: p.notice,
        borderRadius: BorderRadius.circular(PrivioRadius.medium),
      ),
      child: Row(
        children: [
          Icon(icon, color: p.accentText),
          const SizedBox(width: PrivioSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: p.accentText)),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key(key == null ? 'composer.cancel' : 'composer.ttl_cancel'),
            tooltip: L.t.annuler,
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Zone de saisie : durée du prochain message, champ arrondi avec bouton photo (ou
/// bandeau d'enregistrement), bouton de droite (envoyer, micro ou arrêter). Les emojis
/// apparaîtront avec leur lot (aucun bouton non livré n'est affiché).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.trailing,
    this.strip,
    this.onTtlTap,
    this.onPhotoTap,
    this.busy = false,
    this.photosLeft,
    this.ttlActive = false,
    this.onChanged,
    this.onEmojiTap,
    this.panelOpen = false,
  });

  /// Lot 7.3a : bouton émojis / autocollants (ou clavier quand le panneau est ouvert).
  final VoidCallback? onEmojiTap;
  final bool panelOpen;

  /// Bouton photo (absent pendant une modification ou un enregistrement).
  final VoidCallback? onPhotoTap;

  /// Photos restantes aujourd'hui (null : inconnu). À 0, l'icône est atténuée (lot 4.4).
  final int? photosLeft;

  /// Photo en préparation : petit indicateur à la place du bouton.
  final bool busy;

  final ValueChanged<String>? onChanged;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget trailing;

  /// Bandeau affiché à la place du champ (enregistrement en cours).
  final Widget? strip;
  final VoidCallback? onTtlTap;
  final bool ttlActive;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.s,
          PrivioSpacing.xs,
          PrivioSpacing.s,
          PrivioSpacing.m,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark ? p.field : p.sheet,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: dark
                      ? null
                      : [
                          BoxShadow(
                            color: PrivioColors.navy.withValues(alpha: 0.12),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: strip != null
                    ? SizedBox(height: 52, child: strip)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (onTtlTap != null)
                            IconButton(
                              key: const Key('composer.ttl'),
                              tooltip: L.t.dureeCeMessage,
                              isSelected: ttlActive,
                              onPressed: onTtlTap,
                              icon: Icon(
                                Icons.timer_outlined,
                                color: ttlActive
                                    ? p.accentText
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Expanded(
                            child: TextField(
                              key: const Key('chat.input'),
                              controller: controller,
                              onChanged: onChanged,
                              focusNode: focusNode,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 4000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: L.t.ecrireMessage,
                                counterText: '',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  onTtlTap == null ? 20 : 4,
                                  14,
                                  onPhotoTap == null && !busy && onEmojiTap == null ? 20 : 4,
                                  14,
                                ),
                              ),
                            ),
                          ),
                          if (onEmojiTap != null)
                            IconButton(
                              key: const Key('composer.emoji'),
                              tooltip: panelOpen ? L.t.clavier : L.t.emojisAutocollants,
                              onPressed: onEmojiTap,
                              icon: Icon(
                                panelOpen
                                    ? Icons.keyboard_alt_outlined
                                    : Icons.emoji_emotions_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (busy)
                            const Padding(
                              key: Key('composer.photo_busy'),
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else if (onPhotoTap != null)
                            IconButton(
                              key: const Key('composer.photo'),
                              tooltip: photosLeft == 0
                                  ? L.t.plusPhotosAujourdHui
                                  : L.t.envoyerPhoto,
                              onPressed: onPhotoTap,
                              icon: Badge(
                                key: const Key('composer.photo_none'),
                                isLabelVisible: photosLeft == 0,
                                label: const Text('0'),
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(
                                    alpha: photosLeft == 0 ? 0.38 : 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.s),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Demande « vider pour nous deux » en cours (lot 4.3).
class _ClearRequestBanner extends StatelessWidget {
  const _ClearRequestBanner({required this.summary, required this.me, required this.onRespond});

  final ConversationSummary summary;
  final String? me;

  /// true : accepter ; false : refuser ; null : annuler sa propre demande.
  final void Function(bool? accept) onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final mine = summary.clearRequestBy == me;
    final delete = summary.clearRequestDelete;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('clear.banner'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(PrivioSpacing.l, PrivioSpacing.s, PrivioSpacing.l, 0),
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.m,
          PrivioSpacing.s,
          PrivioSpacing.s,
          PrivioSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: p.notice,
          borderRadius: BorderRadius.circular(PrivioRadius.medium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  delete ? Icons.delete_outline : Icons.cleaning_services_outlined,
                  size: 18,
                  color: p.accentText,
                ),
                const SizedBox(width: PrivioSpacing.s),
                Expanded(
                  // Lot 7.2b1 : la demande peut être une suppression de la discussion.
                  child: Text(
                    mine
                        ? (delete
                              ? L.t.deleteRequestSent(summary.title)
                              : L.t.clearRequestSent(summary.title))
                        : delete
                        ? L.t.titleProposeSupprimerDiscussionPour(summary.title)
                        : L.t.titleProposeViderTouteDiscussion(summary.title),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: mine
                  ? [
                      TextButton(
                        key: const Key('clear.cancel'),
                        onPressed: () => onRespond(null),
                        child: Text(L.t.annulerDemande),
                      ),
                    ]
                  : [
                      TextButton(
                        key: const Key('clear.refuse'),
                        onPressed: () => onRespond(false),
                        child: Text(L.t.refuser),
                      ),
                      FilledButton(
                        key: const Key('clear.accept'),
                        onPressed: () => onRespond(true),
                        child: Text(delete ? L.t.accepterSupprimer : L.t.accepterVider),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau de blocage (lot 4.4) : une phrase, et « Débloquer » quand c'est vous qui avez bloqué.
class _BlockedBanner extends ConsumerStatefulWidget {
  const _BlockedBanner({required this.peerId, required this.name});

  final String? peerId;
  final String name;

  @override
  ConsumerState<_BlockedBanner> createState() => _BlockedBannerState();
}

class _BlockedBannerState extends ConsumerState<_BlockedBanner> {
  bool _busy = false;

  Future<void> _unblock(String peerId) async {
    setState(() => _busy = true);
    try {
      await setBlocked(ref, peerId, blocked: false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L.t.nameEstDebloque(widget.name))));
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerId = widget.peerId;
    final iBlocked =
        peerId != null &&
        (ref.watch(blockedUsersProvider).value?.any((b) => b.id == peerId) ?? false);
    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.l),
      child: NoticeBanner(
        key: const Key('chat.blocked'),
        message: iBlocked ? L.t.vousAvezBloqueName(widget.name) : L.t.vousNePouvezPlusVous,
        actionLabel: iBlocked ? L.t.debloquer : null,
        onAction: iBlocked && !_busy ? () => _unblock(peerId) : null,
      ),
    );
  }
}

/// Lot 7.2c1 : ligne « X messages non lus » au-dessus du premier non lu.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      key: const Key('chat.unread_marker'),
      padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.s),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
          // Grande police sur petit écran : le texte passe à la ligne au lieu de déborder.
          Flexible(
            flex: 6,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.s),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count > 1 ? L.t.countMessagesNonLus(count) : L.t.n1MessageNonLu,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

/// Lot 7.2c1 : bouton rond « descendre » (apparaît quand on remonte), avec le nombre de
/// messages arrivés entre-temps.
class _ScrollDownButton extends StatelessWidget {
  const _ScrollDownButton({required this.visible, required this.count, required this.onTap});

  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.5,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.enter,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: Motion.of(context, Motion.fast),
          child: Semantics(
            button: true,
            label: count > 0 ? L.t.scrollDownNew(count) : L.t.descendreDerniersMessages,
            excludeSemantics: true,
            child: Badge(
              isLabelVisible: count > 0,
              label: PopOnChange(value: count, child: Text(count > 99 ? '99+' : '$count')),
              backgroundColor: theme.colorScheme.primary,
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 3,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('chat.scroll_down'),
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.keyboard_double_arrow_down_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lot 7.3a : heure et état d'un autocollant ou de grands émojis, lisibles sur le fond.
class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.bare, required this.child});

  final bool bare;
  final Widget child;

  @override
  Widget build(BuildContext context) => !bare
      ? child
      : DecoratedBox(
          decoration: BoxDecoration(
            color: PrivioPalette.of(context).bubbleIn.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: child,
          ),
        );
}
