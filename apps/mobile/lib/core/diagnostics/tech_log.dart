import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lot 6.1 (ADR-055) : journal technique local, court, sans contenu ni nom.
///
/// Il garde les 200 derniers événements : démarrages (version de Privio et
/// d'Android) et erreurs non rattrapées. Une erreur n'est notée que par son type
/// et son emplacement dans le code (lignes de pile) : jamais son texte, qui
/// pourrait contenir un message, un nom ou un numéro. Rien ne quitte le
/// téléphone sans l'accord de la personne, au moment d'une demande d'assistance.
class TechLog {
  TechLog({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final TechLog instance = TechLog();

  static const maxEntries = 200;

  /// Limite acceptée par le serveur pour un journal joint.
  static const maxExportChars = 16000;
  static const _key = 'privio.tech_log';
  static const _maxFrames = 8;

  final DateTime Function() _now;
  final List<String> _entries = [];
  bool _loaded = false;
  Timer? _save;

  List<String> get entries => List.unmodifiable(_entries);

  /// Recharge le journal enregistré (au démarrage).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key) ?? const [];
      _entries.insertAll(0, saved);
      _trim();
    } on Object {
      // Journal illisible : on repart d'un journal vide.
    }
  }

  void started({required String appVersion, String? android, String? model}) {
    _add(
      [
        'Démarrage · Privio $appVersion',
        if (android != null && android.isNotEmpty) 'Android $android',
        if (model != null && model.isNotEmpty) model,
      ].join(' · '),
    );
  }

  /// Erreur non rattrapée : type et emplacement seulement.
  void error(String origin, Object error, StackTrace? stack) {
    final lines = <String>['Erreur $origin · ${error.runtimeType}'];
    lines.addAll(stackLines(stack));
    _add(lines.join('\n'));
  }

  /// Lignes de pile utiles, sans texte libre : lignes « #n » (fichier et ligne en
  /// clair, ou adresses d'une version obfusquée) et identifiant de compilation qui
  /// permet de les retraduire avec les symboles conservés par la CI.
  static List<String> stackLines(StackTrace? stack) {
    if (stack == null) return const [];
    final out = <String>[];
    var frames = 0;
    for (final raw in stack.toString().split('\n')) {
      final line = raw.trim();
      if (line.startsWith('build_id:') || line.startsWith('isolate_dso_base:')) {
        out.add(line);
      } else if (RegExp(r'^#\d+\s').hasMatch(line) && frames < _maxFrames) {
        frames++;
        out.add(line.length > 160 ? line.substring(0, 160) : line);
      }
    }
    return out;
  }

  /// Texte joint à une demande d'assistance : les entrées les plus récentes qui
  /// tiennent dans la limite du serveur, dans l'ordre chronologique.
  String export() {
    final kept = <String>[];
    var size = 0;
    for (final e in _entries.reversed) {
      if (size + e.length + 1 > maxExportChars) break;
      kept.add(e);
      size += e.length + 1;
    }
    return kept.reversed.join('\n');
  }

  void clear() {
    _entries.clear();
    _persist();
  }

  void _add(String text) {
    final t = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
    _entries.add('$stamp $text');
    _trim();
    _persist();
  }

  void _trim() {
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_key, List.of(_entries));
      } on Object {
        // Écriture impossible : le journal reste en mémoire.
      }
    });
  }

  /// Branche le journal sur les erreurs non rattrapées (Flutter et Dart).
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error('affichage', details.exception, details.stack);
      previous?.call(details);
    };
    final platformPrevious = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, st) {
      error('application', e, st);
      return platformPrevious?.call(e, st) ?? false;
    };
  }
}
