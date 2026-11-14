import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> cancelAll() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _plugin.cancelAll();
    }
  }

  static const _channel = AndroidNotificationChannel(
    'bear_messages_v1',
    'Messages from your person',
    description: 'Notes and little reminders from your partner.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static int _nextId = DateTime.now().millisecondsSinceEpoch % 2147483647;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.createNotificationChannel(_channel);
  }

  static Future<void> show(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final notification = message.notification;

    if (notification == null) return;

    _nextId = (_nextId + 1) % 2147483647;

    await _plugin.show(
      id: _nextId,
      title: notification.title ?? 'Bear 💗',
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'bear_messages_v1',
          'Messages from your person',
          channelDescription: 'Notes and little reminders from your partner.',
          icon: 'ic_notification',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }
}
