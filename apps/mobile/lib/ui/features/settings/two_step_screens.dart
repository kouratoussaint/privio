import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/account.dart';
import '../../../state/app_lock_providers.dart' show formatWait;
import '../../../state/feedback_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/settings_card.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/success_snack.dart';
import '../lock/app_lock_screens.dart' show PinEntry;

/// Lot 8.4a — vérification en deux étapes (ADR-033) : un « code de sécurité » à 6 chiffres,
/// demandé en plus du SMS sur un nouveau téléphone et pour changer de numéro.

/// État de la vérification pour cette session (relu à chaque ouverture des réglages).
final twoStepStateProvider = FutureProvider.autoDispose<TwoStepState>(
  (ref) => ref.watch(accountApiProvider).twoStepState(),
);

/// Même règle que le serveur : pas de chiffre répété, pas de suite.
bool weakTwoStepPin(String pin) {
  if (pin.split('').toSet().length == 1) return true;
  const asc = '0123456789012345';
  const desc = '9876543210987654';
  return asc.contains(pin) || desc.contains(pin);
}

/// Message d'un code refusé (faux, ou trop d'essais).
String twoStepRefusal(TwoStepCheck r) {
  final until = r.retryAt;
  if (until != null && until.isAfter(DateTime.now())) {
    return L.t.tropEssaisReessayezDansNow(formatWait(until.difference(DateTime.now())));
  }
  return L.t.codeIncorrect;
}

// ---------------------------------------------------------------------------
// Après le SMS : saisie du code (compte protégé)
// ---------------------------------------------------------------------------
class TwoStepVerifyScreen extends ConsumerStatefulWidget {
  const TwoStepVerifyScreen({super.key});

  @override
  ConsumerState<TwoStepVerifyScreen> createState() => _TwoStepVerifyScreenState();
}

class _TwoStepVerifyScreenState extends ConsumerState<TwoStepVerifyScreen> {
  String? _message;
  bool _error = false;
  int _shake = 0;
  DateTime? _resetAt;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _resetAt = ref.read(sessionControllerProvider).value?.twoStep?.resetRequestedAt;
    if (_resetAt != null) _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Demande envoyée : on regarde régulièrement si l'assistance a réinitialisé.
  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      await ref.read(sessionControllerProvider.notifier).refreshTwoStep();
    } on Object {
      // Hors connexion : nouvel essai au prochain tour.
    }
  }

  Future<void> _done(String pin) async {
    try {
      final r = await ref.read(sessionControllerProvider.notifier).verifyTwoStep(pin);
      if (!mounted || r.ok) return;
      setState(() {
        _message = twoStepRefusal(r);
        _error = true;
        _shake++;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _message = toAppFailure(e).message;
          _error = true;
        });
      }
    }
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t.twoStepForgotTitle),
        content: Text(L.t.twoStepForgotBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t.annuler)),
          FilledButton(
            key: const Key('two_step.reset.confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t.envoyerDemande),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final at = await ref.read(accountApiProvider).requestTwoStepReset();
      if (!mounted) return;
      setState(() => _resetAt = at);
      _startPolling();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(toAppFailure(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resetAt = _resetAt?.toLocal();
    return Scaffold(
      appBar: AppBar(title: Text(L.t.twoStepTitle), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PrivioSpacing.xl),
            child: Column(
              children: [
                Text(
                  L.t.twoStepVerifyIntro,
                  key: const Key('two_step.intro'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: PrivioSpacing.l),
                PinEntry(
                  title: L.t.codeSecurite,
                  message: _message,
                  error: _error,
                  shake: _shake,
                  onComplete: _done,
                ),
                const SizedBox(height: PrivioSpacing.m),
                if (resetAt == null)
                  TextButton(
                    key: const Key('two_step.forgot'),
                    onPressed: _forgot,
                    child: Text(L.t.codeOublie),
                  )
                else ...[
                  Text(
                    L.t.twoStepResetRequested(
                      MaterialLocalizations.of(context).formatShortDate(resetAt),
                    ),
                    key: const Key('two_step.reset.sent'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  TextButton(
                    key: const Key('two_step.refresh'),
                    onPressed: _refresh,
                    child: Text(L.t.verifierMaintenant),
                  ),
                ],
                TextButton(
                  key: const Key('two_step.signout'),
                  onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
                  child: Text(L.t.twoStepOtherNumber),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Réglages : Paramètres → Sécurité → Vérification en deux étapes
// ---------------------------------------------------------------------------
class TwoStepSettingsScreen extends ConsumerWidget {
  const TwoStepSettingsScreen({super.key});

  Future<void> _flow(BuildContext context, WidgetRef ref, TwoStepFlow flow) async {
    final done = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => TwoStepPinScreen(flow: flow)));
    ref.invalidate(twoStepStateProvider);
    if (done != true || !context.mounted) return;
    ref.read(feedbackProvider).sound(PrivioSound.success);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        successSnack(switch (flow) {
          TwoStepFlow.enable => L.t.twoStepEnabledDone,
          TwoStepFlow.change => L.t.twoStepChangedDone,
          TwoStepFlow.disable => L.t.twoStepDisabledDone,
          TwoStepFlow.phoneChange => '',
        }),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PrivioPalette.of(context);
    final state = ref.watch(twoStepStateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L.t.twoStepTitle)),
      body: switch (state) {
        AsyncData(:final value) => SettingsListView(
          children: [
            const SizedBox(height: PrivioSpacing.s),
            SettingsCard(
              children: [
                ListTile(
                  key: const Key('two_step.status'),
                  leading: Icon(Icons.verified_user_outlined, color: p.accentText),
                  title: Text(L.t.twoStepTitle),
                  subtitle: Text(value.enabled ? L.t.twoStepOn : L.t.twoStepOff),
                ),
              ],
            ),
            SettingsNote(L.t.twoStepIntro),
            const SizedBox(height: PrivioSpacing.l),
            if (!value.enabled)
              FilledButton(
                key: const Key('two_step.enable'),
                onPressed: () => _flow(context, ref, TwoStepFlow.enable),
                child: Text(L.t.activer),
              )
            else
              SettingsCard(
                children: [
                  ListTile(
                    key: const Key('two_step.change'),
                    leading: Icon(Icons.password_rounded, color: p.accentText),
                    title: Text(L.t.twoStepChange),
                    onTap: () => _flow(context, ref, TwoStepFlow.change),
                  ),
                  const SettingsDivider(),
                  ListTile(
                    key: const Key('two_step.disable'),
                    leading: Icon(Icons.remove_moderator_outlined, color: p.accentText),
                    title: Text(L.t.desactiver),
                    onTap: () => _flow(context, ref, TwoStepFlow.disable),
                  ),
                ],
              ),
            SettingsNote(L.t.twoStepHint),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          message: toAppFailure(error).message,
          onRetry: () => ref.invalidate(twoStepStateProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

enum TwoStepFlow { enable, change, disable, phoneChange }

/// Saisie du code : activer (nouveau, confirmation), changer (actuel, nouveau,
/// confirmation), désactiver ou autoriser un changement de numéro (code actuel).
/// Renvoie `true` (pop) une fois l'opération faite.
class TwoStepPinScreen extends ConsumerStatefulWidget {
  const TwoStepPinScreen({super.key, required this.flow});

  final TwoStepFlow flow;

  @override
  ConsumerState<TwoStepPinScreen> createState() => _TwoStepPinScreenState();
}

class _TwoStepPinScreenState extends ConsumerState<TwoStepPinScreen> {
  late String _step = widget.flow == TwoStepFlow.enable ? 'new' : 'current';
  String? _current;
  String? _first;
  String? _message;
  bool _error = false;
  int _shake = 0;

  String get _title => switch (_step) {
    'current' => L.t.codeSecuriteActuel,
    'new' => L.t.choisissezCodeKpinlengthChiffres(6),
    _ => L.t.confirmezCode,
  };

  void _fail(String message) => setState(() {
    _message = message;
    _error = true;
    _shake++;
  });

  Future<void> _done(String pin) async {
    final api = ref.read(accountApiProvider);
    try {
      switch (_step) {
        case 'current':
          switch (widget.flow) {
            case TwoStepFlow.disable:
              final r = await api.disableTwoStep(pin);
              if (!mounted) return;
              if (!r.ok) return _fail(twoStepRefusal(r));
              Navigator.of(context).pop(true);
            case TwoStepFlow.phoneChange:
              final r = await api.authorizePhoneChange(pin);
              if (!mounted) return;
              if (!r.ok) return _fail(twoStepRefusal(r));
              Navigator.of(context).pop(true);
            case TwoStepFlow.change:
            case TwoStepFlow.enable:
              setState(() {
                _current = pin;
                _step = 'new';
                _message = null;
                _error = false;
              });
          }
        case 'new':
          if (weakTwoStepPin(pin)) return _fail(L.t.codeTropSimpleSuiteOu);
          setState(() {
            _first = pin;
            _step = 'confirm';
            _message = null;
            _error = false;
          });
        default:
          if (pin != _first) {
            setState(() => _step = 'new');
            return _fail(L.t.deuxCodesNeCorrespondentPas);
          }
          if (widget.flow == TwoStepFlow.enable) {
            await api.enableTwoStep(pin);
          } else {
            final r = await api.changeTwoStep(_current!, pin);
            if (!mounted) return;
            if (!r.ok) {
              // Code actuel refusé : on recommence depuis le début.
              setState(() => _step = 'current');
              return _fail(twoStepRefusal(r));
            }
          }
          if (mounted) Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (mounted) _fail(toAppFailure(e).message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.flow) {
        TwoStepFlow.enable => L.t.twoStepTitle,
        TwoStepFlow.change => L.t.twoStepChange,
        TwoStepFlow.disable => L.t.twoStepTitle,
        TwoStepFlow.phoneChange => L.t.changerNumero,
      }),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PrivioSpacing.xl),
        child: Column(
          children: [
            if (widget.flow == TwoStepFlow.phoneChange) ...[
              Text(
                L.t.twoStepPhoneChangeIntro,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: PrivioSpacing.l),
            ],
            PinEntry(
              key: ValueKey(_step),
              title: _title,
              message: _message,
              error: _error,
              shake: _shake,
              onComplete: _done,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Changement de numéro : si le compte est protégé, demande le code de sécurité d'abord.
/// Renvoie `true` si l'on peut continuer.
Future<bool> confirmTwoStepForPhoneChange(BuildContext context, WidgetRef ref) async {
  final state = await ref.read(accountApiProvider).twoStepState();
  if (!state.enabled) return true;
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const TwoStepPinScreen(flow: TwoStepFlow.phoneChange)),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// Invitation dans Discussions : « Protégez votre compte » (jusqu'à « Plus tard »)
// ---------------------------------------------------------------------------
final twoStepPromptProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (await ref.watch(localFlagsProvider).twoStepPromptDismissed()) return false;
  final s = await ref.watch(accountApiProvider).twoStepState();
  return !s.enabled;
});

class TwoStepPromptCard extends ConsumerWidget {
  const TwoStepPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(twoStepPromptProvider).value ?? false)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(PrivioSpacing.l, 0, PrivioSpacing.l, PrivioSpacing.s),
      child: Card(
        key: const Key('two_step.prompt'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.l,
            PrivioSpacing.m,
            PrivioSpacing.s,
            PrivioSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: p.accentText),
                  const SizedBox(width: PrivioSpacing.s),
                  Expanded(child: Text(L.t.twoStepPromptTitle, style: theme.textTheme.titleSmall)),
                ],
              ),
              const SizedBox(height: PrivioSpacing.xs),
              Text(L.t.twoStepPromptBody, style: theme.textTheme.bodySmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('two_step.prompt.later'),
                    onPressed: () async {
                      await ref.read(localFlagsProvider).setTwoStepPromptDismissed();
                      ref.invalidate(twoStepPromptProvider);
                    },
                    child: Text(L.t.plusTard),
                  ),
                  TextButton(
                    key: const Key('two_step.prompt.enable'),
                    onPressed: () async {
                      await Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute<void>(builder: (_) => const TwoStepSettingsScreen()),
                      );
                      ref.invalidate(twoStepPromptProvider);
                    },
                    child: Text(L.t.activer),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
