/// Lot 8.3b : texte comparable pour une recherche locale (minuscules, sans accents).
/// « Aïcha » et « aicha », « Kaboré » et « kabore » se retrouvent ; lettres du mooré et du
/// dioula comprises (ɛ, ɔ, ŋ, ɲ, ʋ, voyelles nasales).
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_fold[c] ?? c);
  }
  return b.toString();
}

const _fold = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ẽ': 'e',
  'ɛ': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ĩ': 'i',
  'ɩ': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'õ': 'o',
  'ɔ': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ũ': 'u',
  'ʋ': 'u',
  'ÿ': 'y',
  'ñ': 'n',
  'ɲ': 'n',
  'ŋ': 'n',
  'œ': 'oe',
  'æ': 'ae',
  '’': "'",
};

/// Lot 8.4c : nom réduit à ses lettres et chiffres (sans accents, sans espaces).
String nameKey(String s) => foldForSearch(s).replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Distance d'édition (insertions, suppressions, remplacements), bornée à [max] + 1.
int editDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// Lot 8.4c : deux noms qu'on pourrait confondre : identiques sans accents, majuscules ni
/// espaces, ou à une lettre près (« Amina Dialo »). Moins de 4 lettres : identiques seulement.
bool namesLookAlike(String a, String b) {
  final x = nameKey(a);
  final y = nameKey(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x.length < 4 || y.length < 4) return x == y;
  return editDistance(x, y, max: 1) <= 1;
}
