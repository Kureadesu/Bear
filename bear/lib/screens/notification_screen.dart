import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../services/notification_service.dart';
import '../widgets/page_frame.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.service,
    required this.user,
    required this.profile,
  });
  final NotificationService service;
  final User user;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Notification Settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text('Receive app notifications'),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: service,
          builder: (context, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable notifications'),
                    // subtitle: const Text(
                    //   'Enable notifications',
                    // ),
                    value: service.supported && service.enabled,
                    onChanged: service.supported && !service.busy
                        ? (value) => service.setEnabled(value)
                        : null,
                  ),
                  Text(service.status),
                  if (service.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      service.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (service.supported) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: service.busy
                              ? null
                              : () => service.enabled
                                    ? service.refresh()
                                    : service.setEnabled(true),
                          child: Text(
                            service.enabled
                                ? 'Check again'
                                : 'Enable notifications',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: service.busy
                              ? null
                              : () async {
                                  try {
                                    await service.openSystemSettings();
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Open Android Settings → Apps → Bear → Notifications.',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                          child: const Text('Android settings'),
                        ),
                      ],
                    ),
                  ],
                  if (service.busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
        // const SizedBox(height: 28),
        // Text('From your person', style: Theme.of(context).textTheme.titleLarge),
        // const SizedBox(height: 8),
        // const Text('Your latest notes and little reminders.'),
        // const SizedBox(height: 16),
        // _ReceivedNotes(uid: user.uid, coupleId: profile['coupleId'] as String?),
      ],
    ),
  );
}

class _ReceivedNotes extends StatefulWidget {
  const _ReceivedNotes({required this.uid, required this.coupleId});
  final String uid;
  final String? coupleId;
  @override
  State<_ReceivedNotes> createState() => _ReceivedNotesState();
}

class _ReceivedNotesState extends State<_ReceivedNotes> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant _ReceivedNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupleId != widget.coupleId) _connect();
  }

  void _connect() {
    _stream = widget.coupleId == null
        ? null
        : FirebaseFirestore.instance
              .collection('couples')
              .doc(widget.coupleId)
              .collection('messages')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) {
      return const Text('Connect with your person to start receiving notes.');
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Could not load recent notes.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data!.docs
            .where((doc) => doc.data()['senderId'] != widget.uid)
            .toList();
        if (messages.isEmpty) {
          return const Text('Your person’s next little note will appear here.');
        }
        return Column(
          children: [
            for (final doc in messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      doc.data()['type'] == 'miss_you'
                          ? Icons.favorite
                          : Icons.chat_bubble_outline,
                    ),
                    title: Text(doc.data()['text'] as String? ?? ''),
                    subtitle: const Text('Your person'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
