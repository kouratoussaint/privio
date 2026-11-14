import 'package:flutter/material.dart';

import '../motion/illustrations.dart';

/// Lot 7.2b2 : message de réussite, précédé d'une coche qui se dessine. Le son de réussite
/// est joué par l'écran appelant (`feedbackProvider`).
SnackBar successSnack(String text, {Key? key}) => SnackBar(
  key: key,
  content: Row(
    children: [
      const SuccessCheck(size: 20, color: Colors.white),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  ),
);
