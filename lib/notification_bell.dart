import 'shared/widgets/app_toast.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_notification_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/notifications/domain/notification_destination.dart';
import 'desktop_notification_service.dart';

/// A persistent inbox refreshed while the dashboard is open.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.role,
    required this.onNavigate,
  });

  final String role;
  final ValueChanged<NotificationDestination> onNavigate;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  final _db = Supabase.instance.client;
  final _revision = ValueNotifier<int>(0);
  Timer? _timer;
  StreamSubscription<String>? _desktopTaps;
  Set<String>? _knownIds;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = false;
  bool _clearing = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _desktopTaps = DesktopNotificationService.instance.taps.listen((id) {
      if (!mounted || id == 'test') return;
      unawaited(_openNoticeId(id.toString()));
    });
    final webId = kIsWeb ? Uri.base.queryParameters['notification_id'] : null;
    if (webId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openNoticeId(webId));
      });
    }
    final launchId = DesktopNotificationService.instance.takeLaunchPayload();
    if (launchId != null && launchId != 'test') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openNoticeId(launchId));
      });
    }
    if (PushNotificationService.instance.isReady) {
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        if (!mounted) return;
        unawaited(_load());
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          unawaited(
            DesktopNotificationService.instance.show({
              'id':
                  message.data['notification_id'] ??
                  message.messageId ??
                  'workspace',
              'destination': message.data['screen'],
              'title': message.notification?.title ?? 'New HRMS notification',
              'body':
                  message.notification?.body ?? 'Open HRMS to view the update.',
            }),
          );
        }
        AppToast.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification?.title ?? 'New notification'),
            action: SnackBarAction(label: 'View', onPressed: _open),
          ),
        );
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_openPush);
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) _openPush(message);
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  void _openPush(RemoteMessage message) {
    if (!mounted) return;
    final id = message.data['notification_id'];
    // Fetch the recipient-owned inbox row, rather than trusting push routing data.
    if (id != null) unawaited(_openNoticeId(id.toString()));
  }

  Future<void> _openNoticeId(String id) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || !mounted) return;
    try {
      final item = await _db
          .from('notifications')
          .select()
          .eq('id', id)
          .eq('recipient_id', uid)
          .maybeSingle();
      if (!mounted || _db.auth.currentUser?.id != uid || item == null) return;
      await _activate(item);
    } catch (_) {
      if (mounted) {
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open notification. Please retry from the inbox.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _activate(Map<String, dynamic> item) async {
    final target = NotificationDestination.fromMap(item);
    if (target == null) return;
    final uid = _db.auth.currentUser?.id;
    if (uid == null || item['recipient_id'] != uid) return;
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', item['id'])
        .eq('recipient_id', uid);
    if (!mounted || _db.auth.currentUser?.id != uid) return;
    widget.onNavigate(target);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _desktopTaps?.cancel();
    _foreground?.cancel();
    _opened?.cancel();
    _revision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (_loading || _clearing || uid == null) return;
    final generation = _loadGeneration;
    _loading = true;
    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('recipient_id', uid)
          .isFilter('dismissed_at', null)
          .order('created_at', ascending: false);
      if (!mounted) return;
      if (generation != _loadGeneration || _db.auth.currentUser?.id != uid) {
        return;
      }
      final notices = List<Map<String, dynamic>>.from(rows);
      final knownIds = _knownIds;
      _knownIds = notices.map((row) => row['id'].toString()).toSet();
      if (knownIds != null &&
          !PushNotificationService.instance.hasRegistration) {
        for (final notice in notices) {
          if (notice['read_at'] == null &&
              !knownIds.contains(notice['id'].toString())) {
            unawaited(DesktopNotificationService.instance.show(notice));
          }
        }
      }
      setState(() {
        _items = notices;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load notifications. Please retry.');
    } finally {
      _loading = false;
      if (mounted) _revision.value++;
    }
  }

  Future<void> _clearNotifications() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || _clearing || _items.isEmpty) return;
    final ids = _items.map((item) => item['id'].toString()).toList();
    setState(() => _clearing = true);
    _loadGeneration++;
    _revision.value++;
    try {
      await _db
          .from('notifications')
          .update({'dismissed_at': DateTime.now().toUtc().toIso8601String()})
          .eq('recipient_id', uid)
          .inFilter('id', ids);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => ids.contains(item['id'].toString()));
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not clear notifications. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
        _revision.value++;
      }
    }
  }

  Future<void> _open() async {
    unawaited(_load());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.7,
        child: ValueListenableBuilder<int>(
          valueListenable: _revision,
          builder: (context, revision, child) => Column(
            children: [
              ListTile(
                title: const Text('Notifications'),
                trailing: IconButton(
                  tooltip: 'Refresh notifications',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _clearing || _items.isEmpty
                        ? null
                        : _clearNotifications,
                    icon: const Icon(Icons.clear_all),
                    label: Text(
                      _clearing ? 'Clearing…' : 'Clear notifications',
                    ),
                  ),
                ),
              ),
              if (PushNotificationService.instance.isReady)
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Enable push notifications'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Receive alerts after closing the HRMS tab.'
                        : 'Allow this device to receive remote alerts.',
                  ),
                  onTap: () async {
                    final enabled = await PushNotificationService.instance
                        .register();
                    if (!mounted) return;
                    AppToast.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          enabled
                              ? 'Push notifications enabled on this device.'
                              : 'Push registration failed. Check permissions and configuration, then retry.',
                        ),
                      ),
                    );
                  },
                ),
              if (DesktopNotificationService.instance.supported)
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Enable and test device alerts'),
                  subtitle: const Text(
                    'Send a test notification to this device.',
                  ),
                  onTap: () async {
                    try {
                      final enabled = await DesktopNotificationService.instance
                          .enableAndTest();
                      if (!mounted) return;
                      AppToast.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            enabled
                                ? 'Test alert sent. Check your system notification settings if it is hidden.'
                                : 'Notifications are blocked or unavailable. Check device permissions.',
                          ),
                        ),
                      );
                    } catch (_) {
                      if (!mounted) return;
                      AppToast.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not display a test alert. Check device notification settings.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          _loading ? 'Loading…' : 'No notifications yet',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            leading: Icon(
                              item['read_at'] == null
                                  ? Icons.mark_email_unread_outlined
                                  : Icons.drafts_outlined,
                            ),
                            title: Text(item['title'] as String),
                            subtitle: Text(item['body'] as String),
                            onTap: () async {
                              try {
                                if (!mounted || !sheetContext.mounted) return;
                                Navigator.pop(sheetContext);
                                await _activate(item);
                              } catch (_) {
                                if (!mounted) return;
                                AppToast.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open notification. Please retry.',
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => item['read_at'] == null).length;
    return IconButton(
      tooltip: _error ?? 'Notifications ($unread unread)',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
