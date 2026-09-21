import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/database_service.dart';
import 'login_screen.dart';

class PosFirstRun extends StatefulWidget {
  const PosFirstRun({super.key});
  @override
  State<PosFirstRun> createState() => _PosFirstRunState();
}

class _PosFirstRunState extends State<PosFirstRun> {
  final _code = TextEditingController();
  final _address = TextEditingController(text: ApiConfig.baseUrl);
  final _service = PosEnrollmentService();
  bool _busy = false;
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
    if (DatabaseService.isSetupComplete()) return const LoginScreen();
    if (!PosEnrollmentService.needsEnrollment) {
      return StreamBuilder<dynamic>(
        stream: DatabaseService.userBox?.watch(),
        builder: (context, snapshot) {
          if (DatabaseService.userBox?.isNotEmpty ?? false) {
            return const LoginScreen();
          }
          return Scaffold(
            appBar: _updateBar(),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Vynic POS დაკავშირებულია.\n'
                    'მენეჯერის წვდომის მიღების მოლოდინში…\n'
                    'დატოვეთ POS დაკავშირებული ინტერნეტთან. '
                    'მენეჯერის შექმნა და მიწოდების მდგომარეობა ნახეთ რესტორნის გვერდზე.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: _updateBar(),
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
                  const SizedBox(height: 24),
                  if (ApiConfig.allowDeveloperOverride)
                    TextField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Development API URL',
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
                            setState(() {
                              _busy = false;
                              _error = result.isConnected
                                  ? null
                                  : result.message ??
                                        'დაკავშირება ვერ მოხერხდა';
                              if (result.isConnected) _code.clear();
                            });
                          },
                    child: Text(
                      _busy ? 'უკავშირდება…' : 'მოწყობილობის დაკავშირება',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
