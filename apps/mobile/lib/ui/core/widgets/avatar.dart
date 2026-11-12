import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../state/messaging_providers.dart';

/// Pastille d'initiales colorée, stable par personne (sans photo de profil).
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.seed, this.radius = 26, this.ring});

  final String name;
  final String? seed;
  final double radius;
  final Color? ring;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: PrivioPalette.avatarFor(seed ?? name),
      foregroundColor: Colors.white,
      child: Text(
        initials(name),
        style: TextStyle(fontSize: radius * 0.68, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
    return ExcludeSemantics(
      child: ring == null
          ? avatar
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring!, width: 2),
              ),
              child: avatar,
            ),
    );
  }
}

/// Photo de profil si la personne en a une (téléchargée avec le jeton, gardée chiffrée),
/// sinon, ou en attendant, ses initiales.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.seed,
    this.radius = 26,
    this.ring,
  });

  final String name;
  final String? avatarPath;
  final String? seed;
  final double radius;
  final Color? ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = avatarPath;
    final fallback = InitialAvatar(name: name, seed: seed, radius: radius, ring: ring);
    if (path == null) return fallback;
    final bytes = ref.watch(avatarBytesProvider(path)).value;
    if (bytes == null) return fallback;
    final photo = CircleAvatar(
      key: Key('avatar.photo.$path'),
      radius: radius,
      backgroundColor: PrivioPalette.avatarFor(seed ?? name),
      backgroundImage: ResizeImage(
        MemoryImage(bytes),
        width: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
    return ExcludeSemantics(
      child: ring == null
          ? photo
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring!, width: 2),
              ),
              child: photo,
            ),
    );
  }
}
