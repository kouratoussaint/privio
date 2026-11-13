import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/state_views.dart';

/// Écran 05 — vérification du code SMS. Renvoi possible après 60 s (aligné sur
/// `auth.sms.max_frequency`). La navigation suivante est décidée par le routeur.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phoneE164});

  static const codeLength = 6;
  static const resendDelay = Duration(seconds: 60);

  final String phoneE164;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  int _secondsLeft = OtpScreen.resendDelay.inSeconds;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = OtpScreen.resendDelay.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
    });
  }

  Future<void> _verify() async {
    final code = _controller.text;
    if (code.length != OtpScreen.codeLength || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyOtp(phoneE164: widget.phoneE164, code: code);
      await ref.read(sessionControllerProvider.notifier).onOtpVerified();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = toAppFailure(e).message);
        _controller.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(authServiceProvider).requestOtp(widget.phoneE164);
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Un nouveau code vous a été envoyé.')));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = _secondsLeft == 0 && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Code de vérification')),
      body: FlowLayout(
        bottom: FilledButton(
          key: const Key('otp.submit'),
          onPressed: _busy ? null : _verify,
          child: _busy ? const Text('Vérification…') : const Text('Valider'),
        ),
        children: [
          Text(
            'Saisissez le code à 6 chiffres envoyé par SMS au '
            '${PhoneNumber.format(widget.phoneE164)}.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: PrivioSpacing.xl),
          TextField(
            key: const Key('otp.input'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: OtpScreen.codeLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
            onChanged: (v) {
              if (v.length == OtpScreen.codeLength) _verify();
            },
            decoration: InputDecoration(
              labelText: 'Code reçu par SMS',
              counterText: '',
              errorText: _error,
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          TextButton(
            key: const Key('otp.resend'),
            onPressed: canResend ? _resend : null,
            child: Text(canResend ? 'Renvoyer le code' : 'Renvoyer le code dans $_secondsLeft s'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Modifier le numéro'),
          ),
          if (canResend) ...[
            const SizedBox(height: PrivioSpacing.s),
            Text(
              'Toujours rien\u202F? Vérifiez le numéro ou votre réseau, puis renvoyez le code.',
              key: const Key('otp.help'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
