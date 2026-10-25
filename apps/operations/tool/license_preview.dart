import 'package:vynic/core/ui/pos_theme.dart';
// Synthetic licensing UI only: no database, enrollment, HTTP or operational startup.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/licensing/license_host.dart';
import 'package:vynic/core/services/licensing/subscription_license.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final elapsed = await const MethodChannel(
    'ge.vynic/license',
  ).invokeMethod<int>('elapsed');
  if (elapsed == null || elapsed < 0)
    throw StateError('Native clock unavailable');
  debugPrint('LICENSE_PREVIEW_NATIVE_CLOCK_OK');
  final license = SubscriptionLicense()..enabled = true;
  license.lease.kind = 'TRIAL';
  license.lease.restrict('EXPIRED');
  runApp(
    PosLocale(
      language: 'ka',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: PosTheme.light,
        home: LicenseHost(
          license: license,
          child: const Scaffold(
            body: Center(child: Text('Synthetic records — no restaurant data')),
          ),
        ),
      ),
    ),
  );
}
