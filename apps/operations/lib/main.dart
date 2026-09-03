import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/staff_lock_screen.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/pos/app_mode.dart';
import 'package:vynic/core/services/pos/pos_display_settings_controller.dart';
import 'package:vynic/core/services/notifications/firebase_messaging_service.dart';
import 'package:vynic/core/services/notifications/local_notifications_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/sync/pos_ingest_server.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
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
    await Hive.initFlutter();
    await Future.wait([
      AuthTokenService.init(),
      MobileCacheService.init(),
      ManagerAppPreferences.init(),
    ]);
    final localNotifications = LocalNotificationsService.instance();
    await localNotifications.init();
    await FirebaseMessagingService.instance().init(
      localNotificationsService: localNotifications,
    );
    if (AuthTokenService.hasValidToken || AuthTokenService.hasStaleToken) {
      await FirebaseMessagingService.instance().syncCurrentTokenWithBackend();
    }
    runApp(const MyApp(isMobile: true));
    return;
  }

  // ── Desktop manager / tester client (APP_ROLE=client) ───────────────────────
  // Thin client of a remote Windows POS backend (e.g. Mac on the LAN). Runs the
  // manager UI only and deliberately does NOT init the POS database, start the
  // ingest server, push manager-data sync, or initialize printing. The Windows
  // POS remains the sole source of truth and print host.
  // Role resolves from --dart-define=APP_ROLE first (lets you flip POS vs manager
  // on the same machine without editing .env), then falls back to the bundled
  // .env. e.g. `flutter run -d macos --dart-define=APP_ROLE=pos` forces the POS UI.
  const roleFromDefine = String.fromEnvironment('APP_ROLE');
  final appRole =
      (roleFromDefine.isNotEmpty
              ? roleFromDefine
              : (dotenv.env['APP_ROLE'] ?? ''))
          .toLowerCase()
          .trim();
  final isDesktopClient = appRole == 'client';
  if (isDesktopClient) {
    await Hive.initFlutter();
    await Future.wait([
      AuthTokenService.init(),
      MobileCacheService.init(),
      ManagerAppPreferences.init(),
    ]);
    // Non-essential for a tester — never let a notification hiccup block the UI.
    try {
      await LocalNotificationsService.instance().init();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[main] LocalNotifications init skipped: $e');
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[main] APP_ROLE=client → manager client '
        '(no POS DB / ingest / sync / printing)',
      );
    }
    runApp(const MyApp(isMobile: true));
    return;
  }

  // ── Windows / macOS / Linux POS ────────────────────────────────────────────
  SessionLock.configureRoutes(
    lockRouteBuilder: staffLockRoute,
    loginBuilder: (_) =>
        LoginScreen(companionAppBuilder: (user) => ManagerAppShell(user: user)),
  );

  // Initialize database, run migrations, and prepare app data.
  await DatabaseService.init();
  // Read this installation's Cloud identity now that the data directory exists.
  // Never fails the boot: no credential just means no cloud transport.
  await EdgeDeviceCredentialStore.load();
  await PosDisplaySettingsController.loadFromStorage();
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

  // Cloud pull: claim and execute Cloud-originated work. Deliberately not
  // awaited — a POS must open its till whether or not Cloud is reachable, and
  // an installation with no device credential simply never starts polling.
  unawaited(EdgeTransportService.instance().start());

  runApp(const MyApp(isMobile: false));
}

class MyApp extends StatefulWidget {
  final bool isMobile;
  const MyApp({super.key, required this.isMobile});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Root navigator key lives on SessionLock so the idle auto-lock can push the
  // lock screen from outside any widget context.
  static GlobalKey<NavigatorState> get navigatorKey => SessionLock.navigatorKey;

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
      await EdgeTransportService.instance().stop();
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
      // App-wide activity detector: any pointer interaction resets the POS idle
      // auto-lock countdown. No-op until SessionLock is armed (POS login), so it
      // costs nothing on the mobile manager app.
      builder: (context, child) {
        final activityAwareChild = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => SessionLock.recordActivity(),
          onPointerSignal: (_) => SessionLock.recordActivity(),
          child: child ?? const SizedBox.shrink(),
        );
        if (widget.isMobile) {
          return activityAwareChild;
        }
        return ValueListenableBuilder(
          valueListenable: PosDisplaySettingsController.settings,
          builder: (context, settings, _) {
            return PosScaledSurface(
              scale: settings.scaleFactor,
              child: activityAwareChild,
            );
          },
        );
      },
      home: widget.isMobile
          ? const ManagerThemeListener(child: MobileLoginScreen())
          : LoginScreen(
              companionAppBuilder: (user) => ManagerAppShell(user: user),
            ),
    );
  }
}
