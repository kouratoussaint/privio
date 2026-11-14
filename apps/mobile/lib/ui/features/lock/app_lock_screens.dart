import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../data/storage/app_lock_store.dart';
import '../../../router/routes.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/privio_brand.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/settings_card.dart';

// ---------------------------------------------------------------------------
// Pavé numérique (sans champ texte : aucun clavier, aucune suggestion, aucun presse-papiers)
// ---------------------------------------------------------------------------
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.onDigit,
    required this.onDelete,
    this.enabled = true,
    this.extra,
  });

  final int length;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  /// Bouton en bas à gauche (empreinte), facultatif.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String d) => _PadButton(
      key: Key('pin.$d'),
      label: d,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onDigit(d);
            }
          : null,
      child: Text(d, style: theme.textTheme.headlineSmall),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 80, height: 72, child: extra),
            key('0'),
            _PadButton(
              key: const Key('pin.delete'),
              label: 'Effacer',
              onTap: enabled && length > 0 ? onDelete : null,
              child: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 80,
    height: 72,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Center(child: child),
      ),
    ),
  );
}

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = PrivioPalette.of(context);
    final c = error ? Theme.of(context).colorScheme.error : p.accentText;
    return Semantics(
      label: '$filled chiffre${filled > 1 ? 's' : ''} sur $kPinLength',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kPinLength; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? c : Colors.transparent,
                border: Border.all(color: c, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Saisie d'un code complet : appelle [onComplete] dès le 6e chiffre.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    required this.onComplete,
    this.message,
    this.error = false,
    this.enabled = true,
    this.extra,
  });

  final String title;
  final String? message;
  final bool error;
  final bool enabled;
  final Widget? extra;

  /// Renvoie vrai si la saisie doit être effacée (code refusé, étape suivante).
  final Future<void> Function(String pin) onComplete;

  @override
  State<PinEntry> createState() => PinEntryState();
}

class PinEntryState extends State<PinEntry> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  Future<void> _digit(String d) async {
    if (_busy || _pin.length >= kPinLength) return;
    setState(() => _pin += d);
    if (_pin.length < kPinLength) return;
    setState(() => _busy = true);
    try {
      await widget.onComplete(_pin);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.l),
        PinDots(filled: _pin.length, error: widget.error),
        SizedBox(
          height: 48,
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.message ?? '',
                    key: const Key('pin.message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: widget.error
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        PinPad(
          length: _pin.length,
          enabled: widget.enabled && !_busy,
          onDigit: _digit,
          onDelete: () => setState(() => _pin = _pin.substring(0, _pin.length - 1)),
          extra: widget.extra,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Garde : recouvre toute l'application tant qu'elle est verrouillée
// ---------------------------------------------------------------------------
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  late final AppLifecycleListener _lifecycle;

  /// L'écran de verrouillage est au-dessus du navigateur : il a sa propre couche
  /// (infobulles, menus) — toujours présente, vide quand l'application est ouverte.
  late final OverlayEntry _lockLayer = OverlayEntry(
    builder: (_) => Consumer(
      builder: (_, ref, _) => (ref.watch(appLockProvider).value?.locked ?? false)
          ? const LockScreen()
          : const SizedBox.shrink(),
    ),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(appLockProvider.notifier).onBackground(),
      onShow: () => ref.read(appLockProvider.notifier).onForeground(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    // Tant que les réglages ne sont pas lus, rien n'est montré (pas d'aperçu furtif).
    final covered = switch (lock) {
      AsyncData(:final value) => value.locked,
      AsyncError() => false,
      _ => true,
    };
    final showLock = lock.value?.locked ?? false;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: covered,
          child: TickerMode(
            enabled: !covered,
            child: ExcludeSemantics(excluding: covered, child: widget.child),
          ),
        ),
        Overlay(initialEntries: [_lockLayer]),
        if (covered && !showLock) ColoredBox(color: Theme.of(context).colorScheme.surface),
      ],
    );
  }
}

/// Écran de déverrouillage (au-dessus du navigateur : pas de boîte de dialogue ici).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;
  bool _error = false;
  bool _forgot = false;
  Timer? _tick;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    // Décompte de l'attente, et réactivation du pavé quand elle se termine.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final waiting = ref.read(appLockProvider.notifier).waitUntil != null;
      if (waiting || _waiting) setState(() {});
      _waiting = waiting;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics(auto: true));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _biometrics({bool auto = false}) async {
    final s = ref.read(appLockProvider).value;
    if (s == null || !s.config.biometrics || !s.biometricsAvailable) return;
    if (auto && ref.read(appLockProvider.notifier).waitUntil != null) return;
    final ok = await ref.read(appLockProvider.notifier).unlockWithBiometrics();
    if (!ok && !auto && mounted) {
      setState(() {
        _message = 'Empreinte non reconnue. Saisissez votre code.';
        _error = true;
      });
    }
  }

  Future<void> _submit(String pin) async {
    final r = await ref.read(appLockProvider.notifier).unlock(pin);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case Unlocked():
          _message = null;
          _error = false;
        case WrongPin(:final remainingBeforeWait):
          _error = true;
          _message = remainingBeforeWait <= 2
              ? 'Code incorrect. Encore $remainingBeforeWait essai${remainingBeforeWait > 1 ? 's' : ''} avant une attente.'
              : 'Code incorrect.';
        case MustWait():
          _error = true;
          _message = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(appLockProvider).value;
    final wait = ref.read(appLockProvider.notifier).waitUntil;
    final remaining = wait?.difference(ref.read(lockClockProvider)());
    final bio = (s?.config.biometrics ?? false) && (s?.biometricsAvailable ?? false);

    return Scaffold(
      key: const Key('lock.screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PrivioSpacing.xl),
            child: _forgot
                ? _ForgotPanel(onCancel: () => setState(() => _forgot = false))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PrivioSymbol(size: 64),
                      const SizedBox(height: PrivioSpacing.l),
                      PinEntry(
                        title: 'Saisissez votre code Privio',
                        error: _error,
                        enabled: wait == null,
                        message: wait != null
                            ? 'Trop d’essais. Réessayez dans ${formatWait(remaining!)}.'
                            : _message,
                        onComplete: _submit,
                        extra: bio
                            ? IconButton(
                                key: const Key('lock.biometrics'),
                                tooltip: 'Utiliser l’empreinte',
                                iconSize: 32,
                                onPressed: wait == null ? _biometrics : null,
                                icon: const Icon(Icons.fingerprint),
                              )
                            : null,
                      ),
                      const SizedBox(height: PrivioSpacing.m),
                      TextButton(
                        key: const Key('lock.forgot'),
                        onPressed: () => setState(() => _forgot = true),
                        child: const Text('Code oublié\u202F?'),
                      ),
                      Text(
                        'Le contenu de Privio reste masqué tant que l’application est verrouillée.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ForgotPanel extends ConsumerStatefulWidget {
  const _ForgotPanel({required this.onCancel});

  final VoidCallback onCancel;

  @override
  ConsumerState<_ForgotPanel> createState() => _ForgotPanelState();
}

class _ForgotPanelState extends ConsumerState<_ForgotPanel> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('lock.forgot.panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_reset, size: 48, color: PrivioPalette.of(context).accentText),
        const SizedBox(height: PrivioSpacing.l),
        Text('Code oublié', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.m),
        const Text(
          'Pour des raisons de sécurité, le code ne peut pas être retrouvé. '
          'Vous pouvez vous déconnecter\u202F: les messages gardés sur ce téléphone seront effacés, '
          'puis vous vous reconnecterez avec votre numéro et le code reçu par SMS. '
          'Vos discussions encore actives réapparaîtront.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          key: const Key('lock.forgot.signout'),
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          onPressed: _busy ? null : _signOut,
          child: const Text('Se déconnecter et effacer ce téléphone'),
        ),
        TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Annuler')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 23 (partie) — réglages du verrouillage
// ---------------------------------------------------------------------------
String delayLabel(int seconds) => switch (seconds) {
  0 => 'Immédiatement',
  60 => 'Après 1 minute',
  300 => 'Après 5 minutes',
  1800 => 'Après 30 minutes',
  _ => 'Après ${seconds ~/ 60} min',
};

class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  Future<void> _chooseDelay(BuildContext context, WidgetRef ref, int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in AppLockConfig.delays)
                RadioListTile<int>(key: Key('lock.delay.$d'), value: d, title: Text(delayLabel(d))),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await ref.read(appLockProvider.notifier).setDelay(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final lock = ref.watch(appLockProvider);
    final s = lock.value;
    if (s == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('Verrouillage')),
      body: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.xs,
              0,
              PrivioSpacing.xs,
              PrivioSpacing.l,
            ),
            child: Text(
              'Un code à $kPinLength chiffres, propre à Privio, est demandé à l’ouverture de '
              'l’application. Il protège vos messages si quelqu’un utilise votre téléphone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SettingsCard(
            children: [
              SwitchListTile(
                key: const Key('lock.enabled'),
                value: s.enabled,
                secondary: Icon(Icons.lock_outline, color: p.accentText),
                title: const Text('Verrouiller Privio'),
                onChanged: (v) =>
                    v ? context.push(Routes.appLockNew) : context.push(Routes.appLockDisable),
              ),
              if (s.enabled) ...[
                ListTile(
                  key: const Key('lock.delay'),
                  leading: Icon(Icons.timer_outlined, color: p.accentText),
                  title: const Text('Redemander le code'),
                  subtitle: Text(delayLabel(s.config.delaySeconds)),
                  onTap: () => _chooseDelay(context, ref, s.config.delaySeconds),
                ),
                if (s.biometricsAvailable)
                  SwitchListTile(
                    key: const Key('lock.use_biometrics'),
                    value: s.config.biometrics,
                    secondary: Icon(Icons.fingerprint, color: p.accentText),
                    title: const Text('Déverrouiller avec l’empreinte'),
                    subtitle: const Text('Le code reste toujours accepté'),
                    onChanged: (v) => ref.read(appLockProvider.notifier).setBiometrics(v),
                  ),
                ListTile(
                  key: const Key('lock.change'),
                  leading: Icon(Icons.password, color: p.accentText),
                  title: const Text('Changer le code'),
                  onTap: () => context.push(Routes.appLockChange),
                ),
              ],
            ],
          ),
          const SettingsNote(
            'Code oublié\u202F: il faudra vous déconnecter, ce qui efface les messages gardés sur '
            'ce téléphone. Les captures d’écran restent bloquées dans tous les cas.',
          ),
        ],
      ),
    );
  }
}

/// Création, changement ou désactivation du code.
enum PinFlow { create, change, disable }

class PinFlowScreen extends ConsumerStatefulWidget {
  const PinFlowScreen({super.key, required this.flow});

  final PinFlow flow;

  @override
  ConsumerState<PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends ConsumerState<PinFlowScreen> {
  /// Étapes : 'current' (code actuel), 'new', 'confirm'.
  late String _step = widget.flow == PinFlow.create ? 'new' : 'current';
  String? _first;
  String? _message;
  bool _error = false;

  String get _title => switch (_step) {
    'current' => 'Code actuel',
    'new' =>
      widget.flow == PinFlow.change ? 'Nouveau code' : 'Choisissez un code à $kPinLength chiffres',
    _ => 'Confirmez le code',
  };

  bool _weak(String pin) {
    if (pin.split('').toSet().length == 1) return true; // 000000, 111111…
    const asc = '0123456789012345';
    const desc = '9876543210987654';
    return asc.contains(pin) || desc.contains(pin);
  }

  Future<void> _done(String pin) async {
    final lock = ref.read(appLockProvider.notifier);
    switch (_step) {
      case 'current':
        final r = await lock.verify(pin);
        if (!mounted) return;
        switch (r) {
          case Unlocked():
            if (widget.flow == PinFlow.disable) {
              await lock.disable();
              if (mounted) context.pop();
              return;
            }
            setState(() {
              _step = 'new';
              _message = null;
              _error = false;
            });
          case WrongPin():
            setState(() {
              _message = 'Code incorrect.';
              _error = true;
            });
          case MustWait(:final until):
            setState(() {
              _message =
                  'Trop d’essais. Réessayez dans ${formatWait(until.difference(DateTime.now()))}.';
              _error = true;
            });
        }
      case 'new':
        if (_weak(pin)) {
          setState(() {
            _message = 'Code trop simple (suite ou chiffres identiques). Choisissez-en un autre.';
            _error = true;
          });
          return;
        }
        setState(() {
          _first = pin;
          _step = 'confirm';
          _message = null;
          _error = false;
        });
      default:
        if (pin != _first) {
          setState(() {
            _step = 'new';
            _first = null;
            _message = 'Les deux codes ne correspondent pas. Recommencez.';
            _error = true;
          });
          return;
        }
        if (widget.flow == PinFlow.create) {
          await lock.enable(pin);
        } else {
          await lock.changePin(pin);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.flow == PinFlow.create ? 'Verrouillage activé.' : 'Code modifié.'),
          ),
        );
        context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.flow) {
        PinFlow.create => 'Créer un code',
        PinFlow.change => 'Changer le code',
        PinFlow.disable => 'Désactiver le verrouillage',
      }),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        child: PinEntry(
          key: ValueKey(_step),
          title: _title,
          message:
              _message ??
              (_step == 'new' ? 'Évitez votre date de naissance ou une suite simple.' : null),
          error: _error,
          onComplete: _done,
        ),
      ),
    ),
  );
}
