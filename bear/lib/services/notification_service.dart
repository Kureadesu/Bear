// FCM HTTP v1 uses registration tokens. Keep the compatible token API until
// the backend is migrated to installation-ID direct sending.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local_notification_service.dart';

/// One instance belongs to one signed-in user. Registration, rotation, disabling,
/// and logout are serialized so a late token event cannot undo sign-out cleanup.
class NotificationService extends ChangeNotifier {
  NotificationService(this.uid);
  final String uid;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool enabled = true;
  bool busy = false;
  String status = 'Preparing notifications…';
  String? error;
  bool _disposed = false;
  bool _closing = false;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  Future<void> _queue = Future.value();

  String get _enabledKey => 'bear.push.enabled.$uid';
  String get _deviceKey => 'bear.push.device.$uid';
  bool get _current =>
      !_disposed &&
      !_closing &&
      FirebaseAuth.instance.currentUser?.uid == uid &&
      FirebaseAuth.instance.currentUser?.emailVerified == true;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serialized(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    // An error in one operation must not poison all later operations.
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> start() async {
    if (!supported) {
      status = 'Phone alerts are available in the Android app. Your notes still update live here.';
      _changed();
      return;
    }
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(
        _serialized(() async {
          if (_current && enabled) await _register(token);
        }).catchError((Object _) {
          error = 'Unable to refresh device registration. Open Notifications to retry.';
          _changed();
        }),
      );
    });
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      if (!_current || !enabled) return;
      // New Worker payloads include the recipient, protecting foreground UI
      // against a delayed alert for a different account on the same phone.
      final recipient = message.data['recipientId'];
      if (recipient != null && recipient != uid) return;
      unawaited(
        LocalNotificationService.show(message).catchError((Object _) {
          error = 'A message arrived, but Android could not display its alert.';
          _changed();
        }),
      );
    });
    await refresh(automatic: true);
  }

  Future<void> refresh({bool automatic = false}) => _serialized(() async {
    if (!supported || !_current) return;
    busy = true;
    error = null;
    _changed();
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_enabledKey) ?? true;
      final messaging = FirebaseMessaging.instance;
      var settings = await messaging.getNotificationSettings();
      final asked = prefs.getBool('bear.push.permissionAsked') ?? false;
      if (enabled && (!automatic || !asked)) {
        await prefs.setBool('bear.push.permissionAsked', true);
        settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      if (!_current) return;
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (enabled && allowed) {
        // Migrate the old bell-button setup and protect account switches:
        // invalidate a token that may still be stored under a previous account.
        if (prefs.getString('bear.push.owner') != uid) {
          await messaging.deleteToken().timeout(const Duration(seconds: 15));
        }
        await messaging.setAutoInitEnabled(true);
        final token = await messaging.getToken().timeout(
          const Duration(seconds: 15),
        );
        if (token == null) throw StateError('Device token not available.');
        await _register(token);
        status = 'Notifications are enabled on this phone.';
      } else {
        // Remove any prior registration when Android permission was revoked.
        await _removeRegistration();
        await messaging.deleteToken().timeout(const Duration(seconds: 15));
        await messaging.setAutoInitEnabled(false);
        status = enabled
            ? 'Android notifications are not allowed. Enable them in your phone’s app settings, then tap Check again.'
            : 'Notifications are paused on this phone.';
      }
    } catch (_) {
      error =
          'Could not register this phone. Check your connection and try again.';
      status = 'Device registration needs attention.';
    } finally {
      busy = false;
      _changed();
    }
  });

  Future<void> _register(String token) async {
    if (!_current || !enabled) return;
    final prefs = await SharedPreferences.getInstance();
    final id = sha256.convert(utf8.encode(token)).toString();
    final old = prefs.getString(_deviceKey);
    final devices = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices');
    await devices
        .doc(id)
        .set({
          'token': token,
          'platform': 'android',
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 15));
    await prefs.setString(_deviceKey, id);
    await prefs.setString('bear.push.owner', uid);
    if (old != null && old != id) {
      await devices.doc(old).delete().timeout(const Duration(seconds: 15));
    }
  }

  Future<void> _removeRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>{};
    final saved = prefs.getString(_deviceKey);
    if (saved != null) ids.add(saved);
    // Also removes the earlier manually registered token after upgrading.
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 15),
      );
      if (token != null) ids.add(sha256.convert(utf8.encode(token)).toString());
    }
    for (final id in ids) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(id)
          .delete()
          .timeout(const Duration(seconds: 15));
    }
    await prefs.remove(_deviceKey);
  }

  Future<void> setEnabled(bool value) =>
      _serialized(() async {
        if (!supported || !_current) return;
        busy = true;
        error = null;
        _changed();
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!value) {
            await _removeRegistration();
            await FirebaseMessaging.instance.deleteToken().timeout(
              const Duration(seconds: 15),
            );
            await FirebaseMessaging.instance.setAutoInitEnabled(false);
            await LocalNotificationService.cancelAll();
          }
          enabled = value;
          await prefs.setBool(_enabledKey, value);
          status = value
              ? 'Checking notification permission…'
              : 'Notifications are paused on this phone.';
        } catch (_) {
          error = 'Could not change notification settings. Check your connection and retry.';
        } finally {
          busy = false;
          _changed();
        }
      }).then((_) async {
        if (value && enabled && error == null) await refresh();
      });

  Future<void> openSystemSettings() async {
    if (!supported) return;
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.openAppNotificationSettings();
  }

  /// Call while Firebase auth still belongs to this user. Failure blocks normal
  /// sign-out instead of leaving a known active device attached to the account.
  Future<void> prepareSignOut() => _serialized(() async {
    _closing = true;
    try {
      if (supported) {
        await _removeRegistration();
        await FirebaseMessaging.instance.deleteToken().timeout(
          const Duration(seconds: 15),
        );
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await LocalNotificationService.cancelAll();
      }
    } catch (_) {
      _closing = false;
      rethrow;
    }
  });

  @override
  void dispose() {
    _disposed = true;
    unawaited(_refresh?.cancel());
    unawaited(_foreground?.cancel());
    super.dispose();
  }
}
