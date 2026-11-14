import 'package:firebase_database/firebase_database.dart';
import 'package:material_ui/material_ui.dart';

import '../services/presence_service.dart';

class PartnerPresenceBadge extends StatefulWidget {
  const PartnerPresenceBadge({
    super.key,
    required this.coupleId,
    required this.partnerUid,
  });
  final String coupleId;
  final String partnerUid;
  @override
  State<PartnerPresenceBadge> createState() => _PartnerPresenceBadgeState();
}

class _PartnerPresenceBadgeState extends State<PartnerPresenceBadge> {
  late Stream<DatabaseEvent> _events;
  late Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant PartnerPresenceBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupleId != widget.coupleId ||
        oldWidget.partnerUid != widget.partnerUid) {
      _listen();
    }
  }

  void _listen() {
    _ready = authorizePresence(widget.coupleId);
    _events = presenceDatabase
        .ref('couples/${widget.coupleId}/presence/${widget.partnerUid}')
        .onValue;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, access) {
      if (access.hasError) {
        return TextButton.icon(
          onPressed: () => setState(_listen),
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Retry status'),
        );
      }
      if (access.connectionState != ConnectionState.done) {
        return const Text('Connecting…');
      }
      return StreamBuilder<DatabaseEvent>(
        stream: _events,
        builder: (context, snapshot) {
          String label = 'Connecting…';
          Color color = Colors.blueGrey;
          if (snapshot.hasError) {
            label = 'Status unavailable';
          } else if (snapshot.hasData) {
            final data = snapshot.data!.snapshot;
            final states = data
                .child('connections')
                .children
                .map((c) => c.child('state').value);
            if (states.contains('online')) {
              label = 'Online';
              color = const Color(0xFF75D7A0);
            } else if (states.contains('away')) {
              label = 'Away';
              color = const Color(0xFFF0C674);
            } else {
              label = 'Offline';
              final seen = data.child('lastSeen').value;
              if (seen is num) {
                final date = DateTime.fromMillisecondsSinceEpoch(seen.toInt())
                    .toLocal();
                final time = TimeOfDay.fromDateTime(date).format(context);
                label = 'Last seen ${date.day}/${date.month} at $time';
              }
            }
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
