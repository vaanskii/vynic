import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The public key compiled into the POS builds you ship.
///
/// Kept here so the tool can tell you, before you send anything, whether the
/// key you have loaded is the one your customers' terminals will accept. That
/// check is the whole reason this constant is duplicated out of the POS
/// package rather than imported: the tool is standalone by design, and a build
/// of it should not drag the POS in.
const String kShippedPublicKeyBase64 =
    'bGacZBHy8joBMO8PoKbujLARv-oPIifHmRh4w1zuQlY=';

/// A loaded Ed25519 signing key, plus where it came from.
///
/// The private key is **not** compiled into this app. It is read from a file
/// you point at, and only the path is remembered between runs. A copy of this
/// binary that someone else gets hold of is inert — it can sign nothing.
class SigningKey {
  SigningKey({
    required this.keyPair,
    required this.publicKeyBase64,
    required this.sourcePath,
  });

  final SimpleKeyPair keyPair;
  final String publicKeyBase64;
  final String sourcePath;

  /// Whether tokens signed with this key will be accepted by the POS builds
  /// carrying [kShippedPublicKeyBase64].
  bool get matchesShippedBuild => publicKeyBase64 == kShippedPublicKeyBase64;
}

class SigningKeyStore {
  static const _rememberedPathFile = 'vynic_devtool_key_path.txt';

  static final _algorithm = Ed25519();

  /// Where the POS repository keeps its key, relative to the checkout root.
  static const _repositoryKeyPath = 'secrets/developer_signing_key.json';

  /// How far up to walk looking for the checkout.
  ///
  /// Deep enough to cover a release build launched from its own bundle, which
  /// sits eight directories below the repository root — double-clicking the app
  /// gives it a working directory of `/`, so walking up from the executable is
  /// the only way the first run finds anything.
  static const _maxAncestorDepth = 12;

  /// Loads the key from the remembered path, or from the repository if this is
  /// running inside a checkout. Returns null when neither turns up anything.
  static Future<SigningKey?> loadRemembered() async {
    final remembered = await _readRememberedPath();
    if (remembered != null && File(remembered).existsSync()) {
      try {
        return await loadFrom(remembered);
      } catch (_) {
        // A remembered path that no longer parses is not worth an error on
        // startup — fall through and let the conventional paths try.
      }
    }

    for (final candidate in _repositoryKeyCandidates()) {
      try {
        return await loadFrom(candidate);
      } catch (_) {
        continue;
      }
    }
    debugPrint(
      '[SigningKey] No key found. Searched upward from '
      '${Directory.current.absolute.path} and '
      '${File(Platform.resolvedExecutable).parent.absolute.path}.',
    );
    return null;
  }

  /// Every `secrets/developer_signing_key.json` above the working directory or
  /// above this executable, nearest first.
  static Iterable<String> _repositoryKeyCandidates() sync* {
    final seen = <String>{};
    for (final start in [
      Directory.current.absolute.path,
      File(Platform.resolvedExecutable).parent.absolute.path,
    ]) {
      var directory = Directory(start);
      for (var depth = 0; depth < _maxAncestorDepth; depth++) {
        final candidate = File('${directory.path}/$_repositoryKeyPath');
        if (candidate.existsSync() && seen.add(candidate.path)) {
          yield candidate.path;
        }
        final parent = directory.parent;
        if (parent.path == directory.path) break;
        directory = parent;
      }
    }
  }

  /// Reads and validates a `developer_signing_key.json` written by
  /// `tool/dev_key.dart keygen`, and remembers the path for next time.
  static Future<SigningKey> loadFrom(String path) async {
    debugPrint('[SigningKey] Loading $path');
    final raw = File(path).readAsStringSync();
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Key file is not a JSON object.');
    }
    final privateKey = decoded['privateKey'];
    if (privateKey is! String || privateKey.isEmpty) {
      throw const FormatException('Key file has no privateKey.');
    }

    final keyPair = await _algorithm.newKeyPairFromSeed(
      base64Url.decode(privateKey),
    );
    final publicKey = await keyPair.extractPublicKey();

    await _writeRememberedPath(path);

    return SigningKey(
      keyPair: keyPair,
      publicKeyBase64: base64Url.encode(publicKey.bytes),
      sourcePath: path,
    );
  }

  static Future<String?> _readRememberedPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_rememberedPathFile');
      if (!file.existsSync()) return null;
      final path = file.readAsStringSync().trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeRememberedPath(String path) async {
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$_rememberedPathFile').writeAsString(path);
    } catch (_) {
      // Remembering is a convenience. Failing to do it is not worth surfacing.
    }
  }
}
