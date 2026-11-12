import 'package:flutter/material.dart';

import '../../../core/theme/privio_palette.dart';

/// Pastille d'initiales colorée, stable par personne (les photos arrivent au lot 3.2).
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
