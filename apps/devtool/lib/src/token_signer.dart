import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'signing_key.dart';

/// Everything a token can grant. Mirrors `DeveloperScope` in the POS.
abstract final class TokenScope {
  static const diagnostics = 'diagnostics';
  static const connection = 'connection';
  static const printers = 'printers';
  static const errors = 'errors';
  static const backup = 'backup';
  static const restore = 'restore';
  static const wipe = 'wipe';
  static const recovery = 'recovery';

  static const all = <String>[
    diagnostics,
    connection,
    printers,
    errors,
    backup,
    restore,
    wipe,
    recovery,
  ];

  /// The tools that destroy data or hand over an account.
  static const destructive = <String>[restore, wipe, recovery];
}

/// The wildcard terminal: a token that opens any machine.
const String kAnyTerminal = '*';

class SignedToken {
  const SignedToken({
    required this.value,
    required this.terminal,
    required this.expiresAt,
    required this.scopes,
  });

  final String value;
  final String terminal;
  final DateTime expiresAt;
  final List<String> scopes;

  bool get isMasterKey => terminal == kAnyTerminal;

  /// A filename that says what the token is without opening it.
  String get suggestedFileName {
    final stamp = expiresAt.toIso8601String().split('T').first;
    final who = isMasterKey
        ? 'master'
        : terminal.replaceAll('-', '').substring(0, 8);
    return 'vynic-dev-$who-$stamp.token';
  }
}

class TokenSigner {
  static final _algorithm = Ed25519();

  /// Signs an unlock token.
  ///
  /// [terminal] is the ID read off the POS unlock dialog, or [kAnyTerminal] for
  /// a token that opens any machine. Passing every scope is the default because
  /// a token you signed deliberately, for a window you chose, is not made safer
  /// by also being fiddly.
  static Future<SignedToken> sign({
    required SigningKey key,
    required String terminal,
    required Duration validFor,
    List<String> scopes = TokenScope.all,
    DateTime? issuedAt,
  }) async {
    final issued = (issuedAt ?? DateTime.now()).toUtc();
    final expires = issued.add(validFor);

    final payload = <String, dynamic>{
      'v': 1,
      'jti': issued.microsecondsSinceEpoch.toRadixString(36),
      'terminal': terminal,
      'issuedAt': issued.toIso8601String(),
      'expiresAt': expires.toIso8601String(),
      // Omitted entirely when everything is granted: the POS reads a missing
      // `scopes` as "all", and writing them out would only invite someone to
      // try editing the list.
      if (scopes.length != TokenScope.all.length) 'scopes': scopes,
    };

    final payloadBytes = utf8.encode(json.encode(payload));
    final signature = await _algorithm.sign(payloadBytes, keyPair: key.keyPair);

    return SignedToken(
      value:
          '${base64Url.encode(payloadBytes)}.${base64Url.encode(signature.bytes)}',
      terminal: terminal,
      expiresAt: expires,
      scopes: scopes,
    );
  }
}
