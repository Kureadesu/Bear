import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const workerEndpoint = String.fromEnvironment(
  'BEAR_NOTIFY_URL',
  defaultValue:
      'https://bear-notifications.balaba-claire2003.workers.dev/notify',
);

Future<String?> notifyPartner(String messageId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'Note saved. Sign in again to send an alert.';
  try {
    final token = await user.getIdToken();
    if (token == null) return 'Note saved. Notification authentication failed.';
    final response = await http
        .post(
          Uri.parse(workerEndpoint),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'messageId': messageId}),
        )
        .timeout(const Duration(seconds: 30));
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return 'Note saved. Notification server returned an unexpected response (HTTP ${response.statusCode}).';
    }
    if (decoded is! Map<String, dynamic>) {
      return 'Note saved. Invalid notification response.';
    }
    if (response.statusCode != 200) {
      return 'Note saved. ${decoded['error'] ?? 'Notification service returned HTTP ${response.statusCode}.'}';
    }
    switch (decoded['status']) {
      case 'sent':
        return null;
      case 'already_attempted':
        return 'Note saved. A notification was already attempted.';
      case 'no_devices':
        return 'Note saved. Your person hasn’t enabled phone notifications yet.';
      default:
        return 'Note saved, but the phone alert could not be delivered.';
    }
  } on TimeoutException {
    return 'Note saved. The notification service took too long to respond.';
  } catch (_) {
    return 'Note saved. Could not reach the notification service. On web, check the Worker’s allowed origin.';
  }
}
