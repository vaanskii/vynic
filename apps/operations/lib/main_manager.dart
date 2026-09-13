import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'apps/mobile_app/theme/manager_theme.dart';
import 'apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'core/services/auth/auth_token_service.dart';
import 'core/services/manager_app/mobile_cache_service.dart';
import 'core/services/manager_app/manager_app_preferences.dart';
import 'core/services/notifications/local_notifications_service.dart';
import 'core/services/notifications/firebase_messaging_service.dart';
import 'core/services/sync/api_config.dart';
import 'core/services/pos/app_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.validateBuild();
  AppMode.printHostOverride = false;
  await Hive.initFlutter('VynicManager');
  await Future.wait([
    AuthTokenService.init(),
    MobileCacheService.init(),
    ManagerAppPreferences.init(),
  ]);
  try {
    final notifications = LocalNotificationsService.instance();
    await notifications.init();
    if (Platform.isAndroid || Platform.isIOS) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseMessagingService.instance().init(
        localNotificationsService: notifications,
      );
    }
  } catch (error) {
    debugPrint('Manager notifications unavailable: $error');
  }
  runApp(
    const MaterialApp(
      title: 'Vynic Manager',
      debugShowCheckedModeBanner: false,
      home: ManagerThemeListener(child: MobileLoginScreen()),
    ),
  );
}
