import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../core/widgets/settings_card.dart';

/// Lot 8.4c — « Ce que Privio garde » (texte validé le 15/11/2026, ADR-035). Accessible
/// depuis Aide et Confidentialité. Aucune mention du chiffrement (décision F du 15/11/2026).
class WhatPrivioKeepsScreen extends StatelessWidget {
  const WhatPrivioKeepsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const WhatPrivioKeepsScreen());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <(IconData, String, List<String>)>[
      (
        Icons.chat_bubble_outline,
        L.t.keepMessagesTitle,
        [L.t.keepMessages1, L.t.keepMessages2, L.t.keepMessages3],
      ),
      (
        Icons.person_outline,
        L.t.keepAccountTitle,
        [L.t.keepAccount1, L.t.keepAccount2, L.t.keepAccount3],
      ),
      (
        Icons.history_rounded,
        L.t.keepLongerTitle,
        [L.t.keepLonger1, L.t.keepLonger2, L.t.keepLonger3, L.t.keepLonger4],
      ),
      (
        Icons.block_outlined,
        L.t.keepNeverTitle,
        [L.t.keepNever1, L.t.keepNever2, L.t.keepNever3, L.t.keepNever4, L.t.keepNever5],
      ),
      (Icons.phone_android, L.t.keepPhoneTitle, [L.t.keepPhone1]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(L.t.keepTitle)),
      body: SettingsListView(
        key: const Key('keeps.screen'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, PrivioSpacing.s, 0, PrivioSpacing.s),
            child: Text(L.t.keepIntro, style: theme.textTheme.bodyLarge),
          ),
          for (final (icon, title, bullets) in sections) ...[
            SettingsSectionTitle(title),
            SettingsCard(
              padding: const EdgeInsets.all(PrivioSpacing.l),
              children: [
                for (final (i, b) in bullets.indexed) ...[
                  if (i > 0) const SizedBox(height: PrivioSpacing.m),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: PrivioPalette.of(context).accentText),
                      const SizedBox(width: PrivioSpacing.m),
                      Expanded(child: Text(b, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: PrivioSpacing.xl),
        ],
      ),
    );
  }
}
