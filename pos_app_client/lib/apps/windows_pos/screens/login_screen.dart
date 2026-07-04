import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.companionAppBuilder});

  final Widget Function(User user)? companionAppBuilder;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Holds the entered PIN as a listenable so keystrokes update only the PIN
  // dots + login button (via ValueListenableBuilder in LoginDesktopView) rather
  // than rebuilding the whole login card on every digit.
  final ValueNotifier<String> _pin = ValueNotifier<String>('');
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
    _pin.dispose();
    super.dispose();
  }

  void addDigit(String digit) {
    if (_pin.value.length >= 6) return;
    _pin.value = _pin.value + digit;

    // Disable auto-login on mobile to allow access to the "Companion App" button
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobile && _pin.value.length >= 4) {
      _checkPinMatch();
    }
  }

  void _checkPinMatch() {
    // Check if the current PIN matches any user
    final user = DatabaseService.authenticateByPin(_pin.value);

    if (user != null) {
      // Authentication successful — navigate immediately for a snappy feel.
      setState(() {
        _isLoading = true;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
      );

      // Push staff credentials + flush pending changes AFTER the transition,
      // so the heavy serialization never competes with the screen animation.
      _schedulePostLoginSync();
    }
  }

  /// Fires the manager-data sync a moment after login so the heavy payload
  /// serialization never competes with the navigation transition (the cause
  /// of the post-PIN stutter).
  void _schedulePostLoginSync() {
    Future.delayed(const Duration(milliseconds: 600), () {
      unawaited(ManagerSyncService.syncToManagerApp());
    });
  }

  Future<void> _authenticateUser() async {
    final user = DatabaseService.authenticateByPin(_pin.value);

    if (user != null) {
      // Authentication successful — navigate immediately.
      setState(() {
        _isLoading = true;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
      );

      // Defer credential sync until after the transition.
      _schedulePostLoginSync();
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
    _pin.value = '';
  }

  void deleteDigit() {
    if (_pin.value.isNotEmpty) {
      _pin.value = _pin.value.substring(0, _pin.value.length - 1);
    }
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
    if (_pin.value.length < 4) {
      unawaited(showErrorToast(context, 'გთხოვთ შეიყვანოთ PIN კოდი'));
      return;
    }

    setState(() => _isLoading = true);

    // Build a minimal User object to pass to the shell
    User? shellUser;

    try {
      final result = await MobileAuthService.login(_pin.value);
      shellUser = User(
        username: result.username,
        pinCode: _pin.value,
        role: StaffRole.fromApi(result.role),
      );
    } on MobileAuthError catch (e) {
      if (e == MobileAuthError.networkError) {
        // Try cached token (offline fallback)
        final offline = MobileAuthService.tryOfflineAccess();
        if (offline != null) {
          shellUser = User(
            username: offline.username,
            pinCode: _pin.value,
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
        final localUser = DatabaseService.authenticateByPin(_pin.value);
        if (localUser != null && localUser.canUseManagerMobileApp) {
          // Sync staff to backend FIRST (awaited), then retry login to get JWT.
          await ManagerSyncService.syncToManagerApp();
          try {
            final retryResult = await MobileAuthService.login(_pin.value);
            shellUser = User(
              username: retryResult.username,
              pinCode: _pin.value,
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
      final companionAppBuilder = widget.companionAppBuilder;
      if (companionAppBuilder == null) {
        setState(() => _isLoading = false);
        unawaited(showErrorToast(context, 'Companion app is not configured'));
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => companionAppBuilder(shellUser!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Scaffold(
      body: LoginDesktopView(
        pin: _pin,
        isLoading: _isLoading,
        workDate: DatabaseService.getCurrentDate(),
        now: _now,
        onDigitPressed: addDigit,
        onClearPressed: clearPin,
        onDeletePressed: deleteDigit,
        onLoginPressed: _authenticateUser,
        onOtherUserPressed: clearPin,
        showCompanionApp: isMobile && widget.companionAppBuilder != null,
        onCompanionAppPressed: isMobile && widget.companionAppBuilder != null
            ? _launchCompanionApp
            : null,
      ),
    );
  }
}
