import '../../../l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_palette.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/app_lock_providers.dart';
import '../../../state/feedback_providers.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/success_snack.dart';
import '../lock/app_lock_screens.dart';
import 'two_step_screens.dart';

/// Lot 8.1c — changer de numéro. Le code part vers le NOUVEAU numéro ; tant qu'il n'est
/// pas saisi, rien ne change. Compte, identifiant, discussions et groupes sont conservés ;
/// les contacts ne sont pas prévenus (le numéro n'est jamais affiché dans Privio).
/// Code Privio demandé d'abord si le verrouillage est activé.
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key, required this.currentPhone});

  final String? currentPhone;

  static const codeLength = 6;

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _newPhone;
  String? _error;
  bool _busy = false;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _countdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<bool> _confirmPin() async {
    final lock = ref.read(appLockProvider).value;
    if (lock == null || !lock.enabled) return true;
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const PinFlowScreen(flow: PinFlow.confirm)));
    return ok == true;
  }

  Future<void> _send() async {
    final e164 = PhoneNumber.normalize(_phone.text);
    if (e164 == null) {
      setState(() => _error = const AppFailure(FailureCode.phoneInvalid).message);
      return;
    }
    if (e164 == widget.currentPhone) {
      setState(() => _error = L.t.cEstDejaVotreNumero);
      return;
    }
    if (!await _confirmPin() || !mounted) return;
    // Lot 8.4a : compte protégé : code de sécurité (le serveur refuse sinon le changement).
    try {
      if (!await confirmTwoStepForPhoneChange(context, ref) || !mounted) return;
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await ref.read(authServiceProvider).requestPhoneChange(e164);
      if (!mounted) return;
      if (done) {
        await _finish();
        return;
      }
      setState(() => _newPhone = e164);
      _countdown();
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final e164 = _newPhone;
    if (e164 == null) return;
    setState(() => _error = null);
    try {
      await ref.read(authServiceProvider).requestPhoneChange(e164);
      _countdown();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L.t.nouveauCodeVousEteEnvoye)));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    }
  }

  Future<void> _verify() async {
    final e164 = _newPhone;
    final code = _code.text;
    if (e164 == null || code.length != ChangePhoneScreen.codeLength || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyPhoneChange(newPhoneE164: e164, code: code);
      if (!mounted) return;
      await _finish();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = toAppFailure(e).message);
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    await ref.read(sessionControllerProvider.notifier).refreshAccount();
    if (!mounted) return;
    ref.read(feedbackProvider).sound(PrivioSound.success);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(successSnack(L.t.numeroChange));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PrivioPalette.of(context);
    final step2 = _newPhone != null;
    final canResend = _secondsLeft == 0 && !_busy;
    return Scaffold(
      key: const Key('phone_change.screen'),
      appBar: AppBar(title: Text(L.t.changerNumero)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PrivioSpacing.xl),
          children: [
            Icon(Icons.phonelink_setup_outlined, size: 48, color: p.accentText),
            const SizedBox(height: PrivioSpacing.l),
            if (!step2) ...[
              Text(L.t.votreCompteVotreIdentifiantVos, style: theme.textTheme.bodyLarge),
              if (widget.currentPhone != null) ...[
                const SizedBox(height: PrivioSpacing.m),
                Text(
                  L.t.numeroActuelCurrentphone(PhoneNumber.format(widget.currentPhone!)),
                  key: const Key('phone_change.current'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: p.accentText),
                ),
              ],
              const SizedBox(height: PrivioSpacing.xl),
              TextField(
                key: const Key('phone_change.input'),
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]'))],
                onSubmitted: (_) => _busy ? null : _send(),
                decoration: InputDecoration(
                  labelText: L.t.nouveauNumero,
                  hintText: '70 00 00 00',
                  helperText: L.t.sansIndicatifBurkinaFaso226,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              FilledButton(
                key: const Key('phone_change.send'),
                onPressed: _busy ? null : _send,
                child: Text(_busy ? L.t.envoi : L.t.recevoirCodeSurCeNumero),
              ),
            ] else ...[
              Text(
                L.t.saisissezCode6ChiffresEnvoye2(PhoneNumber.format(_newPhone!)),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: PrivioSpacing.xl),
              TextField(
                key: const Key('phone_change.code'),
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: ChangePhoneScreen.codeLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
                onChanged: (v) {
                  if (v.length == ChangePhoneScreen.codeLength) _verify();
                },
                decoration: InputDecoration(
                  labelText: L.t.codeRecuParSms,
                  counterText: '',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: PrivioSpacing.l),
              FilledButton(
                key: const Key('phone_change.verify'),
                onPressed: _busy ? null : _verify,
                child: Text(_busy ? L.t.verification : L.t.valider),
              ),
              TextButton(
                key: const Key('phone_change.resend'),
                onPressed: canResend ? _resend : null,
                child: Text(
                  canResend ? L.t.renvoyerCode : L.t.renvoyerCodeDansSecondsleft(_secondsLeft),
                ),
              ),
              TextButton(
                key: const Key('phone_change.back'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _newPhone = null;
                        _code.clear();
                        _error = null;
                      }),
                child: Text(L.t.changerNumeroSaisi),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
