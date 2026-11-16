import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../state/providers.dart';
import '../../core/emoji/big_emojis.dart';
import '../../core/motion/illustrations.dart';
import '../../core/motion/motion.dart';

/// Lot 8.5c — guide « Découvrir Privio » : les fonctions principales en 6 écrans illustrés
/// (icônes animées et émojis animés intégrés). Montré une fois après l'arrivée sur Privio
/// (comptes existants compris), puis dans Paramètres › Aide.
class DiscoverPage {
  const DiscoverPage({
    required this.title,
    required this.body,
    required this.icon,
    required this.emoji,
    required this.color,
    required this.around,
  });

  final String title;
  final String body;
  final IconData icon;
  final String emoji;
  final Color color;

  /// Petites icônes autour de l'illustration.
  final List<(IconData, IconMotion)> around;

  static List<DiscoverPage> get all => [
    DiscoverPage(
      title: L.t.discover1Title,
      body: L.t.discover1Body,
      icon: Icons.chat_bubble_outline_rounded,
      emoji: '👋',
      color: const Color(0xFF6A3FD0),
      around: const [
        (Icons.timer_outlined, IconMotion.vanish),
        (Icons.lock_outline, IconMotion.pulse),
      ],
    ),
    DiscoverPage(
      title: L.t.discover2Title,
      body: L.t.discover2Body,
      icon: Icons.person_add_alt_1_outlined,
      emoji: '🤝',
      color: const Color(0xFF138A6E),
      around: const [
        (Icons.qr_code_scanner_rounded, IconMotion.float),
        (Icons.alternate_email_rounded, IconMotion.pulse),
      ],
    ),
    DiscoverPage(
      title: L.t.discover3Title,
      body: L.t.discover3Body,
      icon: Icons.timer_outlined,
      emoji: '✨',
      color: const Color(0xFFB7700F),
      around: const [
        (Icons.auto_delete_outlined, IconMotion.vanish),
        (Icons.schedule_rounded, IconMotion.float),
      ],
    ),
    DiscoverPage(
      title: L.t.discover4Title,
      body: L.t.discover4Body,
      icon: Icons.groups_2_outlined,
      emoji: '🥳',
      color: const Color(0xFF2A73C9),
      around: const [
        (Icons.link_rounded, IconMotion.float),
        (Icons.shield_outlined, IconMotion.pulse),
      ],
    ),
    DiscoverPage(
      title: L.t.discover5Title,
      body: L.t.discover5Body,
      icon: Icons.call_outlined,
      emoji: '🤙',
      color: const Color(0xFF3E8B1A),
      around: const [
        (Icons.videocam_outlined, IconMotion.ring),
        (Icons.volume_up_outlined, IconMotion.pulse),
      ],
    ),
    DiscoverPage(
      title: L.t.discover6Title,
      body: L.t.discover6Body,
      icon: Icons.verified_user_outlined,
      emoji: '🙈',
      color: const Color(0xFFC0457A),
      around: const [
        (Icons.pin_outlined, IconMotion.pulse),
        (Icons.screenshot_monitor_outlined, IconMotion.vanish),
      ],
    ),
  ];
}

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Vu une fois suffit (même si on le quitte avant la fin).
    ref.read(localFlagsProvider).setDiscoverSeen();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _next(int count) async {
    if (_index >= count - 1) return _close();
    await _pages.nextPage(duration: Motion.of(context, Motion.slow), curve: Motion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = DiscoverPage.all;
    final last = _index == pages.length - 1;
    final color = pages[_index].color;
    return Scaffold(
      key: const Key('discover.screen'),
      body: AnimatedContainer(
        duration: Motion.of(context, Motion.slow),
        curve: Motion.enter,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.14),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: Motion.of(context, Motion.fast),
                  child: TextButton(
                    key: const Key('discover.skip'),
                    onPressed: last ? null : _close,
                    child: Text(L.t.discoverSkip),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  key: const Key('discover.pages'),
                  controller: _pages,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _Page(page: pages[i], key: Key('discover.page.$i')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.l),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      AnimatedContainer(
                        duration: Motion.of(context, Motion.medium),
                        curve: Motion.enter,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? color : theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.xl,
                  0,
                  PrivioSpacing.xl,
                  PrivioSpacing.xl,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('discover.next'),
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: () => _next(pages.length),
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      child: Text(last ? L.t.discoverStart : L.t.discoverNext, key: ValueKey(last)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({super.key, required this.page});

  final DiscoverPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = PrivioPalette.of(context).accentText;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppearIn(
                scale: 0.8,
                offset: const Offset(0, 0.08),
                child: _Illustration(page: page),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              AppearIn(
                delay: const Duration(milliseconds: 120),
                child: Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.brightness == Brightness.dark ? null : accent,
                  ),
                ),
              ),
              const SizedBox(height: PrivioSpacing.m),
              AppearIn(
                delay: const Duration(milliseconds: 220),
                child: Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Illustration : grand disque coloré avec l'icône de la fonction, un émoji animé posé
/// dessus, et deux petites icônes animées autour.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.page});

  final DiscoverPage page;

  @override
  Widget build(BuildContext context) {
    const box = 240.0;
    final c = page.color;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.12),
              border: Border.all(color: c.withValues(alpha: 0.25), width: 2),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            child: Icon(page.icon, size: 60, color: Colors.white),
          ),
          Positioned(
            right: 18,
            bottom: 14,
            child: LoopingEmoji(page.emoji, size: 76, key: const Key('discover.emoji')),
          ),
          for (final (i, (icon, motion)) in page.around.indexed)
            Positioned(
              left: i == 0 ? 0 : null,
              right: i == 1 ? 6 : null,
              top: i == 0 ? 36 : 4,
              child: FloatingIcon(icon: icon, size: 26, motion: motion, color: c),
            ),
        ],
      ),
    );
  }
}
