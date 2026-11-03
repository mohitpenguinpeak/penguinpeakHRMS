import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:penguinpeak_hrms/desktop_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android creates leave channel and posts a system notification', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'initialize' ? true : null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final service = DesktopNotificationService.instance;
    await service.initialize();
    await service.show({
      'id': 'notice-1',
      'title': 'New leave application',
      'body': 'Employee applied for leave.',
    });

    final created = calls.singleWhere((call) => call.method == 'createNotificationChannel');
    expect(created.arguments['id'], 'leave_requests');
    final shown = calls.singleWhere((call) => call.method == 'show');
    expect(shown.arguments['title'], 'New leave application');
    expect(shown.arguments['payload'], 'notice-1');
    expect(shown.arguments['platformSpecifics']['channelId'], 'leave_requests');
  });
}
