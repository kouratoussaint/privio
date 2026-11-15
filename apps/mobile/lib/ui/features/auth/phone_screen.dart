import '../../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../router/routes.dart';
import '../../../state/providers.dart';
import '../../core/widgets/state_views.dart';
import '../../core/motion/illustrations.dart';

/// Écran 04 — saisie du numéro (formulaire téléphone uniquement).
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e164 = PhoneNumber.normalize(_controller.text);
    if (e164 == null) {
      setState(() => _error = L.t.numeroIncomplet8ChiffresPour);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(authServiceProvider).requestOtp(e164);
      if (!mounted) return;
      await context.push(Uri(path: Routes.otp, queryParameters: {'phone': e164}).toString());
    } on Object catch (e) {
      if (mounted) setState(() => _error = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L.t.votreNumero)),
      body: FlowLayout(
        bottom: FilledButton(
          key: const Key('phone.submit'),
          onPressed: _busy ? null : _submit,
          child: _busy ? Text(L.t.envoiCode) : Text(L.t.recevoirCode),
        ),
        children: [
          // Lot 7.2b2 : le SMS arrive.
          const Center(
            child: FloatingIcon(icon: Icons.sms_outlined, size: 36, motion: IconMotion.pulse),
          ),
          const SizedBox(height: PrivioSpacing.l),
          Text(L.t.quelEstVotreNumeroVous, style: theme.textTheme.bodyLarge),
          const SizedBox(height: PrivioSpacing.xl),
          TextField(
            key: const Key('phone.input'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]'))],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: L.t.numeroTelephone,
              hintText: '70 00 00 00',
              helperText: L.t.burkinaFaso226ParDefaut,
              errorText: _error,
            ),
          ),
        ],
      ),
    );
  }
}
