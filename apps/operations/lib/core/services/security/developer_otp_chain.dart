import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The hash chain behind the one-time unlock codes.
///
/// Codes are read from the end of a chain backwards. The terminal stores only
/// the last link it has seen; a code is valid if hashing it forward a few times
/// arrives at that link, and using it moves the stored link one step back.
///
/// That is what makes a sixteen-character code safe. It is not a signature —
/// eighty bits could never hold one — but forging the *next* code means
/// inverting SHA-256, which is not something a restaurant owner is going to do
/// with the codes they have already seen. Meanwhile each code dies the moment
/// it is used, because the terminal has moved past it.
abstract final class DeveloperOtpChain {
  /// Bytes per link. Eighty bits: sixteen Crockford base32 characters, and
  /// 2^80 work to find a preimage.
  static const linkBytes = 10;

  /// How far ahead of a terminal a code may be and still be accepted.
  ///
  /// Terminals drift behind the issuing tool — one venue is serviced twice in a
  /// month, another not for a year — and every code the tool skips has to
  /// remain usable, or a rarely-visited terminal becomes unreachable. Being
  /// *behind* is never accepted, which is what keeps used codes dead.
  static const defaultWindow = 500;

  /// One step along the chain.
  static List<int> step(List<int> link) =>
      sha256.convert(link).bytes.sublist(0, linkBytes);

  /// The first link, derived from the master seed.
  static List<int> rootFromSeed(List<int> seed) =>
      sha256.convert(seed).bytes.sublist(0, linkBytes);

  /// Walks [count] steps from [link].
  static List<int> advance(List<int> link, int count) {
    var current = link;
    for (var i = 0; i < count; i++) {
      current = step(current);
    }
    return current;
  }

  /// The link at [index], counting from the root.
  static List<int> linkAt(List<int> seed, int index) =>
      advance(rootFromSeed(seed), index);

  /// How many steps it takes to get from [candidate] to [tip], or null if it
  /// never arrives within [window].
  ///
  /// Zero is deliberately not a match: a candidate equal to the tip is a code
  /// that has already been spent.
  static int? distanceToTip(
    List<int> candidate,
    List<int> tip, {
    int window = defaultWindow,
  }) {
    var current = candidate;
    for (var steps = 1; steps <= window; steps++) {
      current = step(current);
      if (_equals(current, tip)) return steps;
    }
    return null;
  }

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String encodeTip(List<int> link) => base64Url.encode(link);

  static List<int> decodeTip(String value) => base64Url.decode(value);
}
