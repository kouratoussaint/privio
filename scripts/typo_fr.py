#!/usr/bin/env python3
"""Typographie française des textes de l'application (lot 4.4, R-36).

Ne lit que les chaînes Dart (pas le code ni les commentaires) et applique :
  * espace fine insécable (U+202F) avant ? ! ; : et à l'intérieur de « » ;
  * apostrophe typographique ’ entre deux lettres (l'app → l’app).

  python3 scripts/typo_fr.py --check <dossiers…>   # CI : liste les écarts, code 1 s'il y en a
  python3 scripts/typo_fr.py --fix <dossiers…>     # corrige les fichiers en place

Un commentaire `// typo-fr: ignore-next` protège les chaînes des 3 lignes suivantes
(rappels de durée des messages, laissés tels quels sur décision du 13/11/2026).
"""
import pathlib
import re
import sys

NNBSP = "\\u202F"  # écrit sous forme d'échappement Dart, lisible dans le source
LETTER = "A-Za-zÀ-ÖØ-öø-ÿŒœ"
IGNORE = "typo-fr: ignore-next"
IGNORE_SPAN = 3


def string_segments(src):
    """Renvoie (début, fin, guillemet) des morceaux de texte littéral des chaînes Dart,
    interpolations exclues. Chaînes brutes (r'…') ignorées."""
    segs = []
    i, n = 0, len(src)

    def scan_code(i, stop_at_brace):
        depth = 0
        while i < n:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2)
                i = n if j < 0 else j + 2
                continue
            if c in "'\"":
                raw = i > 0 and src[i - 1] in "rR" and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == "_"))
                i = scan_string(i, raw)
                continue
            if stop_at_brace:
                if c == "{":
                    depth += 1
                elif c == "}":
                    if depth == 0:
                        return i + 1
                    depth -= 1
            i += 1
        return i

    def scan_string(i, raw):
        q = src[i]
        triple = src.startswith(q * 3, i)
        delim = q * 3 if triple else q
        i += len(delim)
        start = i
        while i < n:
            if not raw and src[i] == "\\":
                i += 2
                continue
            if src.startswith(delim, i):
                if not raw:
                    segs.append((start, i, q))
                return i + len(delim)
            if not raw and src[i] == "$":
                if i + 1 < n and src[i + 1] == "{":
                    segs.append((start, i, q))
                    i = scan_code(i + 2, True)
                    start = i
                    continue
                m = re.match(r"\$[A-Za-z_]\w*", src[i:])
                if m:
                    segs.append((start, i, q))
                    i += m.end()
                    start = i
                    continue
            if not triple and src[i] == "\n":
                return i
            i += 1
        return i

    scan_code(0, False)
    return segs


RULES = [
    # espace normale avant ? ! ; : (fin de segment, espace ou fermeture ensuite)
    (re.compile(r"(?<=\S) ([?!;:])(?=$|[\s)»’'\"\\])"), lambda m: NNBSP + m.group(1)),
    (re.compile(r"^ ([?!;:])(?=$|[\s)»’'\"\\])"), lambda m: NNBSP + m.group(1)),
    (re.compile(r"« "), lambda m: "«" + NNBSP),
    (re.compile(r" »"), lambda m: NNBSP + "»"),
]


def fix_text(text, quote):
    out = text
    for rx, rep in RULES:
        out = rx.sub(rep, out)
    if quote == "'":
        out = re.sub(rf"(?<=[{LETTER}])\\'(?=[{LETTER}])", "’", out)
    else:
        out = re.sub(rf"(?<=[{LETTER}])'(?=[{LETTER}])", "’", out)
    return out


def process(path, fix):
    src = path.read_text(encoding="utf-8")
    ignored = set()
    lines = src.splitlines(keepends=True)
    starts, pos = [], 0
    for line in lines:
        starts.append(pos)
        pos += len(line)
    starts.append(pos)
    for k, line in enumerate(lines):
        if IGNORE in line:
            end = starts[min(k + 1 + IGNORE_SPAN, len(lines))]
            ignored.update(range(starts[k], end))
    issues, pieces, last = [], [], 0
    for a, b, q in string_segments(src):
        if a in ignored:
            continue
        seg = src[a:b]
        new = fix_text(seg, q)
        if new != seg:
            line = src.count("\n", 0, a) + 1
            issues.append(f"{path}:{line}: {seg.strip()[:80]}")
            pieces.append(src[last:a])
            pieces.append(new)
            last = b
    if fix and issues:
        pieces.append(src[last:])
        path.write_text("".join(pieces), encoding="utf-8")
    return issues


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("--check", "--fix"):
        print(__doc__)
        return 2
    fix = sys.argv[1] == "--fix"
    issues = []
    for d in sys.argv[2:]:
        for f in sorted(pathlib.Path(d).rglob("*.dart")):
            issues += process(f, fix)
    for line in issues:
        print(line)
    return 0 if fix or not issues else 1


if __name__ == "__main__":
    sys.exit(main())
