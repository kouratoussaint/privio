import '../../l10n/l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Lot 8.1c : texte d'invitation (partage Android). Seulement l'identifiant pour l'instant ;
/// le lien de téléchargement sera ajouté quand il existera. Aucune promesse de chiffrement.
String inviteText(String? handle) {
  final me = handle == null ? '' : L.t.monIdentifiantHandle(handle);
  return L.t.jeSuisSurPrivioMessagerie(me);
}

/// Ouvre le partage du téléphone (remplacé dans les tests).
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) =>
      (text) => SharePlus.instance.share(ShareParams(text: text, subject: L.t.rejoinsMoiSurPrivio)),
);
