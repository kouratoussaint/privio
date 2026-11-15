import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../core/util/time_format.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/session_controller.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/privacy_providers.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ttl_picker.dart';
import '../../../state/providers.dart';
import 'what_privio_keeps_screen.dart';

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
      title: L.t.dureeParDefautMessages,
      help: L.t.pourDiscussionsGroupesQueVous,
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
    final blockedCount = ref.watch(blockedUsersProvider).value?.length;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final rules = ref.watch(messagingRulesProvider).value ?? const MessagingRules();

    final s = privacy.value;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L.t.confidentialite)),
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
        'presence' => (L.t.statutLigneVu, L.t.quiVoitSiVousEtes, s.presence),
        'avatar' => (L.t.photoProfil, L.t.autresVoientVosInitialesPlace, s.avatar),
        'about' => (L.t.propos, L.t.votreCourtTextePresentationAffiche, s.about),
        _ => (L.t.invitationsDansGroupes, L.t.personnesNonAutoriseesNePeuvent, s.groupInvites),
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
      appBar: AppBar(title: Text(L.t.confidentialite)),
      body: SettingsListView(
        children: [
          // Lot 8.4c : ce que Privio garde.
          SettingsCard(
            children: [
              ListTile(
                key: const Key('privacy.keeps'),
                leading: Icon(Icons.inventory_2_outlined, color: p.accentText),
                title: Text(L.t.keepTitle),
                subtitle: Text(L.t.keepEntrySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(WhatPrivioKeepsScreen.route()),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.quiVoitQuoi),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('privacy.presence'),
                leading: Icon(Icons.circle_outlined, color: p.accentText),
                title: Text(L.t.ligneVu),
                subtitle: Text(visibilityLabel(s.presence)),
                onTap: () => visibility('presence'),
              ),
              ListTile(
                key: const Key('privacy.avatar'),
                leading: Icon(Icons.account_circle_outlined, color: p.accentText),
                title: Text(L.t.photoProfil),
                subtitle: Text(visibilityLabel(s.avatar)),
                onTap: () => visibility('avatar'),
              ),
              // Lot 7.1a : par défaut, seulement les contacts.
              ListTile(
                key: const Key('privacy.about'),
                leading: Icon(Icons.info_outline, color: p.accentText),
                title: Text(L.t.propos),
                subtitle: Text(visibilityLabel(s.about)),
                onTap: () => visibility('about'),
              ),
            ],
          ),
          SettingsNote(L.t.mesContactsPersonnesAvecQui),
          // Lot 8.3a : qui peut me trouver, m'écrire, m'inviter ; personnes bloquées.
          SettingsSectionTitle(L.t.privacyReachSection),
          SettingsCard(
            children: [
              const _DiscoverableTile(),
              const _ConnectionRequestsTile(),
              ListTile(
                key: const Key('privacy.invites'),
                leading: Icon(Icons.group_add_outlined, color: p.accentText),
                title: Text(L.t.quiPeutMInviterDans),
                subtitle: Text(visibilityLabel(s.groupInvites)),
                onTap: () => visibility('invites'),
              ),
              ListTile(
                key: const Key('privacy.blocked'),
                leading: Icon(Icons.block, color: p.accentText),
                title: Text(L.t.personnesBloquees),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (blockedCount != null)
                      Text(
                        '$blockedCount',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                    const SizedBox(width: PrivioSpacing.xs),
                    Icon(Icons.chevron_right, color: secondary),
                  ],
                ),
                onTap: () => context.push(Routes.blockedUsers),
              ),
            ],
          ),
          SettingsSectionTitle(L.t.messages),
          SettingsCard(
            children: [
              SwitchListTile(
                key: const Key('privacy.receipts'),
                value: s.readReceipts,
                secondary: Icon(Icons.done_all, color: p.accentText),
                title: Text(L.t.accusesLecture),
                subtitle: Text(L.t.siDesactivesOnNeVoit),
                onChanged: (v) => _save(context, ref, s.copyWith(readReceipts: v)),
              ),
              SwitchListTile(
                key: const Key('privacy.typing'),
                value: s.typing,
                secondary: Icon(Icons.keyboard_outlined, color: p.accentText),
                title: Text(L.t.trainEcrire2),
                subtitle: Text(L.t.desactivePersonneNeVoitQuand),
                onChanged: (v) => _save(context, ref, s.copyWith(typing: v)),
              ),
              ListTile(
                key: const Key('privacy.ttl'),
                leading: Icon(Icons.timer_outlined, color: p.accentText),
                title: Text(L.t.dureeParDefautMessages),
                subtitle: Text(
                  L.t.maxttlsecondsNouvellesDiscussions(
                    formatTtl(s.defaultTtlSeconds ?? rules.maxTtlSeconds),
                  ),
                ),
                onTap: () => _pickTtl(context, ref, s),
              ),
            ],
          ),
          SettingsNote(L.t.pourEffacerDiscussionEntiereFiche),
          // Lot 7.3b : aperçus des liens, contenu des GIF (réglages de ce téléphone).
          SettingsSectionTitle(L.t.liensGif),
          const _ContentSettings(),
          SettingsNote(L.t.apercuLienEstPreparePar),
        ],
      ),
    );
  }
}

/// Lot 8.3a (déplacé depuis Paramètres) : « Me trouver par mon numéro ».
class _DiscoverableTile extends ConsumerWidget {
  const _DiscoverableTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final handle = account?.profile?.handle;
    final on = account?.phoneDiscoverable ?? false;
    return SwitchListTile(
      key: const Key('settings.discoverable'),
      value: on,
      onChanged: account == null
          ? null
          : (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(sessionControllerProvider.notifier).setPhoneDiscoverable(v);
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
              }
            },
      secondary: Icon(Icons.phone_outlined, color: p.accentText),
      title: Text(L.t.meTrouverParMonNumero),
      subtitle: Text(
        on
            ? L.t.activeOnPeutAussiVous
            : handle == null
            ? L.t.desactiveOnVousTrouveSeulement
            : L.t.desactiveOnVousTrouveSeulement2(handle),
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
      title: Text(L.t.demandesConnexion),
      subtitle: Text(value ? L.t.toutMondePeutVousEnvoyer : L.t.personneNePeutVousEnvoyer),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                key: const Key('privacy.gif.g'),
                value: 'g',
                title: Text(L.t.toutPublic),
                subtitle: Text(L.t.recommande),
              ),
              RadioListTile<String>(
                key: const Key('privacy.gif.pg13'),
                value: 'pg13',
                title: Text(L.t.modere),
                subtitle: Text(L.t.quelquesContenusMoinsAdaptesEnfants),
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
          title: Text(L.t.apercusLiens),
          subtitle: Text(L.t.titreImageLiensQueVous),
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
          title: Text(L.t.contenuGif),
          subtitle: Text((_gif ?? 'g') == 'pg13' ? L.t.modere : L.t.toutPublic),
          onTap: _pickGif,
        ),
      ],
    );
  }
}
