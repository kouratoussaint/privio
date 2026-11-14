import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../core/widgets/avatar.dart';

/// Lot 7.1b : @mentions dans un groupe. Taper « @ » propose les membres ; le choix insère
/// « @Nom » dans le texte. La personne mentionnée est prévenue (notification sans contenu),
/// même si elle a mis le groupe en sourdine.

/// Mention en cours de saisie : position du « @ » et texte tapé après lui.
class MentionQuery {
  const MentionQuery(this.start, this.query);

  final int start;
  final String query;
}

/// Mention en cours juste avant le curseur, ou null. Le « @ » doit ouvrir un mot.
MentionQuery? activeMention(TextEditingValue value) {
  final sel = value.selection;
  if (!sel.isValid || !sel.isCollapsed || sel.baseOffset > value.text.length) return null;
  final before = value.text.substring(0, sel.baseOffset);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && before[at - 1].trim().isNotEmpty) return null;
  final query = before.substring(at + 1);
  if (query.length > 30 || query.contains('\n') || query.startsWith(' ')) return null;
  return MentionQuery(at, query);
}

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ÿ': 'y',
  'ñ': 'n',
  'œ': 'oe',
  'æ': 'ae',
  'ɛ': 'e',
  'ɔ': 'o',
  'ŋ': 'n',
};

/// Minuscules sans accents (« Gaël » se trouve en tapant « gael »).
String foldName(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    b.write(_accents[c] ?? c);
  }
  return b.toString();
}

/// Membres proposés pour [query] : ni soi-même, ni les invités qui n'ont pas répondu.
/// Une recherche avec espace sans résultat ferme la liste (la mention est finie).
List<GroupMember> mentionCandidates(List<GroupMember> members, String query, {String? me}) {
  final q = foldName(query);
  bool fits(GroupMember m) {
    if (q.isEmpty) return true;
    final name = foldName(m.displayName);
    return name.startsWith(q) ||
        name.split(' ').any((w) => w.startsWith(q)) ||
        foldName(m.handle ?? '').startsWith(q);
  }

  final list = members.where((m) => !m.invited && m.userId != me && fits(m)).toList()
    ..sort((a, b) => foldName(a.displayName).compareTo(foldName(b.displayName)));
  return list.take(6).toList();
}

/// Remplace la mention en cours par « @Nom » suivi d'une espace ; curseur après.
TextEditingValue insertMention(TextEditingValue value, MentionQuery mention, String name) {
  final insert = '@$name ';
  final text = value.text.replaceRange(mention.start, value.selection.baseOffset, insert);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: mention.start + insert.length),
  );
}

/// Personnes choisies dont la mention est toujours dans le texte (effacée : retirée).
List<String> mentionedIds(String text, Map<String, String> picked) => [
  for (final e in picked.entries)
    if (text.contains('@${e.value}')) e.key,
];

/// Texte d'un message, mentions mises en valeur ; la sienne ressort davantage.
TextSpan mentionSpan(
  String text, {
  required Map<String, bool> names,
  required TextStyle? style,
  required TextStyle mention,
  required TextStyle mine,
}) {
  final list = names.keys.where((n) => n.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (list.isEmpty) return TextSpan(text: text, style: style);
  final pattern = RegExp('@(${list.map(RegExp.escape).join('|')})');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(0), style: names[m.group(1)] ?? false ? mine : mention));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: style, children: spans);
}

/// Liste des membres proposés, au-dessus du champ de saisie.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({super.key, required this.candidates, required this.onPick});

  final List<GroupMember> candidates;
  final ValueChanged<GroupMember> onPick;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.s, 0, PrivioSpacing.s, PrivioSpacing.xs),
      child: Material(
        key: const Key('mention.list'),
        color: p.sheet,
        elevation: 2,
        borderRadius: BorderRadius.circular(PrivioRadius.large),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xs),
            children: [
              for (final m in candidates)
                ListTile(
                  key: Key('mention.option.${m.userId}'),
                  dense: true,
                  leading: UserAvatar(
                    name: m.displayName,
                    avatarPath: m.avatarPath,
                    seed: m.userId,
                    radius: 16,
                  ),
                  title: Text(m.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: m.handle == null
                      ? null
                      : Text(
                          '@${m.handle}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  onTap: () => onPick(m),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
