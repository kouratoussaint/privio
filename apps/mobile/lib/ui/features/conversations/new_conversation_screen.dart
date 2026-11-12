import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/handle/handle_rules.dart';
import '../../../core/phone/phone_number.dart';
import '../../../core/theme/privio_tokens.dart';
import '../../../domain/models/messaging.dart';
import '../../../router/routes.dart';
import '../../../state/messaging_providers.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/state_views.dart';

/// Écran 09 — trouver une personne par son identifiant Privio (ou son numéro, si elle
/// l'a autorisé) et lui écrire. Recherche exacte uniquement, limitée côté serveur.
class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _controller = TextEditingController();
  FoundUser? _found;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _found = null;
      _message = null;
    });
    final api = ref.read(messagingApiProvider);
    try {
      FoundUser? user;
      if (PhoneNumber.looksLikePhone(input)) {
        user = await api.findByPhone(PhoneNumber.normalize(input)!);
      } else {
        final handle = HandleRules.normalize(input);
        final issue = HandleRules.validate(handle);
        if (issue != null) {
          setState(() => _message = HandleRules.message(issue));
          return;
        }
        user = await api.findByHandle(handle);
      }
      setState(() {
        _found = user;
        _message = user == null
            ? 'Aucun compte trouvé. Vérifiez l\'identifiant ; pour une recherche par numéro, '
                  'la personne doit avoir activé « Me trouver par mon numéro ».'
            : null;
      });
    } on Object catch (e) {
      setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(FoundUser user) async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(messagingApiProvider).startDirectConversation(user.id);
      ref.invalidate(conversationsProvider);
      if (mounted) context.pushReplacement(Routes.chat(id));
    } on Object catch (e) {
      if (mounted) setState(() => _message = toAppFailure(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle discussion')),
      body: FlowLayout(
        children: [
          TextField(
            key: const Key('search.input'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _busy ? null : _search(),
            decoration: InputDecoration(
              labelText: 'Identifiant Privio ou numéro',
              hintText: '@identifiant ou 70 00 00 00',
              suffixIcon: IconButton(
                key: const Key('search.submit'),
                tooltip: 'Rechercher',
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.l),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Text(_message!, key: const Key('search.message'), style: theme.textTheme.bodyMedium),
          if (found != null)
            Card(
              child: ListTile(
                key: const Key('search.result'),
                leading: InitialAvatar(name: found.displayName),
                title: Text(found.displayName),
                subtitle: Text('@${found.handle}'),
                trailing: FilledButton(
                  key: const Key('search.write'),
                  onPressed: _busy ? null : () => _write(found),
                  child: const Text('Écrire'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
