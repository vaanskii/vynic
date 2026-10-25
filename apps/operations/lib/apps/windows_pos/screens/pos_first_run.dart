import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/auth/manager_activation_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/database_service.dart';
import 'login_screen.dart';
import 'pos_manager_registration_screen.dart';

class PosFirstRun extends StatefulWidget {
  const PosFirstRun({
    super.key,
    this.service,
    this.activationClient,
    this.enrollmentOnly = false,
  });

  /// A dedicated connection route remains available for configured restaurants.
  final bool enrollmentOnly;
  final PosEnrollmentService? service;
  final http.Client? activationClient;
  @override
  State<PosFirstRun> createState() => _PosFirstRunState();
}

class _PosFirstRunState extends State<PosFirstRun> {
  final _code = TextEditingController();
  final _address = TextEditingController(text: ApiConfig.baseUrl);
  late final _service = widget.service ?? PosEnrollmentService();
  bool _busy = false;
  bool _reconnecting = false;
  Future<PosManagerSetupStatus>? _setupFuture;
  String? _setupDeviceId;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    _address.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Existing configured restaurants retain local access even before fleet enrollment.
    if (!widget.enrollmentOnly && DatabaseService.isSetupComplete())
      return const LoginScreen();
    if (!widget.enrollmentOnly &&
        !PosEnrollmentService.needsEnrollment &&
        !_reconnecting) {
      return StreamBuilder<dynamic>(
        stream: DatabaseService.userBox?.watch(),
        builder: (context, snapshot) {
          if (DatabaseService.userBox?.isNotEmpty ?? false) {
            return const LoginScreen();
          }
          final deviceId = EdgeDeviceCredentialStore.deviceId;
          if (_setupFuture == null || _setupDeviceId != deviceId) {
            _setupDeviceId = deviceId;
            _setupFuture = PosManagerSetupService.load(
              client: widget.activationClient,
            );
          }
          return FutureBuilder<PosManagerSetupStatus>(
            future: _setupFuture,
            builder: (context, setupSnapshot) {
              final setup = setupSnapshot.data;
              final legacy = setup?.state == 'LEGACY_INVITATION';
              final message = switch (setup?.state) {
                'READY' =>
                  'POS დაკავშირებულია. შექმენით პირველი Manager თქვენი სახელითა და პირადი PIN-ით.',
                'RECONNECT_REQUIRED' =>
                  'POS-ის შენახული წვდომა სერვერმა უარყო. ხელახლა დააკავშირეთ POS მოწყობილობის ახალი კოდით.',
                'EXPIRED' =>
                  'პირველი Manager-ის რეგისტრაციის ვადა ამოიწურა. მიიღეთ ახალი დაკავშირების კოდი.',
                'COMPLETED' || 'EXISTING_MANAGER' =>
                  'მენეჯერის წვდომის მიღების მოლოდინში… დატოვეთ POS ინტერნეტთან დაკავშირებული.',
                'WAITING_PRIMARY' =>
                  'პირველი Manager შექმენით მთავარ POS-ზე. ეს დამატებითი POS მის წვდომას სინქრონიზაციის შემდეგ მიიღებს.',
                'LEGACY_INVITATION' =>
                  'მენეჯერის წვდომის მიღების მოლოდინში… ეს მოწყობილობა რეგისტრაციის ძველ პროცესს იყენებს.',
                null => 'POS-ის კავშირი მოწმდება…',
                _ =>
                  'რეგისტრაციის შემოწმება ვერ მოხერხდა. გადაამოწმეთ კავშირი და სცადეთ ხელახლა.',
              };
              return Scaffold(
                appBar: _updateBar(),
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(message, textAlign: TextAlign.center),
                          if (setup?.ready == true || legacy) ...[
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: () => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          PosManagerRegistrationScreen(
                                            client: widget.activationClient,
                                            setupId: setup?.ready == true
                                                ? setup!.setupId
                                                : null,
                                          ),
                                    ),
                                  )
                                  .then((_) {
                                    if (mounted)
                                      setState(() => _setupFuture = null);
                                  }),
                              child: Text(
                                legacy
                                    ? 'პირველი აქტივაცია'
                                    : 'Manager-ის შექმნა',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _reconnecting = true;
                              _error = null;
                            }),
                            child: const Text('POS-ის ხელახლა დაკავშირება'),
                          ),
                          if (setup?.state == 'UNAVAILABLE')
                            TextButton(
                              onPressed: () =>
                                  setState(() => _setupFuture = null),
                              child: const Text('ხელახლა შემოწმება'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }
    final form = Scaffold(
      appBar: widget.enrollmentOnly ? AppBar() : _updateBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Vynic POS',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'შეიყვანეთ თქვენი რესტორნის გვერდზე მიღებული მოწყობილობის კოდი.',
                  ),
                  if (_reconnecting ||
                      (widget.enrollmentOnly &&
                          !PosEnrollmentService.needsEnrollment)) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'ხელახალი დაკავშირება ცვლის ამ POS-ის წვდომას. '
                      'გამოიყენეთ მოწყობილობის enrollment კოდი, '
                      'და არა მენეჯერის აქტივაციის კოდი.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (ApiConfig.allowDeveloperOverride)
                    TextField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Development API URL',
                        helperText:
                            'Same Mac: http://api.vynic.localhost · '
                            'LAN/Windows: http://<Mac LAN IP>:8088',
                        helperMaxLines: 2,
                      ),
                    ),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'მოწყობილობის კოდი',
                      hintText: 'XXXX-XXXX-XXXX',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() {
                              _busy = true;
                              _error = null;
                            });
                            final result = await _service.enroll(
                              serverAddress: ApiConfig.allowDeveloperOverride
                                  ? _address.text
                                  : ApiConfig.baseUrl,
                              code: _code.text,
                            );
                            if (!mounted) return;
                            if (result.isConnected && widget.enrollmentOnly) {
                              Navigator.of(context).pop(true);
                              return;
                            }
                            setState(() {
                              _busy = false;
                              _error = result.isConnected
                                  ? null
                                  : result.message ??
                                        'დაკავშირება ვერ მოხერხდა';
                              if (result.isConnected) {
                                _code.clear();
                                _reconnecting = false;
                                _setupFuture = null;
                              }
                            });
                          },
                    child: Text(
                      _busy ? 'უკავშირდება…' : 'მოწყობილობის დაკავშირება',
                    ),
                  ),
                  if (_reconnecting) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _code.clear();
                              setState(() {
                                _reconnecting = false;
                                _error = null;
                              });
                            },
                      child: const Text('გაუქმება'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(canPop: !_busy, child: form);
  }

  PreferredSizeWidget? _updateBar() => !kIsWeb && Platform.isWindows
      ? AppBar(
          actions: [
            TextButton.icon(
              onPressed: () => showPosUpdateDialog(context),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('პროგრამის განახლება'),
            ),
          ],
        )
      : null;
}
