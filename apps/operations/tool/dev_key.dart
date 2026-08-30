// Developer unlock key tool — keygen and token signing.
//
// The POS ships only the *public* key. Unlock tokens are signed here, on the
// developer's own machine, with a private key that never leaves `secrets/`.
// That is the whole point: a client holding the binary, the Hive files and a
// disassembler still cannot mint a token, because the signing half was never
// on their terminal.
//
//   dart run tool/dev_key.dart keygen
//   dart run tool/dev_key.dart sign --terminal <id> --hours 8
//   dart run tool/dev_key.dart sign --terminal '*' --hours 2 --scopes wipe
//
// Run from the apps/operations directory.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:vynic/core/services/security/developer_code_format.dart';
import 'package:vynic/core/services/security/developer_otp_chain.dart';

const _keyDirectory = '../secrets';
const _privateKeyFile = '$_keyDirectory/developer_signing_key.json';

final _algorithm = Ed25519();

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }

  switch (args.first) {
    case 'keygen':
      await _keygen(force: args.contains('--force'));
    case 'sign':
      await _sign(_parseFlags(args.skip(1)));
    case 'otp-seed':
      await _otpSeed(force: args.contains('--force'));
    case 'otp':
      await _otp(_parseFlags(args.skip(1)));
    case 'master':
      await _sign({
        'terminal': '*',
        'hours': '2160',
        ..._parseFlags(args.skip(1)),
      });
    default:
      _usage();
      exit(64);
  }
}

void _usage() {
  stderr.writeln('''
Vynic developer unlock key tool.

  dart run tool/dev_key.dart keygen [--force]
      Creates an Ed25519 keypair. The private key is written to
      $_privateKeyFile (gitignored). The public key is printed for
      pasting into lib/core/services/security/developer_public_key.dart.

  dart run tool/dev_key.dart sign --terminal <id> [--hours 8] [--scopes a,b]
      Signs an unlock token for one terminal. Pass --terminal '*' for a
      token any terminal accepts (install day only — it is a master key).

  dart run tool/dev_key.dart otp-seed [--force]
      Creates the one-time-code chain. Prints the tip to paste into
      lib/core/services/security/developer_otp.dart.

  dart run tool/dev_key.dart otp [--count 1]
      Prints the next one-time code(s). Sixteen characters, works once,
      no terminal id needed.

      Scopes: diagnostics, connection, printers, errors, backup, restore,
              wipe, recovery. Default is every scope.

  dart run tool/dev_key.dart master
      Shorthand for `sign --terminal '*' --hours 2160` — a 90-day token that
      opens any terminal. This is the one to keep in your password manager.
''');
}

Map<String, String> _parseFlags(Iterable<String> args) {
  final flags = <String, String>{};
  final list = args.toList();
  for (var i = 0; i < list.length; i++) {
    final arg = list[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    final next = i + 1 < list.length ? list[i + 1] : null;
    if (next != null && !next.startsWith('--')) {
      flags[name] = next;
      i++;
    } else {
      flags[name] = 'true';
    }
  }
  return flags;
}

Future<void> _keygen({required bool force}) async {
  final file = File(_privateKeyFile);
  if (file.existsSync() && !force) {
    stderr.writeln(
      'A signing key already exists at $_privateKeyFile.\n'
      'Regenerating it invalidates every terminal already running a build '
      'that carries the old public key. Pass --force if you mean it.',
    );
    exit(1);
  }

  final keyPair = await _algorithm.newKeyPair();
  final privateBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  Directory(_keyDirectory).createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'algorithm': 'ed25519',
      'privateKey': base64Url.encode(privateBytes),
      'publicKey': base64Url.encode(publicKey.bytes),
      'createdAt': DateTime.now().toIso8601String(),
    }),
  );
  // Owner read/write only. Best effort — no-op on Windows.
  try {
    Process.runSync('chmod', ['600', file.path]);
  } catch (_) {}

  stdout.writeln('Private key written to $_privateKeyFile — never commit it.');
  stdout.writeln('');
  stdout.writeln('Paste this into developer_public_key.dart:');
  stdout.writeln('');
  stdout.writeln("  '${base64Url.encode(publicKey.bytes)}'");
}

Future<void> _sign(Map<String, String> flags) async {
  final file = File(_privateKeyFile);
  if (!file.existsSync()) {
    stderr.writeln('No signing key at $_privateKeyFile. Run keygen first.');
    exit(1);
  }

  final terminal = flags['terminal'];
  if (terminal == null || terminal.isEmpty) {
    stderr.writeln(
      "Pass --terminal <id>. The id is shown in the POS unlock dialog. "
      "Use '*' only for a terminal you cannot read the id from.",
    );
    exit(64);
  }

  final hours = int.tryParse(flags['hours'] ?? '8') ?? 8;
  // The ceiling is a year. A master token you keep in a password manager wants
  // months, not days — the expiry is there so a leaked token dies on its own,
  // not to make routine work tedious.
  if (hours < 1 || hours > 8760) {
    stderr.writeln('--hours must be between 1 and 8760 (one year).');
    exit(64);
  }

  final scopes = (flags['scopes'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final stored = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  final keyPair = await _algorithm.newKeyPairFromSeed(
    base64Url.decode(stored['privateKey'] as String),
  );

  final issuedAt = DateTime.now().toUtc();
  final payload = <String, dynamic>{
    'v': 1,
    'jti': issuedAt.microsecondsSinceEpoch.toRadixString(36),
    'terminal': terminal,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': issuedAt.add(Duration(hours: hours)).toIso8601String(),
    if (scopes.isNotEmpty) 'scopes': scopes,
  };

  final payloadBytes = utf8.encode(json.encode(payload));
  final signature = await _algorithm.sign(payloadBytes, keyPair: keyPair);
  final token =
      '${base64Url.encode(payloadBytes)}.${base64Url.encode(signature.bytes)}';

  stdout.writeln('Terminal : $terminal');
  stdout.writeln('Expires  : ${payload['expiresAt']} (UTC, in ${hours}h)');
  stdout.writeln('Scopes   : ${scopes.isEmpty ? 'all' : scopes.join(', ')}');
  stdout.writeln('');
  stdout.writeln(token);
}

// --- one-time codes ---------------------------------------------------

const _otpSeedFile = '$_keyDirectory/developer_otp_seed.json';
const _otpChainLength = 20000;

Future<void> _otpSeed({required bool force}) async {
  final file = File(_otpSeedFile);
  if (file.existsSync() && !force) {
    stderr.writeln(
      'A one-time-code seed already exists at $_otpSeedFile.\n'
      'Replacing it makes every terminal running the current build '
      'unreachable by short code until they take a new build. Pass --force '
      'if you mean it.',
    );
    exit(1);
  }

  final random = Random.secure();
  final seed = List<int>.generate(32, (_) => random.nextInt(256));
  final tip = DeveloperOtpChain.linkAt(seed, _otpChainLength);

  Directory(_keyDirectory).createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'seed': base64Url.encode(seed),
      'chainLength': _otpChainLength,
      'nextIndex': _otpChainLength,
      'createdAt': DateTime.now().toIso8601String(),
    }),
  );
  try {
    Process.runSync('chmod', ['600', file.path]);
  } catch (_) {}

  stdout.writeln('Seed written to $_otpSeedFile — never commit it.');
  stdout.writeln('$_otpChainLength codes available.');
  stdout.writeln('');
  stdout.writeln('Paste into developer_otp.dart:');
  stdout.writeln('');
  stdout.writeln("  const String kDeveloperOtpTip =");
  stdout.writeln("      '${DeveloperOtpChain.encodeTip(tip)}';");
}

Future<void> _otp(Map<String, String> flags) async {
  final file = File(_otpSeedFile);
  if (!file.existsSync()) {
    stderr.writeln('No seed at $_otpSeedFile. Run otp-seed first.');
    exit(1);
  }

  final stored = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  final seed = base64Url.decode(stored['seed'] as String);
  final nextIndex = stored['nextIndex'] as int;

  final count = int.tryParse(flags['count'] ?? '1') ?? 1;
  if (count < 1 || count > 20) {
    stderr.writeln('--count must be between 1 and 20.');
    exit(64);
  }
  if (nextIndex - count < 1) {
    stderr.writeln(
      'The chain is exhausted. Run otp-seed --force and ship a new build.',
    );
    exit(1);
  }

  for (var i = 0; i < count; i++) {
    final index = nextIndex - 1 - i;
    final link = DeveloperOtpChain.linkAt(seed, index);
    stdout.writeln(encodeDeveloperCode(link));
  }

  stored['nextIndex'] = nextIndex - count;
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(stored));

  stdout.writeln('');
  stdout.writeln('${stored['nextIndex']} codes left. Each works once, on the');
  stdout.writeln('first terminal that accepts it.');
}
