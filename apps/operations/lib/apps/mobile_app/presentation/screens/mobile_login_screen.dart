import 'package:vynic/core/models/manager_venue_selection.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/manager_app_shell.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key, this.client, this.onAuthenticated});
  final http.Client? client;
  final void Function(User user)? onAuthenticated;

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen> {
  String _pin = '';
  ManagerVenueSelection? _selectedVenue;
  String? _selectionError;
  final _venueCode = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedVenue = ManagerAppPreferences.selectedVenue(ApiConfig.baseUrl);
  }

  @override
  void dispose() {
    _venueCode.dispose();
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

  Future<void> _selectVenue() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _selectionError = null;
    });
    try {
      final venue = await MobileAuthService.linkVenue(
        _venueCode.text,
        client: widget.client,
      );
      // A validated selection must not inherit an older origin/session cache.
      await MobileAuthService.logout();
      await ManagerAppPreferences.rememberVenue(venue);
      _venueCode
          .clear(); // The one-use secret is not retained in preferences or the form.
      if (mounted)
        setState(() {
          _selectedVenue = venue;
          _pin = '';
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _selectionError = error == MobileAuthError.networkError
              ? 'კავშირი ვერ დამყარდა. სცადეთ იგივე კოდით ხელახლა.'
              : error == MobileAuthError.rateLimited
              ? 'მცდელობები დროებით შეზღუდულია. სცადეთ მოგვიანებით.'
              : error == MobileAuthError.serverError
              ? 'დაკავშირება ვერ დასრულდა. სცადეთ იგივე კოდით ხელახლა.'
              : 'ერთჯერადი კოდი მიუწვდომელია ან ვადა ამოიწურა. ახალი კოდი Vynic-ის მხარდაჭერისგან მიიღეთ.',
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _switchVenue() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await MobileAuthService.logout();
      await ManagerAppPreferences.clearVenue();
      if (mounted)
        setState(() {
          _selectedVenue = null;
          _venueCode.clear();
          _pin = '';
          _selectionError = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _selectionError =
              'რესტორნის შეცვლა ვერ დასრულდა. სცადეთ ხელახლა.',
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    final selection = _selectedVenue;
    if (_isLoading || selection == null) return;
    FocusScope.of(context).unfocus();
    if (_pin.length < 4) {
      ManagerToast.show(context, 'გთხოვთ შეიყვანოთ PIN კოდი', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    User? shellUser;

    try {
      final result = await MobileAuthService.login(
        _pin,
        venueCode: selection.code,
        client: widget.client,
      );
      shellUser = User(
        username: result.username,
        pinCode: '',
        role: StaffRole.fromApi(result.role),
      );
    } on MobileAuthError catch (e) {
      if (e == MobileAuthError.networkError) {
        final offline = MobileAuthService.tryOfflineAccess(
          venueCode: selection.code,
        );
        if (offline != null) {
          shellUser = User(
            username: offline.username,
            pinCode: '',
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
            // Naming the address turns „it will not connect" into something
            // the person holding the phone can act on: nearly every case is a
            // stale IP, or the emulator default on a real handset.
            ManagerToast.show(
              context,
              ApiConfig.allowDeveloperOverride
                  ? 'ვერ დაუკავშირდა: ${ApiConfig.baseUrl}'
                  : 'სერვერთან კავშირი ვერ დამყარდა. გადაამოწმეთ ინტერნეტი.',
              isError: true,
            );
          }
          return;
        }
      } else if (e == MobileAuthError.invalidPin) {
        if (mounted) {
          setState(() => _isLoading = false);
          ManagerToast.show(
            context,
            'არასწორი რესტორნის კოდი ან PIN',
            isError: true,
          );
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

    final User user = shellUser;

    if (!user.canUseManagerMobileApp) {
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
      _pin = '';
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!(user);
        setState(() => _isLoading = false);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ManagerAppShell(user: user)),
      );
    }
  }

  Future<void> _editBackendUrl() async {
    if (_isLoading || !ApiConfig.allowDeveloperOverride) return;

    final controller = TextEditingController(text: ApiConfig.baseUrl);
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('სერვერის მისამართი'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'შეიყვანეთ Windows POS სერვერის IP მისამართი '
                '(მაგ. http://192.168.1.50:3000).',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.50:3000',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ManagerAppPreferences.setBackendUrlOverride(null);
                ApiConfig.resetResolvedUrlLog();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('ნაგულისხმევი'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('გაუქმება'),
            ),
            ElevatedButton(
              onPressed: () async {
                final normalized = ApiConfig.normalizeEditableBackendUrl(
                  controller.text,
                );
                if (normalized == null) {
                  setLocal(() => error = 'არასწორი მისამართი');
                  return;
                }
                await ManagerAppPreferences.setBackendUrlOverride(normalized);
                ApiConfig.resetResolvedUrlLog();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('შენახვა'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (saved == true && mounted) {
      await _switchVenue();
      if (!mounted) return;
      setState(() {});
      ManagerToast.show(context, 'სერვერის მისამართი შენახულია');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagerThemeListener(
      child: Builder(
        builder: (context) {
          final theme = managerThemeOf(context);
          return Scaffold(
            backgroundColor: theme.scaffoldBackground,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 960;
                  final form = ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!wide) ...[
                          _buildBrandHeader(),
                          const SizedBox(height: 32),
                        ],
                        _buildConnectionSwitcher(),
                        MobileGlassCard(
                          radius: 22,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _selectedVenue == null
                                    ? Icons.storefront_outlined
                                    : Icons.lock_outline_rounded,
                                color: theme.primary,
                                size: 30,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedVenue == null
                                    ? 'რესტორანთან დაკავშირება'
                                    : 'კეთილი იყოს დაბრუნება',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_selectionError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _selectionError!,
                                      style: TextStyle(
                                        color: theme.bad,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_selectedVenue == null) ...[
                                Text(
                                  'ერთხელ დააკავშირეთ აპლიკაცია თქვენს რესტორანთან.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                TextField(
                                  key: const Key('manager-venue-code'),
                                  controller: _venueCode,
                                  enabled: !_isLoading,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  obscureText: true,
                                  maxLength: 32,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _selectVenue(),
                                  onChanged: (_) => _clearPin(),
                                  decoration: const InputDecoration(
                                    labelText: 'დაკავშირების კოდი',
                                    hintText: 'ერთჯერადი კოდი',
                                    counterText: '',
                                    helperText:
                                        'კოდი მიიღეთ Vynic-ის მხარდაჭერისგან. შემდეგ მხოლოდ PIN დაგჭირდებათ.',
                                    helperMaxLines: 3,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _isLoading ? null : _selectVenue,
                                  child: Text(
                                    _isLoading ? 'მოწმდება…' : 'გაგრძელება',
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  _selectedVenue!.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: theme.primary,
                                  ),
                                ),
                                if (_selectedVenue!.branchName?.isNotEmpty ??
                                    false)
                                  Text(
                                    _selectedVenue!.branchName!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                    ),
                                  ),
                                if (_selectedVenue!.address?.isNotEmpty ??
                                    false)
                                  Text(
                                    _selectedVenue!.address!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                Focus(
                                  autofocus: true,
                                  onKeyEvent: (_, event) {
                                    if (event is! KeyDownEvent || _isLoading)
                                      return KeyEventResult.ignored;
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.backspace) {
                                      _deleteDigit();
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter) {
                                      if (_pin.length >= 4) _login();
                                      return KeyEventResult.handled;
                                    }
                                    final digit = event.character;
                                    if (digit != null &&
                                        RegExp(r'^[0-9]$').hasMatch(digit)) {
                                      _addDigit(digit);
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: Column(
                                    children: [
                                      Text(
                                        'შეიყვანეთ PIN კოდი',
                                        style: TextStyle(
                                          color: theme.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      _buildPinDots(),
                                      const SizedBox(height: 18),
                                      _buildNumberPad(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: !_isLoading && _pin.length >= 4
                                      ? _login
                                      : null,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('შესვლა'),
                                ),
                                const SizedBox(height: 6),
                                TextButton(
                                  onPressed: _isLoading ? null : _switchVenue,
                                  child: const Text('რესტორნის შეცვლა'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'დაცული წვდომა · Vynic Manager',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 400 ? 16 : 32,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 56),
                      ),
                      child: Center(
                        child: wide
                            ? ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1050,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 80,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildBrandHeader(),
                                            const SizedBox(height: 48),
                                            Text(
                                              'თქვენი რესტორანი.\nერთი სამუშაო სივრცე.',
                                              style: TextStyle(
                                                fontSize: 38,
                                                height: 1.35,
                                                fontWeight: FontWeight.w700,
                                                color: theme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            Text(
                                              'მაგიდები, რეზერვაციები, ფინანსები და გუნდი — ყველაფერი ერთად.',
                                              style: TextStyle(
                                                fontSize: 16,
                                                height: 1.7,
                                                color: theme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    form,
                                  ],
                                ),
                              )
                            : form,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBrandHeader() {
    final theme = managerThemeOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'vynic',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'MANAGER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: theme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionSwitcher() {
    if (!ApiConfig.allowDeveloperOverride) return const SizedBox.shrink();
    final theme = managerThemeOf(context);
    return ValueListenableBuilder<String?>(
      valueListenable: ManagerAppPreferences.backendUrlOverride,
      builder: (context, _, _) {
        final url = ApiConfig.baseUrl;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _editBackendUrl,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.heroCardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: theme.primary.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'სერვერი',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MobileGlassTheme.muted(0.58),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: MobileGlassTheme.muted(_isLoading ? 0.25 : 0.55),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinDots() {
    final theme = managerThemeOf(context);
    return Semantics(
      label: 'PIN: ${_pin.length} ციფრი შეყვანილია',
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? theme.primary : theme.surfaceMuted,
                border: Border.all(
                  color: i < _pin.length ? theme.primary : theme.cardBorder,
                ),
              ),
            ),
        ],
      ),
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
              return Flexible(
                child: Padding(
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
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _LoginPadButton extends StatelessWidget {
  const _LoginPadButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: 52,
    child: OutlinedButton(
      onPressed: onTap,
      child: Semantics(
        label: label == '⌫'
            ? 'ბოლო ციფრის წაშლა'
            : label == 'C'
            ? 'PIN-ის გასუფთავება'
            : label,
        child: label == '⌫'
            ? const Icon(Icons.backspace_outlined, size: 22)
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    ),
  );
}
