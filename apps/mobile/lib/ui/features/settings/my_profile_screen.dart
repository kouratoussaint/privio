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
      appBar: AppBar(title: const Text('Ma fiche')),
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
                  label: Text(
                    profile.avatarPath == null ? 'Ajouter une photo' : 'Changer la photo',
                  ),
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
          const SettingsSectionTitle('Profil'),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('my.name'),
                leading: Icon(Icons.badge_outlined, color: p.accentText),
                title: const Text('Nom'),
                subtitle: Text(profile.displayName),
                trailing: Icon(Icons.edit_outlined, color: secondary),
                onTap: () => editMyName(context, ref, profile.displayName),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('my.about'),
                leading: Icon(Icons.info_outline, color: p.accentText),
                title: const Text('À propos'),
                subtitle: Text(
                  (profile.about ?? '').isEmpty
                      ? 'Ajouter un court texte de présentation'
                      : profile.about!,
                ),
                trailing: Icon(Icons.edit_outlined, color: secondary),
                onTap: () => editMyAbout(context, ref, profile.about),
              ),
              const SettingsDivider(),
              ListTile(
                key: const Key('my.handle'),
                leading: Icon(Icons.alternate_email, color: p.accentText),
                title: const Text('Identifiant'),
                subtitle: Text('@${profile.handle} · ne peut pas être changé'),
              ),
              if (account.phoneE164 != null) ...[
                const SettingsDivider(),
                ListTile(
                  key: const Key('my.phone'),
                  leading: Icon(Icons.phone_outlined, color: p.accentText),
                  title: const Text('Numéro'),
                  subtitle: Text(PhoneNumber.format(account.phoneE164!)),
                ),
              ],
            ],
          ),
          const SettingsSectionTitle('Qui voit quoi'),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('my.privacy'),
                leading: Icon(Icons.shield_outlined, color: p.accentText),
                title: const Text('Confidentialité'),
                subtitle: const Text('Photo, À propos, en ligne… pour tous ou par discussion'),
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
    messenger.showSnackBar(successSnack('Nom enregistré.'));
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
    title: const Text('Votre nom'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vos contacts et les membres de vos groupes le voient. Les anciens messages '
          'd’événements de groupe gardent l’ancien nom.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.m),
        TextField(
          key: const Key('name.text'),
          controller: _text,
          maxLength: 40,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Votre nom'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _text,
        builder: (context, v, _) => FilledButton(
          key: const Key('name.save'),
          onPressed: v.text.trim().isEmpty ? null : () => Navigator.pop(context, v.text),
          child: const Text('Enregistrer'),
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
      successSnack(text.trim().isEmpty ? 'À propos retiré.' : 'À propos enregistré.'),
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
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            key: const Key('avatar.gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasAvatar)
            ListTile(
              key: const Key('avatar.remove'),
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Retirer la photo',
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
      successSnack(
        choice == 'remove' ? 'Photo de profil retirée.' : 'Photo de profil mise à jour.',
      ),
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
      title: const Text('À propos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Par exemple\u202F: «\u202FDisponible\u202F», «\u202FAu travail\u202F». Qui le voit se '
            'règle dans Confidentialité.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: PrivioSpacing.m),
          TextField(
            key: const Key('about.text'),
            controller: _text,
            maxLength: 140,
            maxLines: 3,
            minLines: 1,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Votre court texte'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('about.save'),
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
