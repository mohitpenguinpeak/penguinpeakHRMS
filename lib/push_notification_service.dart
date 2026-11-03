import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'features/auth/domain/account_access.dart';

/// Firebase remote delivery for mobile, macOS and the browser companion.
class PushNotificationService {
  static final instance = PushNotificationService._();
  PushNotificationService._();

  bool _ready = false;
  bool _registered = false;
  bool get hasRegistration => _registered;
  bool get isReady => _ready;
  String? _token;
  final _db = Supabase.instance.client;

  Future<void> initialize() async {
    final pushEnabled = const bool.hasEnvironment('PUSH_ENABLED')
        ? const bool.fromEnvironment('PUSH_ENABLED')
        : !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!pushEnabled ||
        (!kIsWeb &&
            ![
              TargetPlatform.android,
              TargetPlatform.iOS,
              TargetPlatform.macOS,
            ].contains(defaultTargetPlatform))) {
      return;
    }
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
            appId: String.fromEnvironment('FIREBASE_APP_ID'),
            messagingSenderId: String.fromEnvironment(
              'FIREBASE_MESSAGING_SENDER_ID',
            ),
            projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          ),
        );
      } else {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
      }
      _ready = true;
      // These APIs supply the FCM registration token used by HTTP v1 sends.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        _token = token;
        await _register();
      });
      _db.auth.onAuthStateChange.listen((event) {
        if (event.session != null)
          unawaited(register(requestPermission: !kIsWeb));
      });
      await register(requestPermission: !kIsWeb);
    } catch (error) {
      debugPrint('Push initialization failed: $error');
    }
  }

  /// Web permission requests must originate from the user's button press.
  Future<bool> register({bool requestPermission = true}) async {
    if (!_ready || _db.auth.currentUser == null) return false;
    try {
      final settings = requestPermission
          ? await FirebaseMessaging.instance.requestPermission()
          : await FirebaseMessaging.instance.getNotificationSettings();
      if (![
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ].contains(settings.authorizationStatus)) {
        return false;
      }
      if (!kIsWeb &&
          [
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          ].contains(defaultTargetPlatform) &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        return false;
      }
      const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
      if (kIsWeb && vapidKey.isEmpty) return false;
      _token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );
      return await _register();
    } catch (error) {
      debugPrint('Push registration failed: $error');
      return false;
    }
  }

  Future<bool> _register() async {
    if (_token == null || _db.auth.currentUser == null) return false;
    try {
      final profile = await _db
          .from('profiles')
          .select('approval_status, role')
          .eq('id', _db.auth.currentUser!.id)
          .maybeSingle();
      if (!AccountAccess.fromProfile(profile).isApproved) {
        _registered = false;
        return false;
      }
      await _db.rpc('register_push_token', params: {'p_token': _token});
      _registered = true;
      return true;
    } catch (error) {
      debugPrint('Push token could not be saved: $error');
      return false;
    }
  }

  /// Call before sign-out so this installation stops receiving account alerts.
  Future<void> unregister() async {
    if (!_ready) return;
    final token =
        _token ??
        await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb
              ? const String.fromEnvironment('FIREBASE_VAPID_KEY')
              : null,
        );
    if (token != null) {
      await _db.from('push_tokens').delete().eq('token', token);
    }
    await FirebaseMessaging.instance.deleteToken();
    _token = null;
    _registered = false;
  }
}
