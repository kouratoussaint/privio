import '../../l10n/l10n.dart';

import 'package:intl/intl.dart';

/// Heure d'un message ou d'une discussion, à la française.
String formatMessageTime(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.Hm('fr').format(local);
  if (diff == 1) return 'hier';
  if (diff < 7) return DateFormat.E('fr').format(local);
  return DateFormat('dd/MM', 'fr').format(local);
}

/// Temps restant avant expiration : « 71 h », « 45 min », « < 1 min ».
String formatRemaining(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.inMinutes < 1) return L.t.n1Min;
  if (left.inHours < 1) return L.t.unitMinutes(left.inMinutes);
  return L.t.unitHours(left.inHours);
}

/// Durées proposées en puces pour une discussion ou un message (lot 4.6), bornées par
/// les règles serveur ; toute autre durée passe par « Personnalisé » (72 h au plus).
const kTtlChoices = [5 * 60, 15 * 60, 30 * 60, 3600, 6 * 3600, 12 * 3600, 24 * 3600, 48 * 3600];

/// « 5 min », « 1 h », « 4 h 30 », « 72 h » — espaces insécables : jamais coupé en fin
/// de ligne (« 4 / h 30 »).
String formatTtl(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return L.t.ttlMinutes(minutes);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? L.t.ttlHours(h) : L.t.ttlHoursMinutes(h, m.toString().padLeft(2, '0'));
}
