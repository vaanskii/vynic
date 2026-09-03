import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic_devtool/src/code_format.dart';
import 'package:vynic_devtool/src/otp_store.dart';

/// The Unlocker carries its own copy of the chain maths and the code alphabet,
/// because depending on the POS package would drag the point-of-sale into this
/// build. Duplication is the cheaper coupling, but only while the two halves
/// stay identical — a drift here means codes this tool prints are rejected by
/// every terminal, discovered on a support call.
void main() {
  test('the chain matches the POS implementation step for step', () {
    final seed = List<int>.generate(32, (i) => (i * 31 + 7) % 256);

    // Recomputed here the long way rather than calling the same helper, so a
    // change to OtpStore has something independent to disagree with.
    var expected = sha256.convert(seed).bytes.sublist(0, OtpStore.linkBytes);
    for (var i = 0; i < 25; i++) {
      expect(OtpStore.linkAt(seed, i), expected, reason: 'index $i');
      expected = sha256.convert(expected).bytes.sublist(0, OtpStore.linkBytes);
    }
  });

  test('the alphabet round trips', () {
    final link = List<int>.generate(OtpStore.linkBytes, (i) => i * 17 % 256);
    final code = encodeDeveloperCode(link);

    expect(code.replaceAll('-', '').length, 16);
    expect(decodeDeveloperCode(code), link);
  });

  test('the code alphabet is byte-identical to the POS copy', () {
    // Compares the source files directly. Anything less would pass while the
    // two drifted, which is the failure this test exists to catch.
    final mine = File('lib/src/code_format.dart').readAsStringSync();
    final theirs = File(
      '../operations/lib/core/services/security/developer_code_format.dart',
    ).readAsStringSync();

    String body(String source) =>
        source.substring(source.indexOf("const String _alphabet"));

    expect(body(mine), body(theirs));
  });
}
