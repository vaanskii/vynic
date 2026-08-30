import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The one-time-code seed, and this tool's place in the chain.
///
/// Codes are handed out from the end backwards. The tool only ever moves
/// downwards, which is what keeps it ahead of every terminal: a terminal can
/// lag as far behind as the acceptance window allows and still take the next
/// code, but the tool must never re-issue one it has already given out.
class OtpSeed {
  OtpSeed({
    required this.seed,
    required this.nextIndex,
    required this.chainLength,
    required this.sourcePath,
  });

  final List<int> seed;
  final int nextIndex;
  final int chainLength;
  final String sourcePath;

  int get remaining => nextIndex;
}

class OtpStore {
  /// Bytes per link — eighty bits, the same figure the POS verifies against.
  static const linkBytes = 10;

  static const _repositorySeedPath = 'secrets/developer_otp_seed.json';
  static const _maxAncestorDepth = 12;

  static List<int> _step(List<int> link) =>
      sha256.convert(link).bytes.sublist(0, linkBytes);

  /// The link at [index], counting from the root.
  static List<int> linkAt(List<int> seed, int index) {
    var current = sha256.convert(seed).bytes.sublist(0, linkBytes);
    for (var i = 0; i < index; i++) {
      current = _step(current);
    }
    return current;
  }

  /// Finds the seed beside the signing key, or anywhere above this executable.
  static OtpSeed? load({String? nearKeyPath}) {
    for (final path in _candidates(nearKeyPath)) {
      try {
        final decoded = json.decode(File(path).readAsStringSync());
        if (decoded is! Map<String, dynamic>) continue;
        debugPrint('[OtpStore] Loading $path');
        return OtpSeed(
          seed: base64Url.decode(decoded['seed'] as String),
          nextIndex: decoded['nextIndex'] as int,
          chainLength: decoded['chainLength'] as int,
          sourcePath: path,
        );
      } catch (_) {
        continue;
      }
    }
    debugPrint('[OtpStore] No seed found.');
    return null;
  }

  /// Takes the next code and writes the advanced counter back.
  ///
  /// The write happens before the code is shown, not after: a code that was
  /// displayed but not recorded would be re-issued later, and the second
  /// terminal to receive it would reject it as spent.
  static ({List<int> link, int index})? take(OtpSeed current) {
    if (current.nextIndex < 1) return null;

    final index = current.nextIndex - 1;
    final file = File(current.sourcePath);
    final decoded =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    decoded['nextIndex'] = index;
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(decoded));

    return (link: linkAt(current.seed, index), index: index);
  }

  static Iterable<String> _candidates(String? nearKeyPath) sync* {
    final seen = <String>{};

    // The seed lives beside the signing key, so if one has been found the
    // other is a directory listing away.
    if (nearKeyPath != null) {
      final beside = File(
        '${File(nearKeyPath).parent.path}/developer_otp_seed.json',
      );
      if (beside.existsSync() && seen.add(beside.path)) yield beside.path;
    }

    for (final start in [
      Directory.current.absolute.path,
      File(Platform.resolvedExecutable).parent.absolute.path,
    ]) {
      var directory = Directory(start);
      for (var depth = 0; depth < _maxAncestorDepth; depth++) {
        final candidate = File('${directory.path}/$_repositorySeedPath');
        if (candidate.existsSync() && seen.add(candidate.path)) {
          yield candidate.path;
        }
        final parent = directory.parent;
        if (parent.path == directory.path) break;
        directory = parent;
      }
    }
  }
}
