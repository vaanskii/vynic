import 'dart:io';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/core/services/app_mode.dart';
import 'package:vynic/core/services/firebase_messaging_service.dart';
import 'package:vynic/core/services/local_notifications_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/services/auth_token_service.dart';
import 'package:vynic/core/services/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_sync_service.dart';
import 'package:vynic/core/services/pos_ingest_server.dart';
import 'package:vynic/firebase_options.dart';

/// True when the process is running on Android or iOS.
bool get _isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables gracefully preventing hard-crashes
  try {
    await dotenv.load(fileName: '.env');
    if (kDebugMode) {
      final backend = dotenv.env['BACKEND_URL']?.trim();
      debugPrint(
        backend != null && backend.isNotEmpty
            ? '[main] Loaded .env — BACKEND_URL=$backend'
            : '[main] Loaded .env — BACKEND_URL not set (using ApiConfig default)',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Warning: .env file not found or could not be loaded: $e');
    }
  }

  if (_isMobilePlatform) {
    // ── Mobile (Android / iOS) ──────────────────────────────────────────────
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final localNotifications = LocalNotificationsService.instance();
    await localNotifications.init();
    await FirebaseMessagingService.instance().init(
      localNotificationsService: localNotifications,
    );
    await Hive.initFlutter();
    await Future.wait([AuthTokenService.init(), MobileCacheService.init()]);
    if (AuthTokenService.hasValidToken || AuthTokenService.hasStaleToken) {
      await FirebaseMessagingService.instance().syncCurrentTokenWithBackend();
    }
    runApp(const MyApp(isMobile: true));
    return;
  }

  // ── Windows / macOS / Linux POS ────────────────────────────────────────────

  // Initialize database, run migrations, and prepare app data.
  await DatabaseService.init();
  if (kDebugMode) {}

  // Initialize mobile-specific services (safe to call on all platforms)
  await Future.wait([AuthTokenService.init(), MobileCacheService.init()]);

  final printHostOverride = dotenv.env['PRINT_HOST']?.toLowerCase().trim();
  if (printHostOverride == 'true') {
    AppMode.printHostOverride = true;
  } else if (printHostOverride == 'false') {
    AppMode.printHostOverride = false;
  } else {
    AppMode.printHostOverride = null;
  }

  if (AppMode.isPrintHost) {
    await PrinterService.initialize();
  }

  // Option A: local HTTP ingest (all desktop POS — mobile→server→Hive callbacks).
  await PosIngestServer.start();

  // Cloud push: audit debounce + periodic manager-data sync (Windows POS only).
  ManagerSyncService.initialize();

  runApp(const MyApp(isMobile: false));
}

class MyApp extends StatefulWidget {
  final bool isMobile;
  const MyApp({super.key, required this.isMobile});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // On mobile, just allow exit without the Windows-style confirmation dialog
    if (widget.isMobile) return AppExitResponse.exit;
    final bool? shouldExit = await _showExitConfirmation();
    if (shouldExit == true) {
      // Clean up all background services
      await _cleanupAndExit();
      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  Future<void> _cleanupAndExit() async {
    try {
      await PosIngestServer.stop();
      PrinterService.dispose();
      // Small delay to ensure sockets are closed
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint('Error during cleanup: $e');
    }
  }

  Future<bool?> _showExitConfirmation() {
    final context = navigatorKey.currentContext;
    if (context == null) return Future.value(true);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 40,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: Color(0xFFEF4444),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'პროგრამიდან გამოსვლა',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ნამდვილად გსურთ პროგრამის დახურვა? ყველა აქტიური პროცესი შეწყდება.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'გამოსვლა',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: widget.isMobile ? const MobileLoginScreen() : const LoginScreen(),
    );
  }
}
