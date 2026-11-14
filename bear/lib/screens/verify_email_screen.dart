import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/page_frame.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.user});
  final User user;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Send automatically on entry; resend is available if the user returns later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_send());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) unawaited(_check());
  }

  Future<void> _send() async {
    if (_busy || _cooldown > 0) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.user.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _cooldown = 60;
        _message = 'Verification email sent. Check your inbox and spam folder.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _cooldown--;
        });
        if (_cooldown <= 0) timer.cancel();
      });
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not send email (${error.code}). Try again shortly.';
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

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user?.emailVerified == true) {
        // Refresh the email_verified claim used by the rules and Worker.
        await user!.getIdToken(true);
      } else if (mounted) {
        setState(() {
          _message = 'Not verified yet. Open the email link, then check again.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Unable to check verification (${error.code}).';
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

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Unable to sign out. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bear'),
      actions: [
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: PageFrame(
      maxWidth: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.mark_email_unread_outlined, size: 64),
          const SizedBox(height: 24),
          Text(
            'Check your inbox',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'We sent a verification link to ${widget.user.email ?? 'your email address'}. Verify your email to continue.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: const Text('I verified my email'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy || _cooldown > 0 ? null : _send,
            child: Text(
              _cooldown > 0
                  ? 'Resend in ${_cooldown}s'
                  : 'Resend verification email',
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 20),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );
}
