import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/services/security/developer_code_format.dart';
import 'package:vynic/core/services/security/developer_otp.dart';
import 'package:vynic/core/services/security/developer_otp_chain.dart';

/// Proves the Unlocker and the POS are looking at the same chain.
///
/// The seed lives in `secrets/`, so this only runs on the developer's machine —
/// which is the machine where a mismatch would otherwise go unnoticed until a
/// venue was already on the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final seedFile = File('../secrets/developer_otp_seed.json');

  test(
    'codes cut from the shipped seed open a shipped build',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('otp_roundtrip');
      Hive.init(tempDir.path);
      DatabaseCore.settingsBox = await Hive.openBox('settings_otp_roundtrip');
      DeveloperAccess.otpTipOverride = null;
      DeveloperAccess.resetForTest();

      try {
        final stored =
            json.decode(seedFile.readAsStringSync()) as Map<String, dynamic>;
        final seed = base64Url.decode(stored['seed'] as String);
        final chainLength = stored['chainLength'] as int;

        expect(
          DeveloperOtpChain.encodeTip(
            DeveloperOtpChain.linkAt(seed, chainLength),
          ),
          kDeveloperOtpTip,
          reason:
              'secrets/developer_otp_seed.json and developer_otp.dart have '
              'drifted apart — re-run `dart run tool/dev_key.dart otp-seed` and '
              'paste the printed tip.',
        );

        // The next two codes the tool would hand out, used in order.
        for (var offset = 1; offset <= 2; offset++) {
          final code = encodeDeveloperCode(
            DeveloperOtpChain.linkAt(seed, chainLength - offset),
          );
          final result = await DeveloperAccess.unlockWithOneTimeCode(code);
          expect(result.isSuccess, isTrue, reason: 'code $offset');
          expect(DeveloperAccess.can(DeveloperScope.wipe), isTrue);
          DeveloperAccess.lock();
        }
      } finally {
        DeveloperAccess.resetForTest();
        await DatabaseCore.settingsBox?.deleteFromDisk();
        DatabaseCore.settingsBox = null;
        await Hive.close();
        await tempDir.delete(recursive: true);
      }
    },
    skip: seedFile.existsSync() ? false : 'no code seed on this machine',
  );
}
