import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'dart:io' show Platform;
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_quit.dart';
import 'package:vynic/apps/windows_pos/widgets/pos_quit_action.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/widgets/connection_feedback.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/apps/windows_pos/screens/login_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/staff_lock_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/pos/app_mode.dart';
import 'package:vynic/core/services/pos/pos_display_settings_controller.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/inventory_projection_sync_service.dart';
import 'package:vynic/core/services/auth/session_lock.dart';

import 'core/services/sync/api_config.dart';
import 'core/services/edge/runtime_config_sync.dart';
import 'apps/windows_pos/screens/pos_first_run.dart';

Future<void> startPos() async {
  ApiConfig.validateBuild();
  AppMode.printHostOverride = true;
  SessionLock.configureRoutes(
    lockRouteBuilder: staffLockRoute,
    loginBuilder: (_) => const LoginScreen(),
  );
  try {
    final dataDirectory = await PosUpdater.instance.pinnedDataDirectory();
    await DatabaseService.init(
      createBootstrapManager: false,
      managedDataDirectory: dataDirectory,
    );
  } catch (error, stack) {
    debugPrint('POS local data startup failed: $error\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'ადგილობრივ მონაცემებზე წვდომა ვერ მოხერხდა.\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  if (Platform.isWindows) PosQuit.enableWindowsTracking();
  await EdgeDeviceCredentialStore.load();
  await PosDisplaySettingsController.loadFromStorage();
  PosInputSettings.load();
  await PrinterService.initialize();
  await PosUpdater.instance.initialize();
  runApp(const PosApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await PosUpdater.instance.startAfterFirstFrame();
    if (PosQuit.instance.shutdownStarted) return;
    ManagerSyncService.initialize();
    unawaited(EdgeTransportService.instance().start());
    unawaited(InventoryProjectionSyncService.instance().start());
    unawaited(RuntimeConfigSync.instance.start());
  });
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> with WidgetsBindingObserver {
  // Root navigator key lives on SessionLock so the idle auto-lock can push the
  // lock screen from outside any widget context.
  static GlobalKey<NavigatorState> get navigatorKey => SessionLock.navigatorKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_recordKeyActivity);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_recordKeyActivity);
    super.dispose();
  }

  bool _recordKeyActivity(KeyEvent event) {
    if (event is KeyDownEvent) SessionLock.recordActivity();
    return false;
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!Platform.isWindows) return AppExitResponse.exit;
    final context = navigatorKey.currentContext;
    if (context == null) return AppExitResponse.cancel;
    return await confirmPosQuit(context)
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    return PosLocaleHost(
      child: Builder(
        builder: (context) => MaterialApp(
          locale: Locale(PosLocale.code(context)),
          supportedLocales: const [Locale('ka'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: 'Vynic POS',
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
            return ValueListenableBuilder(
              valueListenable: PosDisplaySettingsController.settings,
              builder: (context, settings, _) {
                return PosScaledSurface(
                  scale: settings.scaleFactor,
                  child: PosUpdateHost(
                    navigatorKey: navigatorKey,
                    child: PosInputScope(
                      child: ConnectionFeedback.pos(child: activityAwareChild),
                    ),
                  ),
                );
              },
            );
          },
          home: const PosFirstRun(),
        ),
      ),
    );
  }
}
