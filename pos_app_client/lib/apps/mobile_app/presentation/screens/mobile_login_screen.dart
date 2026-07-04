import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isLoading = false;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _addDigit(String d) {
    if (_pin.length >= 6 || _isLoading) return;
    setState(() => _pin += d);
    if (_pin.length == 6) {
      unawaited(_login());
    }
  }

  void _deleteDigit() {
    if (_pin.isEmpty || _isLoading) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _clearPin() => setState(() => _pin = '');

  Future<void> _login() async {
    if (_pin.length < 4) {
      ManagerToast.show(context, 'გთხოვთ შეიყვანოთ PIN კოდი', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    User? shellUser;

    try {
      final result = await MobileAuthService.login(_pin);
      shellUser = User(
        username: result.username,
        pinCode: _pin,
        role: StaffRole.fromApi(result.role),
      );
    } on MobileAuthError catch (e) {
      if (e == MobileAuthError.networkError) {
        final offline = MobileAuthService.tryOfflineAccess();
        if (offline != null) {
          shellUser = User(
            username: offline.username,
            pinCode: _pin,
            role: StaffRole.fromApi(offline.role),
          );
          if (offline.isStale && mounted) {
            ManagerToast.show(
              context,
              'ოფლაინ რეჟიმი – ბოლო შესვლის მონაცემებით',
              isError: false,
            );
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            ManagerToast.show(
              context,
              'სერვერთან კავშირი ვერ დამყარდა',
              isError: true,
            );
          }
          return;
        }
      } else if (e == MobileAuthError.invalidPin) {
        if (mounted) {
          setState(() => _isLoading = false);
          ManagerToast.show(context, 'არასწორი PIN კოდი', isError: true);
          _clearPin();
        }
        return;
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ManagerToast.show(
            context,
            MobileAuthService.errorMessage(e),
            isError: true,
          );
          _clearPin();
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ManagerToast.show(context, 'შეცდომა. სცადეთ ახლავე.', isError: true);
      }
      return;
    }

    if (shellUser != null && !shellUser.canUseManagerMobileApp) {
      await MobileAuthService.logout();
      if (mounted) {
        setState(() => _isLoading = false);
        ManagerToast.show(
          context,
          MobileAuthService.errorMessage(MobileAuthError.accessDenied),
          isError: true,
        );
        _clearPin();
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
    return MobileGlassScreen(
      orbs: [
        Positioned(
          top: -120,
          right: -80,
          child: MobileGlowOrb(color: MobileGlassTheme.primary, size: 320),
        ),
        Positioned(
          bottom: -60,
          left: -100,
          child: MobileGlowOrb(color: MobileGlassTheme.accent, size: 280),
        ),
        Positioned(
          top: 180,
          left: -40,
          child: MobileGlowOrb(color: MobileGlassTheme.good, size: 180),
        ),
      ],
      body: Stack(
        children: [
          Positioned.fill(child: _LoginGridBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBrandHeader(),
                    SizedBox(height: 28),
                    MobileGlassCard(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      radius: 28,
                      borderColor: MobileGlassTheme.primary.withValues(
                        alpha: 0.25,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'შეიყვანეთ PIN კოდი',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: MobileGlassTheme.muted(0.75),
                              letterSpacing: 0.4,
                            ),
                          ),
                          SizedBox(height: 24),
                          _buildPinDots(),
                          SizedBox(height: 28),
                          _buildNumberPad(),
                          SizedBox(height: 24),
                          if (_isLoading)
                            Center(
                              child: SizedBox(
                                height: 48,
                                width: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: MobileGlassTheme.primary,
                                ),
                              ),
                            )
                          else
                            _LoginGradientButton(
                              label: 'შესვლა',
                              enabled: _pin.length >= 4,
                              onPressed: _login,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'დაცული წვდომა • PIN ავტორიზაცია',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: MobileGlassTheme.muted(0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    final theme = managerThemeOf(context);
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final t = _pulseController.value;
            return Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MobileGlassTheme.primary.withValues(alpha: 0.22 + t * 0.08),
                    MobileGlassTheme.primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(
                  color: MobileGlassTheme.primary.withValues(
                    alpha: 0.35 + t * 0.15,
                  ),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: MobileGlassTheme.primary.withValues(
                      alpha: 0.18 + t * 0.12,
                    ),
                    blurRadius: 28 + t * 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/logo/vynicnew.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: 22),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              theme.textPrimary,
              MobileGlassTheme.primary,
              MobileGlassTheme.accent,
            ],
            stops: const [0.2, 0.65, 1],
          ).createShader(bounds),
          child: Text(
            'Vynic Manager',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: theme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'რესტორნის მართვის სისტემა',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: MobileGlassTheme.muted(0.55),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < _pin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: filled ? 16 : 14,
          height: filled ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? MobileGlassTheme.primary
                : MobileGlassTheme.surface(0.08),
            border: Border.all(
              color: filled
                  ? MobileGlassTheme.primary.withValues(alpha: 0.9)
                  : MobileGlassTheme.border(0.22),
              width: 1.5,
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: MobileGlassTheme.primary.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildNumberPad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((label) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _LoginPadButton(
                  label: label,
                  onTap: () {
                    if (label == '⌫') {
                      _deleteDigit();
                    } else if (label == 'C') {
                      _clearPin();
                    } else {
                      _addDigit(label);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _LoginGridBackground extends StatelessWidget {
  const _LoginGridBackground();

  @override
  Widget build(BuildContext context) {
    final theme = managerThemeOf(context);
    return CustomPaint(
      painter: _GridPainter(theme),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.theme);

  final DashboardThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 36.0;
    final gridColor = theme.isDark
        ? Colors.white.withValues(alpha: 0.045)
        : theme.textPrimary.withValues(alpha: 0.06);
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final center = Offset(size.width * 0.5, size.height * 0.38);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.primary.withValues(alpha: 0.06);
    canvas.drawCircle(
      center,
      math.min(size.width, size.height) * 0.42,
      ringPaint,
    );
    canvas.drawCircle(
      center,
      math.min(size.width, size.height) * 0.28,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.theme != theme;
}

class _LoginPadButton extends StatefulWidget {
  const _LoginPadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_LoginPadButton> createState() => _LoginPadButtonState();
}

class _LoginPadButtonState extends State<_LoginPadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = managerThemeOf(context);
    final isDelete = widget.label == '⌫';
    final isClear = widget.label == 'C';
    final isAction = isDelete || isClear;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 100),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: theme.useGlassCards
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: _padFace(
                    theme: theme,
                    pressed: _pressed,
                    isDelete: isDelete,
                    isClear: isClear,
                    isAction: isAction,
                  ),
                )
              : _padFace(
                  theme: theme,
                  pressed: _pressed,
                  isDelete: isDelete,
                  isClear: isClear,
                  isAction: isAction,
                ),
        ),
      ),
    );
  }

  Widget _padFace({
    required DashboardThemeData theme,
    required bool pressed,
    required bool isDelete,
    required bool isClear,
    required bool isAction,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 84,
      height: 58,
      decoration: BoxDecoration(
        color: pressed
            ? theme.primary.withValues(alpha: 0.18)
            : theme.heroCardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDelete
              ? theme.bad.withValues(alpha: pressed ? 0.5 : 0.28)
              : isClear
              ? theme.warn.withValues(alpha: pressed ? 0.5 : 0.28)
              : theme.cardBorder,
        ),
        boxShadow: pressed
            ? [
                BoxShadow(
                  color:
                      (isDelete
                              ? theme.bad
                              : isClear
                              ? theme.warn
                              : theme.primary)
                          .withValues(alpha: 0.2),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: isAction ? 20 : 24,
            fontWeight: FontWeight.w700,
            color: isDelete
                ? theme.bad
                : isClear
                ? theme.warn
                : theme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _LoginGradientButton extends StatelessWidget {
  const _LoginGradientButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: enabled
                  ? LinearGradient(
                      colors: [
                        MobileGlassTheme.primary,
                        MobileGlassTheme.accent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: enabled ? null : MobileGlassTheme.surface(0.12),
              border: Border.all(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.12)
                    : MobileGlassTheme.border(0.12),
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: MobileGlassTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
