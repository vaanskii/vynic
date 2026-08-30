import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/services/security/developer_code_format.dart';
import 'package:vynic/core/services/security/developer_otp_chain.dart';

/// One-time codes are the convenient path, so they are the one most worth
/// being suspicious of. Sixteen characters cannot hold a signature; what makes
/// them safe instead is that each code is a hash preimage of the last, spent
/// the moment it is used.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<int> seed;
  // Longer than the acceptance window, so a code can actually be placed
  // *outside* it — at 400 the out-of-window index went negative, wrapped to
  // the chain root, and landed back inside.
  const chainLength = 800;

  /// The code a terminal expects at [index], counting back from the tip.
  String codeAt(int index) =>
      encodeDeveloperCode(DeveloperOtpChain.linkAt(seed, index));

  setUp(() async {
    final random = Random(7);
    seed = List<int>.generate(32, (_) => random.nextInt(256));

    tempDir = await Directory.systemTemp.createTemp('dev_otp_test');
    Hive.init(tempDir.path);
    DatabaseCore.settingsBox = await Hive.openBox('settings_otp_test');
    DeveloperAccess.resetForTest();
    DeveloperAccess.otpTipOverride = DeveloperOtpChain.encodeTip(
      DeveloperOtpChain.linkAt(seed, chainLength),
    );
  });

  tearDown(() async {
    DeveloperAccess.otpTipOverride = null;
    DeveloperAccess.resetForTest();
    await DatabaseCore.settingsBox?.deleteFromDisk();
    DatabaseCore.settingsBox = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('the next code opens the panel with every tool', () async {
    final result = await DeveloperAccess.unlockWithOneTimeCode(
      codeAt(chainLength - 1),
    );

    expect(result.isSuccess, isTrue);
    expect(DeveloperAccess.can(DeveloperScope.wipe), isTrue);
    expect(DeveloperAccess.can(DeveloperScope.restore), isTrue);
  });

  test('the same code will not open it twice', () async {
    // The property the whole scheme rests on. Once spent, the terminal has
    // moved past that link and hashing forward no longer arrives at the tip.
    final code = codeAt(chainLength - 1);
    expect(
      (await DeveloperAccess.unlockWithOneTimeCode(code)).isSuccess,
      isTrue,
    );
    DeveloperAccess.lock();

    final replay = await DeveloperAccess.unlockWithOneTimeCode(code);

    expect(replay.failure, DeveloperUnlockFailure.spentCode);
    expect(DeveloperAccess.isUnlocked, isFalse);
  });

  test('codes work in sequence', () async {
    for (var i = 1; i <= 4; i++) {
      final result = await DeveloperAccess.unlockWithOneTimeCode(
        codeAt(chainLength - i),
      );
      expect(result.isSuccess, isTrue, reason: 'code $i');
      DeveloperAccess.lock();
    }
  });

  test('a skipped-ahead code is accepted', () async {
    // Terminals drift behind the issuing tool — one venue serviced twice a
    // month, another once a year. Every code the tool skipped has to still
    // work, or a rarely-visited terminal becomes unreachable.
    final result = await DeveloperAccess.unlockWithOneTimeCode(
      codeAt(chainLength - 60),
    );

    expect(result.isSuccess, isTrue);
  });

  test('a code beyond the window is refused', () async {
    final result = await DeveloperAccess.unlockWithOneTimeCode(
      codeAt(chainLength - (DeveloperOtpChain.defaultWindow + 50)),
    );

    expect(result.failure, DeveloperUnlockFailure.spentCode);
  });

  test('an older code cannot be replayed after a newer one is spent', () async {
    // Someone who kept last month's code cannot use it once a later code has
    // moved the terminal past it.
    final older = codeAt(chainLength - 1);
    await DeveloperAccess.unlockWithOneTimeCode(codeAt(chainLength - 10));
    DeveloperAccess.lock();

    final result = await DeveloperAccess.unlockWithOneTimeCode(older);

    expect(result.failure, DeveloperUnlockFailure.spentCode);
  });

  test('a code from a different chain is refused', () async {
    final otherSeed = List<int>.generate(32, (i) => i * 3 + 1);
    final foreign = encodeDeveloperCode(
      DeveloperOtpChain.linkAt(otherSeed, chainLength - 1),
    );

    final result = await DeveloperAccess.unlockWithOneTimeCode(foreign);

    expect(result.failure, DeveloperUnlockFailure.spentCode);
  });

  test('garbage is refused without throwing', () async {
    for (final junk in const ['', 'hello', '1234', '!!!!-!!!!-!!!!-!!!!']) {
      final result = await DeveloperAccess.unlockWithOneTimeCode(junk);
      expect(result.isSuccess, isFalse, reason: junk);
    }
  });

  test('a mistyped code is forgiven the ways a phone call mangles it', () async {
    // Lower case, missing dashes, stray spaces, and the letters people confuse
    // for digits. The alternative is a support call failing on a typo.
    final code = codeAt(chainLength - 1);
    final mangled = code
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('1', 'l')
        .replaceAll('0', 'O');

    final result = await DeveloperAccess.unlockWithOneTimeCode(mangled);

    expect(result.isSuccess, isTrue);
  });

  test('a code is sixteen characters in four groups', () {
    final code = codeAt(chainLength - 1);

    expect(code.replaceAll('-', '').length, 16);
    expect(code.split('-'), hasLength(4));
  });

  test('spending a code survives a restart', () async {
    // The tip lives in Hive, not memory: closing the app must not hand a
    // client back a code they already watched get used.
    final code = codeAt(chainLength - 1);
    await DeveloperAccess.unlockWithOneTimeCode(code);
    DeveloperAccess.resetForTest();

    final replay = await DeveloperAccess.unlockWithOneTimeCode(code);

    expect(replay.failure, DeveloperUnlockFailure.spentCode);
  });
}
