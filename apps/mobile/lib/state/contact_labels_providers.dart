import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/contact_labels.dart';
import 'messaging_providers.dart';
import 'providers.dart';

/// Lot 10.4 — mes surnoms privés et vérifications en personne (ADR-048) : d'abord la copie
/// de ce téléphone, puis le serveur (à chaque synchronisation de la liste des discussions).
/// Tient aussi à jour [ContactLabels.current], lu par les modèles pour afficher les noms.
final contactLabelsProvider = NotifierProvider<ContactLabelsController, Map<String, ContactLabel>>(
  ContactLabelsController.new,
);

class ContactLabelsController extends Notifier<Map<String, ContactLabel>> {
  @override
  Map<String, ContactLabel> build() {
    // Changement de compte : rien ne passe d'un compte à l'autre.
    if (ref.watch(currentUserIdProvider) == null) {
      ContactLabels.reset();
      return const {};
    }
    final cache = ref.watch(localCacheProvider);
    unawaited(
      cache.ensureLoaded().then((_) {
        if (ref.mounted && state.isEmpty && cache.labels.isNotEmpty) _set(_index(cache.labels));
      }),
    );
    final initial = _index(cache.labels);
    ContactLabels.current = initial;
    return initial;
  }

  static Map<String, ContactLabel> _index(List<ContactLabel> list) => {
    for (final l in list) l.userId: l,
  };

  void _set(Map<String, ContactLabel> labels) {
    ContactLabels.current = labels;
    state = labels;
  }

  Future<void> _save() => ref.read(localCacheProvider).putLabels(state.values.toList());

  /// Synchronise avec le serveur ; hors connexion, la copie locale reste affichée.
  Future<void> refresh() async {
    try {
      final list = await ref.read(messagingApiProvider).listContactLabels();
      if (!ref.mounted) return;
      _set(_index(list));
      await _save();
    } on Object {
      // Hors connexion : on garde ce qu'on a.
    }
  }

  /// Surnom privé de [userId] (null ou vide : retiré). Les erreurs remontent à l'écran.
  Future<void> setNickname(String userId, String? nickname) async {
    final saved = await ref.read(messagingApiProvider).setContactNickname(userId, nickname);
    if (!ref.mounted) return;
    final next = Map.of(state);
    final old = next[userId];
    if (saved == null) {
      if (old != null) {
        if (old.verification == null) {
          next.remove(userId);
        } else {
          next[userId] = old.copyWith(clearNickname: true);
        }
      }
    } else {
      next[userId] = (old ?? ContactLabel(userId: userId)).copyWith(nickname: saved);
    }
    _set(next);
    await _save();
  }

  /// Fermer l'avis « vérification à refaire » (le badge reste retiré).
  Future<void> dismissNotice(String userId) async {
    final old = state[userId];
    if (old != null) _set({...state, userId: old.copyWith(notice: false)});
    try {
      await ref.read(messagingApiProvider).dismissVerificationNotice(userId);
      await _save();
    } on Object {
      // Réessayé à la prochaine fermeture ; l'état revient du serveur au rafraîchissement.
    }
  }
}
