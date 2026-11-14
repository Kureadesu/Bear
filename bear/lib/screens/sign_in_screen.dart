import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<void>? _googleInitialization;

Future<UserCredential> signInWithGoogle() async {
  final auth = FirebaseAuth.instance;

  // Browser: keep using Firebase's popup.
  if (kIsWeb) {
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});

    return auth.signInWithPopup(provider);
  }

  // Native Android/iOS: initialize Google Sign-In once.
  final googleSignIn = GoogleSignIn.instance;

  await (_googleInitialization ??= googleSignIn.initialize());

  final googleUser = await googleSignIn.authenticate();
  final idToken = googleUser.authentication.idToken;

  if (idToken == null) {
    throw FirebaseAuthException(
      code: 'invalid-credential',
      message: 'Google did not return an ID token.',
    );
  }

  final credential = GoogleAuthProvider.credential(idToken: idToken);

  return auth.signInWithCredential(credential);
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate({required bool withGoogle}) async {
    if (_busy) return;

    if (!withGoogle && !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = FirebaseAuth.instance;

      if (withGoogle) {
        await signInWithGoogle();
      } else if (_creatingAccount) {
        await auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = _authErrorMessage(error);
        });
      }
    } on GoogleSignInException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == GoogleSignInExceptionCode.canceled
              ? 'Google sign-in was cancelled.'
              : 'Google sign-in failed (${error.code.name}).';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
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

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'The email or password is incorrect.';
      case 'email-already-in-use':
        return 'That email already has an account. Try signing in.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Google sign-in was cancelled. You can try again.';
      case 'popup-blocked':
        return 'Your browser blocked the sign-in popup. Allow popups and retry.';
      case 'unauthorized-domain':
        return 'Add this website’s domain to Firebase Auth’s authorized domains.';
      case 'operation-not-allowed':
        return 'Enable this sign-in method in Firebase Console.';
      case 'account-exists-with-different-credential':
        return 'Sign in using your original method for this email address.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Sign-in failed (${error.code}). Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🐻',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 64),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bear',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A little closer, wherever you are.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _authenticate(withGoogle: true),
                      child: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'or use your email',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty || !email.contains('@')) {
                          return 'Enter your email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password.';
                        }
                        if (_creatingAccount && value.length < 6) {
                          return 'Use at least 6 characters.';
                        }
                        return null;
                      },
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _authenticate(withGoogle: false),
                      child: Text(
                        _creatingAccount ? 'Create account' : 'Sign in',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _creatingAccount = !_creatingAccount;
                                _error = null;
                                _formKey.currentState?.reset();
                              });
                            },
                      child: Text(
                        _creatingAccount
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
