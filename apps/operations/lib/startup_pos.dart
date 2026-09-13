import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  await DatabaseService.init(createBootstrapManager: false);
  await EdgeDeviceCredentialStore.load();
  await PosDisplaySettingsController.loadFromStorage();
  await PrinterService.initialize();
  ManagerSyncService.initialize();
  unawaited(EdgeTransportService.instance().start());
  unawaited(InventoryProjectionSyncService.instance().start());
  unawaited(RuntimeConfigSync.instance.start());
  runApp(const PosApp());
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // On mobile, just allow exit without the Windows-style confirmation dialog
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
      await InventoryProjectionSyncService.instance().stop();
      await RuntimeConfigSync.instance.stop();
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
              child: activityAwareChild,
            );
          },
        );
      },
      home: const PosFirstRun(),
    );
  }
}
