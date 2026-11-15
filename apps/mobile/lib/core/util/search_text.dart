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
