import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../profile_helpers.dart';
import 'app_shell.dart';
import 'profile_editor.dart';
import 'verify_email_screen.dart';

class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    if (!user.emailVerified) {
      return VerifyEmailScreen(key: ValueKey(user.uid), user: user);
    }
    return ProfileGate(key: ValueKey(user.uid), user: user);
  }
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.user});
  final User user;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<void> _setup;
  late final _profile = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.user.uid);
  late final _changes = _profile.snapshots();

  @override
  void initState() {
    super.initState();
    _setup = _ensureProfile();
  }

  Future<void> _ensureProfile() async {
    // Verification may have just changed. Refresh the claims before rule checks.
    await widget.user.getIdToken(true);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final existing = await transaction.get(_profile);
      if (existing.exists) return;
      transaction.set(_profile, {
        'displayName': widget.user.displayName ?? '',
        'photoUrl': widget.user.photoURL,
        'coupleId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': false,
      });
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _setup,
    builder: (context, setup) {
      if (setup.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (setup.hasError) {
        return _errorScreen(
          'Could not prepare your profile. Check your connection and try again.',
        );
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _changes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _errorScreen(
              'Could not load your profile. Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return _errorScreen(
              'Your profile is missing. Tap Try again to recreate it.',
            );
          }
          if (needsProfileSetup(data)) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Make yourself at home'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (_) {}
                    },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
              body: ProfileEditor(
                user: widget.user,
                profile: data,
                onboarding: true,
              ),
            );
          }
          return AppShell(user: widget.user, profile: data);
        },
      );
    },
  );

  Widget _errorScreen(String message) => Scaffold(
    appBar: AppBar(
      title: const Text('Bear'),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {}
          },
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => setState(() {
                _setup = _ensureProfile();
              }),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}
