import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/mobile_auth_service.dart';
import 'package:vynic/core/services/manager_sync_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String pin = '';
  bool _isLoading = false;
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void addDigit(String digit) {
    setState(() {
      if (pin.length < 6) {
        pin += digit;

        // Disable auto-login on mobile to allow access to the "Companion App" button
        final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
        if (!isMobile && pin.length >= 4) {
          _checkPinMatch();
        }
      }
    });
  }

  void _checkPinMatch() async {
    // Check if the current PIN matches any user
    final user = DatabaseService.authenticateByPin(pin);

    if (user != null) {
      // Authentication successful - auto login
      setState(() {
        _isLoading = true;
      });

      // Small delay for visual feedback
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
        );
      }
    }
  }

  Future<void> _authenticateUser() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate a small delay for better UX
    await Future.delayed(const Duration(milliseconds: 300));

    final user = DatabaseService.authenticateByPin(pin);

    if (user != null) {
      // Sync staff credentials to backend so mobile login works
      unawaited(ManagerSyncService.syncToManagerApp());

      // Authentication successful
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
        );
      }
    } else {
      // Authentication failed
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Show error message
        unawaited(showErrorToast(context, 'Invalid PIN code'));

        // Clear PIN after delay
        await Future.delayed(const Duration(milliseconds: 500));
        clearPin();
      }
    }
  }

  void clearPin() {
    setState(() {
      pin = '';
    });
  }

  void deleteDigit() {
    setState(() {
      if (pin.isNotEmpty) {
        pin = pin.substring(0, pin.length - 1);
      }
    });
  }

  /// Launches the Mobile Manager Companion App.
  ///
  /// Flow:
  ///   1. Try to authenticate with the backend using the entered PIN → JWT.
  ///   2. If that fails due to a network error, fall back to a cached JWT
  ///      (valid or within the 7-day grace period) so managers can still
  ///      access the app while offline.
  ///   3. If no cached token is available either, show a clear error.
  Future<void> _launchCompanionApp() async {
    if (pin.length < 4) {
      unawaited(showErrorToast(context, 'გთხოვთ შეიყვანოთ PIN კოდი'));
      return;
    }

    setState(() => _isLoading = true);

    // Build a minimal User object to pass to the shell
    User? shellUser;

    try {
      final result = await MobileAuthService.login(pin);
      shellUser = User(
        username: result.username,
        pinCode: pin,
        role: StaffRole.fromApi(result.role),
      );
    } on MobileAuthError catch (e) {
      if (e == MobileAuthError.networkError) {
        // Try cached token (offline fallback)
        final offline = MobileAuthService.tryOfflineAccess();
        if (offline != null) {
          shellUser = User(
            username: offline.username,
            pinCode: pin,
            role: StaffRole.fromApi(offline.role),
          );
          if (offline.isStale && mounted) {
            unawaited(
              showErrorToast(
                context,
                'ოფლაინ რეჟიმი – ბოლო შესვლის მონაცემებით',
              ),
            );
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            unawaited(
              showErrorToast(context, 'სერვერთან კავშირი ვერ დამყარდა'),
            );
          }
          return;
        }
      } else if (e == MobileAuthError.invalidPin) {
        // Backend Staff table may be empty (first run / DB reset).
        // Fall back to local DB — only valid when the POS runs on this device.
        final localUser = DatabaseService.authenticateByPin(pin);
        if (localUser != null && localUser.canUseManagerMobileApp) {
          // Sync staff to backend FIRST (awaited), then retry login to get JWT.
          await ManagerSyncService.syncToManagerApp();
          try {
            final retryResult = await MobileAuthService.login(pin);
            shellUser = User(
              username: retryResult.username,
              pinCode: pin,
              role: StaffRole.fromApi(retryResult.role),
            );
          } catch (_) {
            // Sync succeeded but login still failed — enter with local user,
            // all API calls will gracefully fall back to cache.
            shellUser = localUser;
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            unawaited(showErrorToast(context, 'არასწორი PIN კოდი'));
            clearPin();
          }
          return;
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          unawaited(showErrorToast(context, MobileAuthService.errorMessage(e)));
          clearPin();
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        unawaited(showErrorToast(context, 'შეცდომა. სცადეთ ახლავე.'));
      }
      return;
    }

    if (!shellUser.canUseManagerMobileApp) {
      await MobileAuthService.logout();
      if (mounted) {
        setState(() => _isLoading = false);
        unawaited(
          showErrorToast(
            context,
            MobileAuthService.errorMessage(MobileAuthError.accessDenied),
          ),
        );
        clearPin();
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ManagerAppShell(user: shellUser!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Scaffold(
      body: LoginDesktopView(
        pin: pin,
        isLoading: _isLoading,
        workDate: DatabaseService.getCurrentDate(),
        now: _now,
        onDigitPressed: addDigit,
        onClearPressed: clearPin,
        onDeletePressed: deleteDigit,
        onLoginPressed: pin.length >= 4 ? _authenticateUser : null,
        onOtherUserPressed: clearPin,
        showCompanionApp: isMobile,
        onCompanionAppPressed: isMobile ? _launchCompanionApp : null,
      ),
    );
  }
}
