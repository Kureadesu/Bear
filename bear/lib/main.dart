import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bear',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC87589),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF7F4),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(
                child: Text('Unable to check your sign-in status.'),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = snapshot.data;
          return user == null
              ? const SignInScreen()
              : HomeScreen(user: user);
        },
      ),
    );
  }
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
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        await auth.signInWithPopup(provider);
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
                      'A little place for the two of you.',
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to sign out. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bear 🐻'),
        actions: [
          TextButton(
            onPressed: () => _signOut(context),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: profile.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load your profile. Check your Firestore rules.',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data();
          final coupleId = data?['coupleId'];

          if (coupleId is! String || coupleId.trim().isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add your coupleId to your user document in Firestore.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return _SharedSpace(
            key: ValueKey(coupleId),
            user: user,
            coupleId: coupleId,
          );
        },
      ),
    );
  }
}

class _SharedSpace extends StatefulWidget {
  const _SharedSpace({
    super.key,
    required this.user,
    required this.coupleId,
  });

  final User user;
  final String coupleId;

  @override
  State<_SharedSpace> createState() => _SharedSpaceState();
}

class _SharedSpaceState extends State<_SharedSpace> {
  final _noteController = TextEditingController();

  late final CollectionReference<Map<String, dynamic>> _messages;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream;

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _messages = FirebaseFirestore.instance
        .collection('couples')
        .doc(widget.coupleId)
        .collection('messages');

    _messageStream = _messages
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _send({required bool missYou}) async {
    if (_sending) return;

    final text = missYou
        ? 'I miss you 💗'
        : _noteController.text.trim();

    if (text.isEmpty || text.length > 2000) {
      setState(() {
        _error = 'Write a note between 1 and 2,000 characters.';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _messages.add({
        'senderId': widget.user.uid,
        'type': missYou ? 'miss_you' : 'note',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      if (!missYou) {
        _noteController.clear();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to your shared space 💗')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.code == 'permission-denied'
            ? 'Permission denied. Check your memberIds and Firestore rules.'
            : 'Could not send (${error.code}). Please try again.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not send. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your little shared space',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Leave a little note',
                    hintText: 'Something that made you think of her…',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _send(missYou: false),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Send note'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _send(missYou: true),
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('I miss you'),
                    ),
                  ],
                ),
                if (_sending) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                Expanded(
                  child: StreamBuilder<
                      QuerySnapshot<Map<String, dynamic>>>(
                    stream: _messageStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Unable to load messages. Check your '
                            'connection and Firestore rules.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final messages = snapshot.data!.docs;

                      if (messages.isEmpty) {
                        return const Center(
                          child: Text('Your first little note goes here 💌'),
                        );
                      }

                      return ListView.builder(
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index].data();

                          final isMine =
                              message['senderId'] == widget.user.uid;
                          final isMissYou =
                              message['type'] == 'miss_you';
                          final text = message['text'];

                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isMissYou
                                    ? Icons.favorite
                                    : Icons.chat_bubble_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                              title: Text(
                                text is String ? text : '',
                              ),
                              subtitle: Text(
                                isMine ? 'You' : 'Your person',
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}