import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/state_views.dart';
import '../lock/app_lock_screens.dart';
import 'discussions_tab.dart';

/// Lot 10.2 — discussions cachées (ADR-045).
///
/// * ouvertes par un appui long sur le logo Privio, puis le code Privio (jamais l'empreinte :
///   quelqu'un qui partage le téléphone peut y avoir enregistré la sienne) ;
/// * code demandé à chaque fois, qu'il y ait des discussions cachées ou non ;
/// * pas encore de code Privio : il est créé, sans activer le verrouillage à l'ouverture ;
/// * la liste se referme dès qu'on la quitte, que Privio passe en arrière-plan ou après
///   1 min sans action.

bool _hasPin(WidgetRef ref) {
  final c = ref.read(appLockProvider).value?.config;
  return c?.salt != null && c?.hash != null;
}

/// Demande le code Privio (ou le fait créer). Vrai si l'on peut continuer.
Future<bool> _askCode(BuildContext context, WidgetRef ref) async {
  final flow = _hasPin(ref) ? PinFlow.confirm : PinFlow.codeOnly;
  final ok = await Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => PinFlowScreen(flow: flow)));
  return ok ?? false;
}

/// Appui long sur le logo : code Privio, puis la liste des discussions cachées.
Future<void> openHiddenConversations(BuildContext context, WidgetRef ref) async {
  if (!await _askCode(context, ref) || !context.mounted) return;
  ref.read(hiddenUnlockedProvider.notifier).open();
  await context.push(Routes.hidden);
}

/// Masquer ou ne plus masquer une discussion (pour moi seulement).
Future<void> setConversationHidden(
  BuildContext context,
  WidgetRef ref,
  ConversationSummary summary,
  bool hide,
) async {
  // Le code Privio ouvrira la discussion cachée : il doit exister avant.
  if (hide && !_hasPin(ref)) {
    if (!await _askCode(context, ref) || !context.mounted) return;
  }
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  try {
    await ref.read(conversationsProvider.notifier).setSecret(summary.id, hide);
    messenger.showSnackBar(
      SnackBar(content: Text(hide ? L.t.discussionMasquee : L.t.discussionReaffichee)),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

class HiddenConversationsScreen extends ConsumerStatefulWidget {
  const HiddenConversationsScreen({super.key});

  static const idleTimeout = Duration(minutes: 1);

  @override
  ConsumerState<HiddenConversationsScreen> createState() => _HiddenConversationsScreenState();
}

class _HiddenConversationsScreenState extends ConsumerState<HiddenConversationsScreen>
    with WidgetsBindingObserver {
  late final HiddenUnlock _unlock = ref.read(hiddenUnlockedProvider.notifier);
  Timer? _idle;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _touch();
    // Arrivée sans le code (lien direct) : rien n'est montré.
    if (!ref.read(hiddenUnlockedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final unlock = _unlock;
    unawaited(Future<void>.microtask(unlock.close));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.hidden) return;
    // Appareil photo, galerie : sortie voulue depuis une discussion cachée.
    if (ref.read(appLockProvider.notifier).leavingOnPurpose) return;
    _close();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(HiddenConversationsScreen.idleTimeout, () {
      if (!mounted) return;
      // Une discussion cachée est ouverte par-dessus : on attend qu'on revienne ici.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return _touch();
      _close();
    });
  }

  /// Referme la liste et toute discussion cachée ouverte par-dessus.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    _idle?.cancel();
    _unlock.close();
    GoRouter.of(context).go(Routes.discussions);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(hiddenUnlockedProvider);
    final hidden = [
      for (final c in ref.watch(conversationsProvider).value ?? const <ConversationSummary>[])
        if (c.secret) c,
    ];
    return Listener(
      onPointerDown: (_) => _touch(),
      child: Scaffold(
        backgroundColor: PrivioPalette.of(context).sheet,
        appBar: AppBar(
          title: Text(L.t.discussionsCachees),
          actions: [
            IconButton(
              key: const Key('hidden.close'),
              tooltip: L.t.fermer,
              icon: const Icon(Icons.lock_outline),
              onPressed: _close,
            ),
          ],
        ),
        body: !unlocked
            ? const SizedBox.shrink()
            : hidden.isEmpty
            ? EmptyView(
                key: const Key('hidden.empty'),
                icon: Icons.visibility_off_outlined,
                title: L.t.aucuneDiscussionCachee,
                message: L.t.aucuneDiscussionCacheeMessage,
              )
            : ListView(
                key: const Key('hidden.list'),
                children: [for (final c in hidden) ConversationTile(summary: c)],
              ),
      ),
    );
  }
}
