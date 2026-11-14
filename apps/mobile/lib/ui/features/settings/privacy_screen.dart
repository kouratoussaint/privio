import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ttl_picker.dart';
import '../lock/app_lock_screens.dart' show delayLabel;
import '../../../state/providers.dart';

/// Écran 23 — confidentialité et sécurité (lot 4.3). Chaque réglage est appliqué par le
/// serveur ; « mes contacts » = personnes avec qui l'on a une discussion à deux.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, PrivacySettings next) async {
    try {
      await ref.read(privacyProvider.notifier).save(next);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  Future<String?> _pickVisibility(
    BuildContext context, {
    required String title,
    required String help,
    required String current,
    required String keyPrefix,
  }) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.l),
            child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.l,
              PrivioSpacing.xs,
              PrivioSpacing.l,
              PrivioSpacing.s,
            ),
            child: Text(help, style: Theme.of(ctx).textTheme.bodySmall),
          ),
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              children: [
                for (final v in const ['everyone', 'contacts', 'nobody'])
                  RadioListTile<String>(
                    key: Key('$keyPrefix.$v'),
                    value: v,
                    title: Text(visibilityLabel(v)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickTtl(BuildContext context, WidgetRef ref, PrivacySettings s) async {
    final rules = ref.read(messagingRulesProvider).value ?? const MessagingRules();
    final current = s.defaultTtlSeconds ?? rules.maxTtlSeconds;
    final picked = await showTtlPicker(
      context,
      title: 'Durée par défaut des messages',
      help: 'Pour les discussions et groupes que vous créerez.',
      current: current,
      min: rules.minTtlSeconds,
      max: rules.maxTtlSeconds,
      keyPrefix: 'privacy.ttl',
    );
    if (picked == null || !context.mounted) return;
    await _save(
      context,
      ref,
      picked == rules.maxTtlSeconds
          ? s.copyWith(clearDefaultTtl: true)
          : s.copyWith(defaultTtlSeconds: picked),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final privacy = ref.watch(privacyProvider);
    final lock = ref.watch(appLockProvider).value;
    final rules = ref.watch(messagingRulesProvider).value ?? const MessagingRules();

    final s = privacy.value;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confidentialité')),
        body: privacy.hasError
            ? ErrorView(
                message: toAppFailure(privacy.error!).message,
                onRetry: () => ref.invalidate(privacyProvider),
              )
            : const LoadingView(),
      );
    }

    Future<void> visibility(String which) async {
      final (label, help, current) = switch (which) {
        'presence' => (
          'Statut «\u202Fen ligne\u202F» et «\u202Fvu à\u202F»',
          'Qui voit si vous êtes connecté, et quand vous l’étiez pour la dernière fois.',
          s.presence,
        ),
        'avatar' => ('Photo de profil', 'Les autres voient vos initiales à la place.', s.avatar),
        'about' => (
          'À propos',
          'Votre court texte de présentation, affiché sur votre fiche.',
          s.about,
        ),
        _ => (
          'Invitations dans les groupes',
          'Les personnes non autorisées ne peuvent pas vous inviter (sans qu’on le leur dise). '
              'Une invitation doit toujours être acceptée.',
          s.groupInvites,
        ),
      };
      final v = await _pickVisibility(
        context,
        title: label,
        help: help,
        current: current,
        keyPrefix: 'privacy.$which',
      );
      if (v == null || v == current || !context.mounted) return;
      await _save(context, ref, switch (which) {
        'presence' => s.copyWith(presence: v),
        'avatar' => s.copyWith(avatar: v),
        'about' => s.copyWith(about: v),
        _ => s.copyWith(groupInvites: v),
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: SettingsListView(
        children: [
          const SettingsSectionTitle('Qui voit quoi', first: true),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('privacy.presence'),
                leading: Icon(Icons.circle_outlined, color: p.accentText),
                title: const Text('En ligne et «\u202Fvu à\u202F»'),
                subtitle: Text(visibilityLabel(s.presence)),
                onTap: () => visibility('presence'),
              ),
              ListTile(
                key: const Key('privacy.avatar'),
                leading: Icon(Icons.account_circle_outlined, color: p.accentText),
                title: const Text('Photo de profil'),
                subtitle: Text(visibilityLabel(s.avatar)),
                onTap: () => visibility('avatar'),
              ),
              // Lot 7.1a : par défaut, seulement les contacts.
              ListTile(
                key: const Key('privacy.about'),
                leading: Icon(Icons.info_outline, color: p.accentText),
                title: const Text('À propos'),
                subtitle: Text(visibilityLabel(s.about)),
                onTap: () => visibility('about'),
              ),
              ListTile(
                key: const Key('privacy.invites'),
                leading: Icon(Icons.group_add_outlined, color: p.accentText),
                title: const Text('Qui peut m’inviter dans un groupe'),
                subtitle: Text(visibilityLabel(s.groupInvites)),
                onTap: () => visibility('invites'),
              ),
              const _ConnectionRequestsTile(),
            ],
          ),
          const SettingsNote(
            '«\u202FMes contacts\u202F»\u202F: les personnes avec qui vous êtes connecté (discussion à deux). '
            'Une personne bloquée ne voit jamais rien. Chaque discussion peut avoir ses propres '
            'réglages (fiche du contact ou du groupe).',
          ),
          const SettingsSectionTitle('Messages'),
          SettingsCard(
            children: [
              SwitchListTile(
                key: const Key('privacy.receipts'),
                value: s.readReceipts,
                secondary: Icon(Icons.done_all, color: p.accentText),
                title: const Text('Accusés de lecture'),
                subtitle: const Text(
                  'Si désactivés, on ne voit plus quand vous avez lu. Vous voyez toujours ceux '
                  'des autres.',
                ),
                onChanged: (v) => _save(context, ref, s.copyWith(readReceipts: v)),
              ),
              SwitchListTile(
                key: const Key('privacy.typing'),
                value: s.typing,
                secondary: Icon(Icons.keyboard_outlined, color: p.accentText),
                title: const Text('«\u202FEn train d’écrire\u202F»'),
                subtitle: const Text('Désactivé\u202F: personne ne voit quand vous écrivez.'),
                onChanged: (v) => _save(context, ref, s.copyWith(typing: v)),
              ),
              ListTile(
                key: const Key('privacy.ttl'),
                leading: Icon(Icons.timer_outlined, color: p.accentText),
                title: const Text('Durée par défaut des messages'),
                subtitle: Text(
                  '${formatTtl(s.defaultTtlSeconds ?? rules.maxTtlSeconds)} · nouvelles discussions',
                ),
                onTap: () => _pickTtl(context, ref, s),
              ),
            ],
          ),
          const SettingsNote(
            'Pour effacer une discussion entière\u202F: fiche du contact ou du groupe, '
            '«\u202FVider la discussion\u202F».',
          ),
          // Lot 7.3b : aperçus des liens, contenu des GIF (réglages de ce téléphone).
          const SettingsSectionTitle('Liens et GIF'),
          const _ContentSettings(),
          const SettingsNote(
            'L’aperçu d’un lien est préparé par le serveur Privio : votre téléphone ne '
            'contacte pas le site, et vos contacts non plus.',
          ),
          const SettingsSectionTitle('Sécurité'),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('privacy.lock'),
                leading: Icon(Icons.lock_outline, color: p.accentText),
                title: const Text('Verrouillage de l’application'),
                subtitle: Text(
                  (lock?.enabled ?? false)
                      ? 'Activé · ${delayLabel(lock!.config.delaySeconds).toLowerCase()}'
                      : 'Désactivé',
                ),
                onTap: () => context.push(Routes.appLock),
              ),
              ListTile(
                key: const Key('privacy.blocked'),
                leading: Icon(Icons.block, color: p.accentText),
                title: const Text('Personnes bloquées'),
                onTap: () => context.push(Routes.blockedUsers),
              ),
              ListTile(
                leading: Icon(Icons.screenshot_monitor_outlined, color: p.accentText),
                title: const Text('Captures d’écran'),
                subtitle: const Text('Toujours bloquées dans Privio (non modifiable).'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Qui peut m'envoyer une demande » (lot 4.7) : tout le monde ou personne.
class _ConnectionRequestsTile extends ConsumerWidget {
  const _ConnectionRequestsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final accept = ref.watch(acceptConnectionRequestsProvider);
    final value = accept.value ?? true;
    return SwitchListTile(
      key: const Key('privacy.requests'),
      value: value,
      secondary: Icon(Icons.person_add_alt_1_outlined, color: p.accentText),
      title: const Text('Demandes de connexion'),
      subtitle: Text(
        value
            ? 'Tout le monde peut vous envoyer une demande.'
            : 'Personne ne peut vous envoyer de demande.',
      ),
      onChanged: accept.isLoading
          ? null
          : (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(messagingApiProvider).setAcceptConnectionRequests(v);
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
              } finally {
                ref.invalidate(acceptConnectionRequestsProvider);
              }
            },
    );
  }
}

/// Lot 7.3b : aperçus des liens (activés par défaut) et contenu des GIF (tout public par
/// défaut). Réglages gardés sur ce téléphone.
class _ContentSettings extends ConsumerStatefulWidget {
  const _ContentSettings();

  @override
  ConsumerState<_ContentSettings> createState() => _ContentSettingsState();
}

class _ContentSettingsState extends ConsumerState<_ContentSettings> {
  bool? _previews;
  String? _gif;

  @override
  void initState() {
    super.initState();
    final flags = ref.read(localFlagsProvider);
    flags.linkPreviews().then((v) {
      if (mounted) setState(() => _previews = v);
    });
    flags.gifFilter().then((v) {
      if (mounted) setState(() => _gif = v);
    });
  }

  Future<void> _pickGif() async {
    final current = _gif ?? 'g';
    final next = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                key: Key('privacy.gif.g'),
                value: 'g',
                title: Text('Tout public'),
                subtitle: Text('Recommandé.'),
              ),
              RadioListTile<String>(
                key: Key('privacy.gif.pg13'),
                value: 'pg13',
                title: Text('Modéré'),
                subtitle: Text('Quelques contenus moins adaptés aux enfants.'),
              ),
            ],
          ),
        ),
      ),
    );
    if (next == null || next == current) return;
    await ref.read(localFlagsProvider).setGifFilter(next);
    if (mounted) setState(() => _gif = next);
  }

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    return SettingsCard(
      children: [
        SwitchListTile(
          key: const Key('privacy.link_previews'),
          value: _previews ?? true,
          secondary: Icon(Icons.link_rounded, color: p.accentText),
          title: const Text('Aperçus des liens'),
          subtitle: const Text('Titre et image des liens que vous envoyez.'),
          onChanged: _previews == null
              ? null
              : (v) async {
                  await ref.read(localFlagsProvider).setLinkPreviews(v);
                  if (mounted) setState(() => _previews = v);
                },
        ),
        ListTile(
          key: const Key('privacy.gif'),
          leading: Icon(Icons.gif_box_outlined, color: p.accentText),
          title: const Text('Contenu des GIF'),
          subtitle: Text((_gif ?? 'g') == 'pg13' ? 'Modéré' : 'Tout public'),
          onTap: _pickGif,
        ),
      ],
    );
  }
}
