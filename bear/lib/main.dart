import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'local_notification_service.dart';
import 'screens/account_gate.dart';
import 'screens/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // A notification icon/configuration error should not make all of Bear blank.
  try {
    await LocalNotificationService.initialize();
  } catch (error) {
    debugPrint('Notification initialization failed: $error');
  }
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bear',
    debugShowCheckedModeBanner: false,
    theme: buildBearTheme(),
    darkTheme: buildBearTheme(),
    themeMode: ThemeMode.dark,
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _users = FirebaseAuth.instance.userChanges();

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _users,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text('Unable to check sign-in status. Please restart Bear.'),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      return user == null
          ? const SignInScreen()
          : AccountGate(key: ValueKey(user.uid), user: user);
    },
  );
}
