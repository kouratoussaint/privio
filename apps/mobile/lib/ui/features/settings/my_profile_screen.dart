import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/services/photo_picker.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import '../conversations/conversation_details.dart' show FicheAvatar;
import '../../core/widgets/success_snack.dart';
import '../../../state/feedback_providers.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/handle/handle_rules.dart';
import 'change_phone_screen.dart';

/// Lot 7.2a — « Ma fiche » (Paramètres → ligne du profil) : comme la fiche d'un contact,
/// mais modifiable : photo (prendre, choisir, retirer, voir en grand), nom, À propos.
/// L'@identifiant et le numéro ne se changent pas ici.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final account = ref.watch(sessionControllerProvider).value?.account;
    final profile = account?.profile;
    if (account == null || profile == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(L.t.maFiche)),
      body: SettingsListView(
        children: [
          SettingsCard(
            padding: const EdgeInsets.all(PrivioSpacing.l),
            children: [
              FicheAvatar(
                name: profile.displayName,
                path: profile.avatarPath,
                seed: account.userId,
                onEdit: () => editMyAvatar(context, ref, hasAvatar: profile.avatarPath != null),
              ),
              const SizedBox(height: PrivioSpacing.s),
              Center(
                child: TextButton.icon(
                  key: const Key('my.photo'),
                  onPressed: () =>
                      editMyAvatar(context, ref, hasAvatar: profile.avatarPath != null),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(profile.avatarPath == null ? L.t.ajouterPhoto : L.t.changerPhoto),
                ),
              ),
              Text(
                profile.displayName,
                key: const Key('my.title'),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              Text(
                '@${profile.handle}',
                style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          SettingsSectionTitle(L.t.profil),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('my.name'),
                leading: Icon(Icons.badge_outlined, color: p.accentText),
                title: Text(L.t.nom),
                subtitle: Text(profile.displayName),
                trailing: Icon(Icons.edit_outlined, color: secondary),
                onTap: () => editMyName(context, ref, profile.displayName),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('my.about'),
                leading: Icon(Icons.info_outline, color: p.accentText),
                title: Text(L.t.propos),
                subtitle: Text(
                  (profile.about ?? '').isEmpty
                      ? L.t.ajouterCourtTextePresentation
                      : profile.about!,
                ),
                trailing: Icon(Icons.edit_outlined, color: secondary),
                onTap: () => editMyAbout(context, ref, profile.about),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('my.handle'),
                leading: Icon(Icons.alternate_email, color: p.accentText),
                title: Text(L.t.identifiant),
                subtitle: Text(L.t.handleNePeutPasEtre(profile.handle)),
              ),
              const SettingsDivider(),
              // Lot 8.1a : QR code de l'identifiant, à faire scanner dans Privio.
              ListTile(
                key: const Key('my.qr'),
                leading: Icon(Icons.qr_code_2_rounded, color: p.accentText),
                title: Text(L.t.monQrCode),
                subtitle: Text(L.t.faireScannerDansPrivioPour),
                trailing: Icon(Icons.chevron_right, color: secondary),
                onTap: () =>
                    showMyQrCode(context, handle: profile.handle, name: profile.displayName),
              ),
              if (account.phoneE164 != null) ...[
                const SettingsDivider(),
                // Lot 8.1c : changer de numéro.
                ListTile(
                  key: const Key('my.phone'),
                  leading: Icon(Icons.phone_outlined, color: p.accentText),
                  title: Text(L.t.numero),
                  subtitle: Text(PhoneNumber.format(account.phoneE164!)),
                  trailing: Text(
                    L.t.changer,
                    style: theme.textTheme.labelLarge?.copyWith(color: p.accentText),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => ChangePhoneScreen(currentPhone: account.phoneE164),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SettingsSectionTitle(L.t.quiVoitQuoi),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('my.privacy'),
                leading: Icon(Icons.shield_outlined, color: p.accentText),
                title: Text(L.t.confidentialite),
                subtitle: Text(L.t.photoProposLignePourTous),
                trailing: Icon(Icons.chevron_right, color: secondary),
                onTap: () => context.push(Routes.privacy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nom affiché : 1 à 40 caractères ; visible par vos contacts et dans vos groupes.
Future<void> editMyName(BuildContext context, WidgetRef ref, String current) async {
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(initial: current),
  );
  if (text == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(accountApiProvider).setDisplayName(text);
    await ref.read(sessionControllerProvider.notifier).refreshAccount();
    ref.read(feedbackProvider).sound(PrivioSound.success);
    messenger.showSnackBar(successSnack(L.t.nomEnregistre));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('name.dialog'),
    title: Text(L.t.votreNom),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L.t.vosContactsMembresVosGroupes, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: PrivioSpacing.m),
        TextField(
          key: const Key('name.text'),
          controller: _text,
          maxLength: 40,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: L.t.votreNom),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t.annuler)),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _text,
        builder: (context, v, _) => FilledButton(
          key: const Key('name.save'),
          onPressed: v.text.trim().isEmpty ? null : () => Navigator.pop(context, v.text),
          child: Text(L.t.enregistrer),
        ),
      ),
    ],
  );
}

/// « À propos » : 140 caractères au plus, vide pour le retirer.
Future<void> editMyAbout(BuildContext context, WidgetRef ref, String? current) async {
  final text = await showDialog<String>(
    context: context,
    builder: (_) => AboutDialogBox(initial: current ?? ''),
  );
  if (text == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(accountApiProvider).setAbout(text);
    await ref.read(sessionControllerProvider.notifier).refreshAccount();
    messenger.showSnackBar(
      successSnack(text.trim().isEmpty ? L.t.proposRetire : L.t.proposEnregistre),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

/// Photo de profil : prendre, choisir ou retirer. Préparée sur le téléphone (carrée,
/// sans métadonnées), vérifiée et nettoyée encore par le serveur.
Future<void> editMyAvatar(BuildContext context, WidgetRef ref, {required bool hasAvatar}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('avatar.camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(L.t.prendrePhoto),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            key: const Key('avatar.gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(L.t.choisirDansGalerie),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasAvatar)
            ListTile(
              key: const Key('avatar.remove'),
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                L.t.retirerPhoto,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final api = ref.read(accountApiProvider);
    if (choice == 'remove') {
      await api.removeAvatar();
    } else {
      final source = choice == 'camera' ? PhotoSource.camera : PhotoSource.gallery;
      final raw = await ref
          .read(appLockProvider.notifier)
          .runExternal(() => ref.read(photoPickerProvider).pick(source));
      if (raw == null) return;
      final photo = await ref.read(photoPreparerProvider)(raw, avatar: true);
      await api.setAvatar(photo.bytes);
      countDataW(ref, sent: photo.bytes.length);
    }
    await ref.read(sessionControllerProvider.notifier).refreshAccount();
    ref.read(feedbackProvider).sound(PrivioSound.success);
    messenger.showSnackBar(
      successSnack(choice == 'remove' ? L.t.photoProfilRetiree : L.t.photoProfilMiseJour),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
  }
}

class AboutDialogBox extends StatefulWidget {
  const AboutDialogBox({super.key, required this.initial});

  final String initial;

  @override
  State<AboutDialogBox> createState() => AboutDialogBoxState();
}

class AboutDialogBoxState extends State<AboutDialogBox> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('about.dialog'),
      title: Text(L.t.propos),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.t.parExempleDisponibleTravailQui, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: PrivioSpacing.m),
          TextField(
            key: const Key('about.text'),
            controller: _text,
            maxLength: 140,
            maxLines: 3,
            minLines: 1,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: L.t.votreCourtTexte),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t.annuler)),
        FilledButton(
          key: const Key('about.save'),
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(L.t.enregistrer),
        ),
      ],
    );
  }
}

/// Lot 8.1a : mon QR code (identifiant). Lisible seulement dans Privio :
/// Nouvelle discussion → Scanner.
Future<void> showMyQrCode(
  BuildContext context, {
  required String handle,
  required String name,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) {
    final theme = Theme.of(ctx);
    return SafeArea(
      child: Padding(
        key: const Key('my.qr.sheet'),
        padding: const EdgeInsets.fromLTRB(PrivioSpacing.xl, 0, PrivioSpacing.xl, PrivioSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: theme.textTheme.titleLarge),
            Text(
              '@$handle',
              style: theme.textTheme.bodyMedium?.copyWith(color: PrivioPalette.of(ctx).accentText),
            ),
            const SizedBox(height: PrivioSpacing.l),
            Container(
              padding: const EdgeInsets.all(PrivioSpacing.m),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(PrivioRadius.large),
              ),
              child: QrImageView(
                key: const Key('my.qr.code'),
                data: profileQrData(handle),
                size: 220,
                backgroundColor: Colors.white,
                semanticsLabel: L.t.monQrCodePrivio,
              ),
            ),
            const SizedBox(height: PrivioSpacing.l),
            Text(
              L.t.pourVousTrouverPersonneOuvre,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  },
);
