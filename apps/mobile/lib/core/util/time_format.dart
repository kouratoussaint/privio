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
  if (left.inMinutes < 1) return '< 1 min';
  if (left.inHours < 1) return '${left.inMinutes} min';
  return '${left.inHours} h';
}
