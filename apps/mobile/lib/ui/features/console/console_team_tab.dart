import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console_team.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';
import 'console_reports_tab.dart' show consoleChip;

/// Lot 5.8 — « Équipe » (propriétaire) : qui a accès à la console, avec quel rôle. Ajout
/// par le numéro d'un compte Privio existant ; deux étapes obligatoires pour l'équipe.
class ConsoleTeamTab extends ConsumerWidget {
  const ConsoleTeamTab({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, ConsoleRole)>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminApiProvider).addStaff(result.$1, result.$2);
      ref.invalidate(consoleTeamProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Ajouté à l’équipe (${result.$2.label.toLowerCase()}).')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  Future<void> _manage(BuildContext context, WidgetRef ref, StaffMember m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(m.name ?? '@${m.handle ?? '—'}'), subtitle: Text(m.role.label)),
            for (final r in [ConsoleRole.moderator, ConsoleRole.support])
              if (r != m.role)
                ListTile(
                  key: Key('team.role.${r.name}'),
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text('Passer en «\u202F${r.label}\u202F»'),
                  onTap: () => Navigator.pop(c, r.name),
                ),
            ListTile(
              key: const Key('team.remove'),
              leading: Icon(Icons.person_remove_outlined, color: Theme.of(c).colorScheme.error),
              title: Text(
                'Retirer de l’équipe',
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(adminApiProvider);
    try {
      if (choice == 'remove') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Retirer de l’équipe\u202F?'),
            content: Text(
              '${m.name ?? '@${m.handle}'} n’aura plus accès à la console. Ses décisions '
              'passées restent au journal.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
              FilledButton(
                key: const Key('team.remove.confirm'),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Retirer'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await api.removeStaff(m.userId);
        messenger.showSnackBar(const SnackBar(content: Text('Retiré de l’équipe.')));
      } else {
        await api.setStaffRole(m.userId, ConsoleRole.of(choice)!);
        messenger.showSnackBar(const SnackBar(content: Text('Rôle modifié.')));
      }
      ref.invalidate(consoleTeamProvider);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(consoleTeamProvider);
    final theme = Theme.of(context);
    return switch (team) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consoleTeamProvider.future),
        child: ListView(
          key: const Key('team.list'),
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.m,
            PrivioSpacing.m,
            PrivioSpacing.m,
            PrivioSpacing.xxl,
          ),
          children: [
            Text(
              'Modérateur\u202F: signalements, sanctions, groupes, sites sans aperçu. '
              'Assistance\u202F: demandes d’assistance, fiches des comptes sans sanction. '
              'La vérification en deux étapes est obligatoire pour l’équipe.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: PrivioSpacing.m),
            for (final m in value)
              Card(
                key: Key('team.member.${m.userId}'),
                margin: const EdgeInsets.only(bottom: PrivioSpacing.s),
                child: ListTile(
                  leading: UserAvatar(
                    name: m.name ?? m.handle ?? '?',
                    avatarPath: m.avatar,
                    seed: m.userId,
                    radius: 20,
                  ),
                  title: Text(m.name ?? '@${m.handle ?? '—'}'),
                  subtitle: Text(
                    [
                      '${m.role.label}${m.handle == null ? '' : ' · @${m.handle}'}',
                      if (m.phone != null) m.phone!,
                      if (!m.role.isOwner)
                        m.twoStep ? 'Deux étapes activées' : 'Deux étapes à activer',
                      if (m.lastActionAt != null) 'Dernière action\u202F: ${_day(m.lastActionAt!)}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: m.role.isOwner
                      ? Icon(Icons.verified_rounded, color: theme.colorScheme.primary)
                      : !m.twoStep
                      ? Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error)
                      : const Icon(Icons.more_vert),
                  onTap: m.role.isOwner ? null : () => _manage(context, ref, m),
                ),
              ),
            const SizedBox(height: PrivioSpacing.m),
            FilledButton.icon(
              key: const Key('team.add'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Ajouter une personne'),
            ),
          ],
        ),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consoleTeamProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _phone = TextEditingController();
  ConsoleRole _role = ConsoleRole.moderator;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  /// 8 chiffres (Burkina Faso) ou numéro complet +226…
  String? get _e164 {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (RegExp(r'^\d{8}$').hasMatch(digits)) return '+226$digits';
    if (RegExp(r'^\+\d{8,15}$').hasMatch(digits)) return digits;
    if (RegExp(r'^00\d{8,15}$').hasMatch(digits)) return '+${digits.substring(2)}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('team.add.dialog'),
      title: const Text('Ajouter à l’équipe'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Numéro d’un compte Privio existant. La personne devra activer la vérification '
              'en deux étapes pour ouvrir la console.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.m),
            TextField(
              key: const Key('team.add.phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Numéro',
                hintText: '70 00 00 00 ou +226…',
              ),
            ),
            const SizedBox(height: PrivioSpacing.m),
            Wrap(
              spacing: PrivioSpacing.s,
              children: [
                for (final r in [ConsoleRole.moderator, ConsoleRole.support])
                  consoleChip(
                    context,
                    key: Key('team.add.role.${r.name}'),
                    label: r.label,
                    selected: _role == r,
                    onTap: () => setState(() => _role = r),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('team.add.confirm'),
          onPressed: _e164 == null ? null : () => Navigator.pop(context, (_e164!, _role)),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

String _day(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
