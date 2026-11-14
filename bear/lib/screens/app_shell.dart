import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../services/notification_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/page_frame.dart';
import 'shared_space.dart';
import 'profile_editor.dart';
import 'notification_screen.dart';
import '../services/presence_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user, required this.profile});
  final User user;
  final Map<String, dynamic> profile;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  PresenceService? _presence;

  void _startPresence() {
    unawaited(_presence?.stop());
    final coupleId = widget.profile['coupleId'];
    _presence = coupleId is String && coupleId.isNotEmpty
        ? PresenceService(uid: widget.user.uid, coupleId: coupleId)
        : null;
    unawaited(_presence?.start());
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile['coupleId'] != widget.profile['coupleId']) {
      _startPresence();
    }
  }

  late final NotificationService _notifications;
  int _selected = 0;
  bool _expanded = true;
  bool _signingOut = false;
  static const _titles = ['Our space', 'Profile', 'Notifications', 'Settings'];
  static const _icons = [
    Icons.favorite_outline,
    Icons.person_outline,
    Icons.notifications_outlined,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications = NotificationService(widget.user.uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_notifications.start());
      _startPresence();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_signingOut) {
      unawaited(_notifications.refresh(automatic: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_presence?.stop()); // new
    _notifications.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Bear?'),
        content: const Text(
          'Notifications for this account will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _signingOut = true;
    });
    try {
      await _notifications.prepareSignOut();
      await _presence?.stop();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not safely disconnect this phone. Check your connection and try signing out again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  void _select(int index) => setState(() {
    _selected = index;
  });

  Widget _drawer(String name, String? photo) => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        ProfileAvatar(name: name, photoUrl: photo, radius: 32),
                        const SizedBox(height: 12),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.user.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < _titles.length; i++)
                    ListTile(
                      selected: i == _selected,
                      leading: Icon(_icons[i]),
                      title: Text(_titles[i]),
                      onTap: () {
                        Navigator.pop(context);
                        _select(i);
                      },
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            enabled: !_signingOut,
            onTap: () {
              Navigator.pop(context);
              unawaited(_signOut());
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name = widget.profile['displayName'] as String? ?? 'Your profile';
    final photo = widget.profile['photoUrl'] as String?;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideWeb = kIsWeb && constraints.maxWidth >= 820;
        final compactWeb = kIsWeb && !wideWeb;
        final pages = [
          SharedSpace(user: widget.user, profile: widget.profile),
          ProfileEditor(user: widget.user, profile: widget.profile),
          NotificationScreen(
            service: _notifications,
            user: widget.user,
            profile: widget.profile,
          ),
          _settings(name, photo),
        ];
        return Scaffold(
          drawer: compactWeb ? _drawer(name, photo) : null,
          appBar: AppBar(
            title: Text(_selected == 0 ? 'Bear' : _titles[_selected]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Tooltip(
                  message: name,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _select(1),
                    child: ProfileAvatar(
                      name: name,
                      photoUrl: photo,
                      radius: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Row(
              children: [
                if (wideWeb) _sidebar(name, photo),
                Expanded(
                  child: _signingOut
                      ? const Center(child: CircularProgressIndicator())
                      : IndexedStack(index: _selected, children: pages),
                ),
              ],
            ),
          ),
          bottomNavigationBar: kIsWeb
              ? null
              : NavigationBar(
                  selectedIndex: _selected,
                  onDestinationSelected: _signingOut ? null : _select,
                  destinations: [
                    for (var i = 0; i < _titles.length; i++)
                      NavigationDestination(
                        icon: Icon(_icons[i]),
                        label: _titles[i],
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _sidebar(String name, String? photo) => SizedBox(
    width: _expanded ? 248 : 80,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Align(
                    alignment: _expanded
                        ? Alignment.centerRight
                        : Alignment.center,
                    child: IconButton(
                      tooltip: _expanded
                          ? 'Collapse navigation'
                          : 'Expand navigation',
                      onPressed: () => setState(() {
                        _expanded = !_expanded;
                      }),
                      icon: Icon(
                        _expanded ? Icons.chevron_left : Icons.chevron_right,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: _expanded
                        ? Column(
                            children: [
                              ProfileAvatar(
                                name: name,
                                photoUrl: photo,
                                radius: 32,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.user.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          )
                        : Tooltip(
                            message: name,
                            child: ProfileAvatar(
                              name: name,
                              photoUrl: photo,
                              radius: 22,
                            ),
                          ),
                  ),
                  const Divider(),
                  for (var i = 0; i < _titles.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: _expanded
                          ? ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              selected: i == _selected,
                              selectedTileColor: const Color(0xFF29456C),
                              leading: Icon(_icons[i]),
                              title: Text(_titles[i]),
                              onTap: () => _select(i),
                            )
                          : IconButton.filledTonal(
                              tooltip: _titles[i],
                              isSelected: i == _selected,
                              onPressed: () => _select(i),
                              icon: Icon(_icons[i]),
                            ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _expanded
                ? ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    enabled: !_signingOut,
                    onTap: _signOut,
                  )
                : IconButton(
                    tooltip: 'Sign out',
                    onPressed: _signingOut ? null : _signOut,
                    icon: const Icon(Icons.logout),
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _settings(String name, String? photo) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Make Bear yours',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListTile(
                  leading: ProfileAvatar(name: name, photoUrl: photo),
                  title: Text(name),
                  subtitle: Text(widget.user.email ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _select(1),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Email verified'),
                  subtitle: Text(
                    'Your account is ready for your shared space.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              // const ListTile(
              //   leading: Icon(Icons.dark_mode_outlined),
              //   title: Text('Midnight blue'),
              //   subtitle: Text('Bear’s dark appearance'),
              // ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: const Text('Manage alerts on this device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _select(2),
              ),
              // const ListTile(
              //   leading: Icon(Icons.photo_outlined),
              //   title: Text('Profile picture'),
              //   subtitle: Text(
              //     'Optional. Add an image link or use your initials in Profile.',
              //   ),
              // ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}
