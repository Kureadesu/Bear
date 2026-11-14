import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

const presenceDatabaseUrl =
    'https://bear-1c5ec-default-rtdb.asia-southeast1.firebasedatabase.app';

FirebaseDatabase get presenceDatabase => FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: presenceDatabaseUrl,
);

Future<void> authorizePresence(String coupleId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || !user.emailVerified) {
    throw StateError('Verify your email first.');
  }
  final token = await user.getIdToken();
  if (token == null) throw StateError('Please sign in again.');
  const endpoint = String.fromEnvironment(
    'BEAR_PRESENCE_URL',
    defaultValue: 'https://bear-notifications.balaba-claire2003.workers.dev/presence-access',
  );
  final response = await http
      .post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{}',
      )
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw StateError(
      'Presence authorization failed (HTTP ${response.statusCode}).',
    );
  }
  final body = jsonDecode(response.body);
  if (body is! Map ||
      body['coupleId'] != coupleId ||
      body['status'] != 'ready') {
    throw StateError('Your pairing changed. Reopen your shared space.');
  }
}

class PresenceService with WidgetsBindingObserver {
  PresenceService({required this.uid, required this.coupleId});
  final String uid;
  final String coupleId;
  StreamSubscription<DatabaseEvent>? _connectionEvents;
  DatabaseReference? _connection;
  bool _closed = false;
  bool _starting = false;
  bool _observing = false;
  Timer? _retry;
  String _state = 'online';

  bool get _current =>
      !_closed &&
      FirebaseAuth.instance.currentUser?.uid == uid &&
      FirebaseAuth.instance.currentUser?.emailVerified == true;

  Future<void> start() async {
    if (!_current || _starting || _connectionEvents != null) return;
    _starting = true;
    try {
      await authorizePresence(coupleId);
      if (!_current) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _state = lifecycle == null || lifecycle == AppLifecycleState.resumed
          ? 'online'
          : 'away';
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _connectionEvents = presenceDatabase
          .ref('.info/connected')
          .onValue
          .listen(
            (event) {
              if (event.snapshot.value == true && _current) {
                unawaited(_connect());
              }
            },
            onError: (Object error) {
              debugPrint('Presence connection: $error');
            },
          );
    } catch (error) {
      debugPrint('Presence setup: $error');
      _retry?.cancel();
      if (_current) {
        _retry = Timer(const Duration(seconds: 20), () {
          unawaited(start());
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _connect() async {
    // Use a new ID for each connection/reconnection. A delayed disconnect from
    // an older socket cannot remove the newer socket's record.
    final userRef = presenceDatabase.ref('couples/$coupleId/presence/$uid');
    final ref = userRef.child('connections').push();
    try {
      await ref.onDisconnect().remove();
      await userRef.child('lastSeen').onDisconnect().set(ServerValue.timestamp);
      if (!_current) {
        await ref.onDisconnect().cancel();
        return;
      }
      final previous = _connection;
      _connection = ref;
      await ref.set({'state': _state, 'changedAt': ServerValue.timestamp});
      if (!_current) {
        await ref.remove();
        return;
      }
      if (previous != null && previous.key != ref.key) {
        await previous.remove();
        await previous.onDisconnect().cancel();
      }
    } catch (error) {
      debugPrint('Presence registration: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state == AppLifecycleState.resumed ? 'online' : 'away';
    unawaited(_updateState());
  }

  Future<void> _updateState() async {
    if (!_current || _connection == null) return;
    try {
      await _connection!.update({
        'state': _state,
        'changedAt': ServerValue.timestamp,
      });
    } catch (error) {
      debugPrint('Presence state: $error');
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _retry?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _connectionEvents?.cancel();
    final ref = _connection;
    _connection = null;
    if (ref == null) return;
    try {
      await ref.parent!.parent!
          .update({
            'connections/${ref.key}': null,
            'lastSeen': ServerValue.timestamp,
          })
          .timeout(const Duration(seconds: 3));
      // Cancel only after the server acknowledged removal. Otherwise leave the
      // onDisconnect operation armed for an interrupted/offline shutdown.
      await ref.onDisconnect().cancel();
      await ref.parent!.parent!.child('lastSeen').onDisconnect().cancel();
    } catch (_) {
      /* Server onDisconnect remains the fallback. */
    }
  }
}
