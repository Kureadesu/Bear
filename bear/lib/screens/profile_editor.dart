import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../profile_helpers.dart';
import '../widgets/page_frame.dart';
import '../widgets/profile_avatar.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.user,
    required this.profile,
    this.onboarding = false,
  });
  final User user;
  final Map<String, dynamic> profile;
  final bool onboarding;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _photo;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.profile['displayName'] as String? ?? '',
    );
    _photo = TextEditingController(
      text: widget.profile['photoUrl'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _photo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Firestore is the source of truth for app display names.
      // Merge only these fields; never overwrite coupleId or createdAt.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
            'displayName': _name.text.trim(),
            'photoUrl': _photo.text.trim().isEmpty ? null : _photo.text.trim(),
            'profileComplete': true,
          });
      if (mounted && !widget.onboarding) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Could not save your profile (${error.code}). Please try again.';
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
  Widget build(BuildContext context) => PageFrame(
    maxWidth: 520,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.onboarding ? 'What should we call you?' : 'Your profile',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            widget.onboarding
                ? 'Choose a name your person will recognize. A photo can wait.'
                : 'This is how you appear in Bear and in your partner’s notifications.',
          ),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: Listenable.merge([_name, _photo]),
            builder: (_, _) => Center(
              child: ProfileAvatar(
                name: _name.text,
                photoUrl: validatePhotoUrl(_photo.text) == null
                    ? _photo.text.trim()
                    : null,
                radius: 48,
              ),
            ),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _name,
            enabled: !_busy,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name'),
            validator: validateDisplayName,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Profile picture · optional'),
            children: [
              const Text(
                'Keep your Google picture, use initials, or paste an HTTPS image link. Uploading a photo from your device can be added later.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _photo,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Image URL',
                  hintText: 'https://…',
                ),
                validator: validatePhotoUrl,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : () => _photo.clear(),
                  child: const Text('Use my initials instead'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_outlined),
            title: Text(widget.user.email ?? 'Google account'),
            subtitle: const Text('Email verified'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _busy
                  ? 'Saving…'
                  : widget.onboarding
                  ? 'Continue to Bear'
                  : 'Save changes',
            ),
          ),
        ],
      ),
    ),
  );
}
