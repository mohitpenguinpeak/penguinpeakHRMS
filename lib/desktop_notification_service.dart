import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Displays OS alerts on desktop and web while the signed-in app is running.
/// Remote delivery to a terminated process requires a separate push transport.
class DesktopNotificationService {
  DesktopNotificationService._();
  static final instance = DesktopNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;
  bool _ready = false;
  int _nextId = 0;

  bool get supported =>
      kIsWeb ||
      [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform);

  Future<void> initialize() async {
    if (!supported || _ready) return;
    try {
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              macOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              linux: LinuxInitializationSettings(
                defaultActionName: 'Open leave requests',
              ),
              windows: WindowsInitializationSettings(
                appName: 'PenguinPeak HRMS',
                appUserModelId: 'PenguinPeak.HRMS',
                guid: '14d04fc0-c1dc-4922-8ae5-b519056eb172',
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              if (response.payload != null) _taps.add(response.payload!);
            },
          ) ??
          false;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'leave_requests',
                'Leave requests',
                description: 'New employee leave applications',
                importance: Importance.high,
              ),
            );
      }
    } catch (error) {
      debugPrint('Desktop notification setup failed: $error');
    }
  }

  /// Must be invoked from a button click to comply with browser permission rules.
  Future<bool> enableAndTest() async {
    // Request web permission before any async initialization loses user activation.
    if (kIsWeb) {
      final allowed = await _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (allowed != true) return false;
    }
    await initialize();
    if (!_ready) return false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final allowed = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (allowed != true) return false;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final allowed = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (allowed != true) return false;
    }
    await _show(
      'Notification test',
      'PenguinPeak HRMS device alerts are enabled.',
      'test',
    );
    return true;
  }

  Future<void> show(Map<String, dynamic> notice) async {
    if (!_ready) return;
    try {
      await _show(
        notice['title'] as String,
        notice['body'] as String,
        notice['id'].toString(),
      );
    } catch (error) {
      // An OS permission or notification-server failure must not break the inbox.
      debugPrint('Desktop alert failed: $error');
    }
  }

  Future<void> _show(String title, String body, String payload) => _plugin.show(
    id: _nextId++ % 2147483647,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'leave_requests',
        'Leave requests',
        channelDescription: 'New employee leave applications',
        importance: Importance.high,
        priority: Priority.high,
      ),
      macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    ),
  );
}
