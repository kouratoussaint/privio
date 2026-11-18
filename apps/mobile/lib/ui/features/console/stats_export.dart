import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/console.dart';
import '../../../domain/models/console_team.dart';

/// Lot 5.9 — export des statistiques : un fichier CSV de nombres agrégés (jamais de nom, de
/// numéro ni de contenu), partagé par le menu d'Android. Réservé au propriétaire, journalisé.

String statsCsvName(DateTime now) =>
    'privio-statistiques-${now.year}${now.month.toString().padLeft(2, '0')}'
    '${now.day.toString().padLeft(2, '0')}.csv';

String statsCsv(ConsoleStats s, StatsExtra extra) {
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final usage = {for (final (d, v) in extra.usage) day(d): v};
  final metrics = kUsageMetrics.keys.toList();
  final b = StringBuffer()
    ..writeln(
      [
        'jour',
        'actifs',
        'nouveaux_comptes',
        'messages',
        'demandes_connexion',
        'demandes_acceptees',
        'notifications_envoyees',
        'notifications_echouees',
        ...metrics,
      ].join(';'),
    );
  for (final d in s.days) {
    final u = usage[day(d.day)] ?? const <String, int>{};
    b.writeln(
      [
        day(d.day),
        d.active ?? '',
        d.newAccounts,
        d.messages,
        d.requests,
        d.accepted,
        d.pushSent,
        d.pushFailed,
        for (final m in metrics) u[m] ?? 0,
      ].join(';'),
    );
  }
  b
    ..writeln()
    ..writeln(
      'semaine_inscription;inscrits;eligibles_j1;revenus_j1;eligibles_j7;revenus_j7;'
      'eligibles_j30;revenus_j30',
    );
  for (final w in extra.retention) {
    b.writeln([day(w.week), w.signups, w.d1, w.r1, w.d7, w.r7, w.d30, w.r30].join(';'));
  }
  b
    ..writeln()
    ..writeln('langue;telephones');
  for (final e in extra.languages.entries) {
    b.writeln('${e.key};${e.value}');
  }
  return b.toString();
}

/// Partage du fichier (remplacé dans les tests).
final shareCsvProvider = Provider<Future<void> Function(String name, String csv)>(
  (ref) =>
      (name, csv) => SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(Uint8List.fromList(utf8.encode(csv)), mimeType: 'text/csv', name: name),
          ],
          fileNameOverrides: [name],
        ),
      ),
);
