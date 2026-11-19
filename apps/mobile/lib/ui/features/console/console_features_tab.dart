import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/console.dart';
import '../../../state/console_providers.dart';
import '../../core/widgets/settings_card.dart';
import 'console_ui.dart';
import '../../core/widgets/state_views.dart';

/// Lot 5.5 — rubrique « Fonctionnalités » de la console : interrupteurs appliqués tout de
/// suite à tous (le serveur refuse ce qui est coupé, l'application masque les boutons),
/// message d'information affiché à tous, engagements de Privio (fixés) et fonctions pas
/// encore développées (pour information).
class ConsoleFeaturesTab extends ConsumerWidget {
  const ConsoleFeaturesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(consolePoliciesProvider);
    return switch (policies) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(consolePoliciesProvider.future),
        child: _FeatureList(policies: value),
      ),
      AsyncError(:final error) => ErrorView(
        message: toAppFailure(error).message,
        onRetry: () => ref.invalidate(consolePoliciesProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

const _violet = Color(0xFF8E44C9);

IconData _featureIcon(String key) => switch (key) {
  'signups_enabled' => Icons.person_add_alt_1_outlined,
  'calls_audio_enabled' => Icons.call_outlined,
  'calls_video_enabled' => Icons.videocam_outlined,
  'voice_enabled' => Icons.mic_none_rounded,
  'photo_enabled' => Icons.photo_camera_outlined,
  'gif_enabled' => Icons.gif_box_outlined,
  'link_preview_enabled' => Icons.link_rounded,
  'group_create_enabled' => Icons.group_add_outlined,
  'group_invite_links_enabled' => Icons.qr_code_2_rounded,
  'message_copy_enabled' => Icons.content_copy_rounded,
  'internal_forward_enabled' => Icons.forward_rounded,
  'external_share_enabled' => Icons.ios_share_rounded,
  'conversation_export_enabled' => Icons.file_download_outlined,
  'save_media_to_gallery_enabled' => Icons.photo_library_outlined,
  'screen_capture_allowed' => Icons.screenshot_monitor_outlined,
  'document_upload_enabled' => Icons.description_outlined,
  'message_ttl_hours' => Icons.timer_outlined,
  'quota_timezone' => Icons.public_rounded,
  'video_call_max_minutes' => Icons.timer_outlined,
  'video_upload_enabled' => Icons.movie_outlined,
  _ => Icons.toggle_on_outlined,
};

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.policies});

  final List<ConsolePolicy> policies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<ConsolePolicy> of(String c, {bool? bools}) => [
      for (final p in policies)
        if (p.category == c && (bools == null || p.isBool == bools)) p,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final switches = of('features', bools: true);
    final announcement = of('features', bools: false).firstOrNull;
    final locked = of('locked');
    final future = of('future');
    return ListView(
      key: const Key('console.features'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.l,
        PrivioSpacing.m,
        PrivioSpacing.l,
        PrivioSpacing.xxl,
      ),
      children: [
        const ConsoleIntro(
          'Appliqué tout de suite à tous les comptes. Le serveur refuse ce qui est coupé\u202F; '
          'l’application masque les boutons au prochain retour. Chaque changement est '
          'inscrit au journal.',
        ),
        // Lot 5.10 : titre de section aussi pour les fonctions (pas de carte vide).
        if (switches.isNotEmpty) ...[
          const ConsoleHeading('Fonctions', first: true),
          SettingsCard(
            children: [
              for (final (i, p) in switches.indexed) ...[
                if (i > 0) const SettingsDivider(),
                _FeatureSwitch(policy: p),
              ],
            ],
          ),
        ],
        if (announcement != null) ...[
          const SettingsSectionTitle('Message d’information'),
          SettingsCard(children: [_AnnouncementTile(policy: announcement)]),
        ],
        const SettingsSectionTitle('Engagements de Privio'),
        SettingsCard(
          children: [
            for (final (i, p) in locked.indexed) ...[
              if (i > 0) const SettingsDivider(),
              ListTile(
                key: Key('feature.${p.key}'),
                leading: Icon(_featureIcon(p.key), color: theme.colorScheme.onSurfaceVariant),
                // Lot 5.10 : « Durée de vie maximale d’un message : 72 h » → titre, puis
                // valeur avec la mention (plus de « : 72 h » seul à la ligne).
                title: Text(p.label.split(RegExp(r'\s:\s')).first),
                subtitle: Text(
                  [
                    ...p.label.split(RegExp(r'\s:\s')).skip(1),
                    p.isBool
                        ? 'Promis à l’inscription\u202F: non modifiable'
                        : 'Fixé\u202F: non modifiable',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.lock_outline),
              ),
            ],
          ],
        ),
        if (future.isNotEmpty) ...[
          const SettingsSectionTitle('Pas encore développés'),
          SettingsCard(
            children: [
              for (final (i, p) in future.indexed) ...[
                if (i > 0) const SettingsDivider(),
                ListTile(
                  key: Key('feature.${p.key}'),
                  leading: Icon(_featureIcon(p.key), color: theme.colorScheme.onSurfaceVariant),
                  title: Text(p.label),
                  subtitle: const Text('Disponible quand la fonction sera développée'),
                  trailing: const Icon(Icons.lock_outline),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _FeatureSwitch extends ConsumerStatefulWidget {
  const _FeatureSwitch({required this.policy});

  final ConsolePolicy policy;

  @override
  ConsumerState<_FeatureSwitch> createState() => _FeatureSwitchState();
}

class _FeatureSwitchState extends ConsumerState<_FeatureSwitch> {
  bool _saving = false;

  ConsolePolicy get _p => widget.policy;

  Future<void> _toggle(bool on) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('feature.confirm'),
        title: Text('${on ? 'Activer' : 'Désactiver'} : ${_p.label} ?'),
        content: Text(_p.effectText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('feature.confirm.ok'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(on ? 'Activer' : 'Désactiver'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await savePolicy(ref, _p, on);
      messenger.showSnackBar(
        SnackBar(content: Text('${_p.label} : ${on ? 'activé' : 'désactivé'}')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = _p.value == true;
    final color = on ? _violet : theme.colorScheme.onSurfaceVariant;
    return SwitchListTile(
      key: Key('feature.${_p.key}'),
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: on ? 0.14 : 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(_featureIcon(_p.key), color: color, size: 20),
      ),
      title: Text(_p.label),
      subtitle: Text(
        on ? 'Activé' : 'Désactivé pour tous',
        style: on ? null : TextStyle(color: theme.colorScheme.error),
      ),
      value: on,
      activeThumbColor: _violet,
      onChanged: _saving ? null : _toggle,
    );
  }
}

class _AnnouncementTile extends ConsumerWidget {
  const _AnnouncementTile({required this.policy});

  final ConsolePolicy policy;

  static const maxChars = 200;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _AnnouncementDialog(initial: policy.value as String? ?? ''),
    );
    if (next == null || next == policy.value || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await savePolicy(ref, policy, next);
      messenger.showSnackBar(
        SnackBar(content: Text(next.isEmpty ? 'Message retiré' : 'Message publié pour tous')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = (policy.value as String? ?? '').trim();
    const amber = Color(0xFFB7700F);
    return ListTile(
      key: const Key('feature.announcement_text'),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: amber.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: const Icon(Icons.campaign_outlined, color: amber, size: 20),
      ),
      title: Text(text.isEmpty ? 'Aucun message' : text),
      subtitle: Text(
        text.isEmpty ? 'Toucher pour écrire un message' : 'Affiché à tous · toucher pour modifier',
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _edit(context, ref),
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog({required this.initial});

  final String initial;

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('announcement.editor'),
    title: const Text('Message d’information'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Affiché à tous en haut des listes Discussions et Groupes.'),
        const SizedBox(height: PrivioSpacing.m),
        TextField(
          key: const Key('announcement.input'),
          controller: _ctrl,
          maxLength: _AnnouncementTile.maxChars,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Maintenance ce soir à 22 h'),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const Key('announcement.clear'),
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Retirer'),
      ),
      FilledButton(
        key: const Key('announcement.publish'),
        onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
        child: const Text('Publier'),
      ),
    ],
  );
}
