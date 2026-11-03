import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'desktop_notification_service.dart';
import 'push_notification_service.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    throw StateError(
      'Supabase configuration is missing. '
      'Run with --dart-define-from-file=supabase.env.json',
    );
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);

  await DesktopNotificationService.instance.initialize();
  await PushNotificationService.instance.initialize();

  runApp(const PenguinPeakApp());
}

class PenguinPeakApp extends StatelessWidget {
  const PenguinPeakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'PenguinPeak HRMS',
          debugShowCheckedModeBanner: false,
          theme: AppThemes.light,
          darkTheme: AppThemes.dark,
          themeMode: mode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
