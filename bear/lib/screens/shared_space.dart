import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../pairing_screen.dart';
import '../services/push_sender.dart';
import '../widgets/partner_presence_badge.dart';

class SharedSpace extends StatelessWidget {
  const SharedSpace({super.key, required this.user, required this.profile});
  final User user;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final coupleId = profile['coupleId'];
    if (coupleId is! String || coupleId.isEmpty) return const PairingScreen();
    return _SharedSpace(
      key: ValueKey(coupleId),
      user: user,
      coupleId: coupleId,
    );
  }
}

class _SharedSpace extends StatefulWidget {
  const _SharedSpace({super.key, required this.user, required this.coupleId});

  final User user;
  final String coupleId;

  @override
  State<_SharedSpace> createState() => _SharedSpaceState();
}

class _SharedSpaceState extends State<_SharedSpace> {
  late final Future<String?> _partnerUid;

  Future<String?> _findPartnerUid() async {
    final couple = await FirebaseFirestore.instance
        .collection('couples')
        .doc(widget.coupleId)
        .get();

    final members = List<String>.from(couple.data()?['memberIds'] ?? []);
    for (final id in members) {
      if (id != widget.user.uid) return id;
    }
    return null;
  }

  late final Future<String> _partnerName;

  Future<String> _loadPartnerName() async {
    final db = FirebaseFirestore.instance;

    final couple = await db.collection('couples').doc(widget.coupleId).get();

    final members = List<String>.from(couple.data()?['memberIds'] ?? []);

    final others = members.where((id) => id != widget.user.uid);

    if (others.isEmpty) return 'Your person';

    final partner = await db.collection('users').doc(others.first).get();

    final name = partner.data()?['displayName'];

    return name is String && name.trim().isNotEmpty
        ? name.trim()
        : 'Your person';
  }

  final _noteController = TextEditingController();

  late final CollectionReference<Map<String, dynamic>> _messages;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream;

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _partnerUid = _findPartnerUid();
    _partnerName = _loadPartnerName();

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

  Future<void> _send({bool missYou = false, bool loveYou = false}) async {
    if (_sending) return;

    final text = missYou
        ? 'I miss you 🥺'
        : loveYou
        ? 'I love you 💗'
        : _noteController.text.trim();

    if (text.isEmpty || text.length > 2000) {
      setState(() {
        _error = 'Write a message between 1 and 2,000 characters.';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final messageRef = await _messages.add({
        'senderId': widget.user.uid,
        'type': missYou ? 'miss_you' : 'note',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final notificationWarning = await notifyPartner(messageRef.id);

      if (!mounted) return;

      if (!missYou && !loveYou) {
        _noteController.clear();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notificationWarning ?? 'Saved and notification sent 💗',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.code == 'permission-denied'
            ? 'You do not have access to this shared space. Try signing in again.'
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: FutureBuilder<String>(
                future: _partnerName,
                builder: (context, snapshot) {
                  final name = snapshot.data ?? 'Your person';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFF29456C),
                            child: Icon(Icons.favorite_outline),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 6),
                                FutureBuilder<String?>(
                                  future: _partnerUid,
                                  builder: (context, statusSnapshot) {
                                    if (statusSnapshot.hasError) {
                                      return const Text('Status unavailable');
                                    }

                                    if (statusSnapshot.connectionState !=
                                        ConnectionState.done) {
                                      return const Text('Connecting…');
                                    }

                                    final partnerUid = statusSnapshot.data;

                                    if (partnerUid == null) {
                                      return const Text(
                                        'Waiting for your person',
                                      );
                                    }

                                    return PartnerPresenceBadge(
                                      coupleId: widget.coupleId,
                                      partnerUid: partnerUid,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Only the message area scrolls.
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messageStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Unable to load messages. Try again.'),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snapshot.data!.docs;

                  return ListView.builder(
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      // With reverse:true, the final item is at the top.
                      if (index == messages.length) {
                        return Column(
                          children: [
                            InviteBanner(coupleId: widget.coupleId),
                            if (messages.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Your first little note goes here 💌',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        );
                      }

                      final message = messages[index].data();
                      final isMine = message['senderId'] == widget.user.uid;
                      final text = message['text'] as String? ?? '';

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isMine
                                ? const Color(0xFF223B61)
                                : const Color(0xFF16243C),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FutureBuilder<String>(
                                future: _partnerName,
                                builder: (context, nameSnapshot) {
                                  return Text(
                                    isMine
                                        ? 'You'
                                        : nameSnapshot.data ?? 'Your person',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                text,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // This stays at the bottom, above Android navigation.
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF121E35),
                border: Border(top: BorderSide(color: Color(0xFF314462))),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _sending
                                ? null
                                : () => _send(missYou: true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            child: const Text('I miss you 🥺'),
                          ),
                          OutlinedButton(
                            onPressed: _sending
                                ? null
                                : () => _send(loveYou: true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            child: const Text('I love you 💗'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _noteController,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: 3,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'A little message…',
                                counterText: '',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Send message',
                            onPressed: _sending ? null : () => _send(),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                      if (_sending) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InviteBanner extends StatelessWidget {
  const InviteBanner({super.key, required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    final inviteRef = FirebaseFirestore.instance
        .collection('invites')
        .doc(coupleId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: inviteRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Unable to load your invitation.'),
          );
        }

        final invite = snapshot.data?.data();

        // Old manually created couples may not have an invite.
        if (invite == null || invite['status'] != 'open') {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Invite your person 💌',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Share this private code. It can be accepted once '
                  'before it expires.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  coupleId,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: coupleId));

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite code copied')),
                        );
                      } catch (_) {
                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Select the code and copy it manually.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                  ),
                ),
                if (invite['expiresAt'] is Timestamp)
                  Text(
                    'Expires: '
                    '${(invite['expiresAt'] as Timestamp).toDate().toLocal()}',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
