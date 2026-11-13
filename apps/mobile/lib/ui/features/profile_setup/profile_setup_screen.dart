import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/handle/handle_rules.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../state/providers.dart';
import '../../../state/session_controller.dart';
import '../../core/widgets/state_views.dart';

/// Écran 06 — nom et identifiant Privio unique. La photo de profil arrive avec le
/// pipeline média (étape 3) : elle n'est pas proposée tant qu'elle n'est pas livrée.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  static const availabilityDebounce = Duration(milliseconds: 500);

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

enum _Availability { unknown, checking, available, taken }

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  Timer? _debounce;
  _Availability _availability = _Availability.unknown;
  String? _handleError;
  String? _nameError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _onHandleChanged(String raw) {
    _debounce?.cancel();
    final normalized = HandleRules.normalize(raw);
    final issue = HandleRules.validate(normalized);
    setState(() {
      _handleError = issue == null || normalized.isEmpty ? null : HandleRules.message(issue);
      _availability = issue == null ? _Availability.checking : _Availability.unknown;
    });
    if (issue != null) return;
    _debounce = Timer(ProfileSetupScreen.availabilityDebounce, () async {
      try {
        final free = await ref.read(accountApiProvider).isHandleAvailable(normalized);
        if (!mounted || HandleRules.normalize(_handle.text) != normalized) return;
        setState(() {
          _availability = free ? _Availability.available : _Availability.taken;
          _handleError = free ? null : const AppFailure(FailureCode.handleTaken).message;
        });
      } on Object {
        if (mounted) setState(() => _availability = _Availability.unknown);
      }
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final handle = HandleRules.normalize(_handle.text);
    final issue = HandleRules.validate(handle);
    setState(() {
      _nameError = name.isEmpty || name.length > 40
          ? const AppFailure(FailureCode.displayNameInvalid).message
          : null;
      _handleError = issue == null ? _handleError : HandleRules.message(issue);
      _formError = null;
    });
    if (_nameError != null || issue != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).createProfile(handle: handle, displayName: name);
      await ref.read(sessionControllerProvider.notifier).onProfileCreated();
    } on Object catch (e) {
      final failure = toAppFailure(e);
      if (!mounted) return;
      setState(() {
        if (failure.code == FailureCode.handleTaken || failure.code == FailureCode.handleInvalid) {
          _handleError = failure.message;
          _availability = _Availability.taken;
        } else {
          _formError = failure.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = ref.watch(sessionControllerProvider).value?.account?.phoneE164;
    final helper = switch (_availability) {
      _Availability.checking => 'Vérification de la disponibilité…',
      _Availability.available => 'Cet identifiant est disponible.',
      _ => 'Il permet à vos proches de vous trouver sans connaître votre numéro.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Votre profil')),
      body: FlowLayout(
        bottom: FilledButton(
          key: const Key('profile.submit'),
          onPressed: _busy ? null : _submit,
          child: _busy ? const Text('Création…') : const Text('Créer mon profil'),
        ),
        children: [
          if (phone != null)
            Text(
              'Numéro vérifié\u202F: ${PhoneNumber.format(phone)}',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: PrivioSpacing.xl),
          TextField(
            key: const Key('profile.name'),
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Votre nom',
              helperText: 'Visible par les personnes avec qui vous échangez.',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: PrivioSpacing.m),
          TextField(
            key: const Key('profile.handle'),
            controller: _handle,
            maxLength: HandleRules.maxLength + 1,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onHandleChanged,
            decoration: InputDecoration(
              labelText: 'Identifiant',
              hintText: 'awa_s',
              prefixText: '@',
              helperText: helper,
              errorText: _handleError,
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: PrivioSpacing.m),
            Text(
              _formError!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
