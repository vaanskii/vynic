import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic_devtool/src/signing_key.dart';

/// The tool is only useful if the key it loads is the one customers' terminals
/// trust. This catches the case where `keygen --force` was run and the POS was
/// never rebuilt — the tokens would look fine and be rejected everywhere.
void main() {
  final keyFile = File('../secrets/developer_signing_key.json');

  test(
    'the repository key is the one the shipped POS accepts',
    () async {
      final key = await SigningKeyStore.loadFrom(keyFile.path);

      expect(
        key.matchesShippedBuild,
        isTrue,
        reason:
            'secrets/developer_signing_key.json no longer matches '
            'kShippedPublicKeyBase64. Re-run keygen and update both the POS '
            'constant and this tool, or restore the matching private key.',
      );
    },
    skip: keyFile.existsSync() ? false : 'no private key on this machine',
  );

  test('a file that is not a key is rejected clearly', () async {
    final temp = await Directory.systemTemp.createTemp('devtool_key_test');
    final bogus = File('${temp.path}/not-a-key.json')
      ..writeAsStringSync('{"hello": "world"}');

    await expectLater(
      SigningKeyStore.loadFrom(bogus.path),
      throwsA(isA<FormatException>()),
    );

    await temp.delete(recursive: true);
  });
}
