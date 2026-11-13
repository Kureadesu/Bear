import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import 'pairing_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  final _service = PairingService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pair({required bool create}) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (create) {
        await _service.createInvite();
      } else {
        await _service.acceptInvite(_codeController.text);
      }

      // HomeScreen already watches the user's profile.
      // Its coupleId change will switch the screen automatically.
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message.toString();
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == 'permission-denied'
              ? 'This invitation is unavailable, or the pairing rules '
                    'have not been published.'
              : 'Could not connect (${error.code}). Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // final ancestors = <String>[];

    // context.visitAncestorElements((element) {
    //   ancestors.add(element.widget.runtimeType.toString());
    //   return true;
    // });

    // debugPrint('PAIRING ANCESTORS: ${ancestors.join(' → ')}');

    // debugPrint(
    //   'HAS MATERIAL LOCALIZATIONS: '
    //   '${Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) != null}',
    // );
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '🐻 💗 🐻',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  'Connect with your person',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'One person creates an invite. '
                  'The other enters that code below.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : () => _pair(create: true),
                  child: const Text('Create invite'),
                ),
                const SizedBox(height: 24),
                const Text('Already have a code?', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    hintText: 'Paste the complete code',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : () => _pair(create: false),
                  child: const Text('Accept invite'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
