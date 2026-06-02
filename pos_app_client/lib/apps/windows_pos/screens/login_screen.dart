import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
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
  static const Color _backgroundColor = Color(0xFFF4F6FA);
  static const Color _primaryColor = Color(0xFF1E3A8A);

  String pin = '';
  bool _isLoading = false;

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

    if (shellUser != null && !shellUser.canUseManagerMobileApp) {
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

  Widget _buildPinDisplay(bool isSmallScreen) {
    final double slotSize = isSmallScreen ? 38 : 44;
    final double radius = isSmallScreen ? 12 : 14;
    final double elevationAlpha = isSmallScreen ? 0.18 : 0.22;

    return Wrap(
      spacing: isSmallScreen ? 12 : 14,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      children: List.generate(6, (index) {
        final bool isFilled = index < pin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: slotSize,
          height: slotSize,
          decoration: BoxDecoration(
            color: isFilled ? _primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isFilled ? _primaryColor : const Color(0xFFCBD5E1),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isFilled
                    ? _primaryColor.withValues(alpha: elevationAlpha)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: isFilled ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenHeight <= 768 || screenWidth <= 1024;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 32,
              vertical: isSmallScreen ? 24 : 40,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isSmallScreen ? screenWidth * 0.92 : 520,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 24 : 40,
                  vertical: isSmallScreen ? 28 : 36,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(isSmallScreen ? 20 : 24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: isSmallScreen ? 52 : 60,
                          width: isSmallScreen ? 52 : 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _primaryColor.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.lock_outline,
                            size: isSmallScreen ? 26 : 28,
                            color: _primaryColor,
                          ),
                        ),
                        SizedBox(width: isSmallScreen ? 14 : 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'POS Access',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 22 : 26,
                                  fontWeight: FontWeight.w700,
                                  color: _primaryColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enter your secure PIN to continue working.',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 15,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isSmallScreen ? 26 : 32),
                    Center(child: _buildPinDisplay(isSmallScreen)),
                    SizedBox(height: isSmallScreen ? 24 : 32),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 14 : 20,
                        vertical: isSmallScreen ? 18 : 22,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(
                          isSmallScreen ? 18 : 20,
                        ),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          PinPad(
                            onDigitPressed: addDigit,
                            onClearPressed: clearPin,
                            onDeletePressed: deleteDigit,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 24 : 32),
                    if (_isLoading)
                      Center(
                        child: SizedBox(
                          height: 42,
                          width: 42,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            color: _primaryColor,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: isSmallScreen ? 48 : 52,
                        child: ElevatedButton(
                          onPressed: pin.length >= 4 ? _authenticateUser : null,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _primaryColor,
                            disabledBackgroundColor: const Color(0xFFCBD5E1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'ავტორიზაცია',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                      SizedBox(height: isSmallScreen ? 16 : 20),
                      TextButton.icon(
                        onPressed: _isLoading ? null : _launchCompanionApp,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                        icon: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                        ),
                        label: const Text('Companion App (Managers)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
