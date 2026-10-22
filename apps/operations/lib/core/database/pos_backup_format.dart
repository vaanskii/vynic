import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Portable format; checksums detect damage, AES-GCM authenticates encryption.
abstract final class PosBackupFormat {
  static const version = 2;
  static const product = 'vynic-pos';
  static const stores = <String>[
    'meta',
    'users',
    'tables',
    'orders',
    'packages',
    'menu',
    'settings',
    'sales',
    'expenses',
    'auditLog',
    'reservations',
    'quickOrders',
    'closureJournal',
    'inventoryCatalog',
    'menuCanonical',
    'menuMutationJournal',
    'edge_command_journal',
  ];
  static const deviceSettings = <String>{
    'posIngestConnectionKey',
    'developerTerminalId',
    'developerClockHighWater',
    'developerOtpTip',
    'enrolledDeviceName',
    'deviceRuntimeConfig',
    'restoreVenueBinding',
    'restoreSourceDeviceId',
    'restoreLegacyIncomplete',
  };

  static String canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${canonical(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    return jsonEncode(value);
  }

  static String digest(Object? value) =>
      hash.sha256.convert(utf8.encode(canonical(value))).toString();

  /// Tagged primitives preserve nested map keys, dates and binary logo data.
  /// Unsupported values fail instead of being stringified or dropped.
  static Object? encodeValue(dynamic value) {
    if (value == null || value is String || value is bool || value is int)
      return value;
    if (value is double && value.isFinite) return value;
    if (value is DateTime) return {'t': 'date', 'v': value.toIso8601String()};
    if (value is Uint8List) return {'t': 'bytes', 'v': base64Encode(value)};
    if (value is List)
      return {'t': 'list', 'v': value.map(encodeValue).toList()};
    if (value is Map)
      return {
        't': 'map',
        'v': value.entries
            .map((e) => [encodeValue(e.key), encodeValue(e.value)])
            .toList(),
      };
    throw FormatException(
      'Unsupported durable value type ${value.runtimeType}',
    );
  }

  static dynamic decodeValue(dynamic value) {
    if (value == null || value is String || value is bool || value is int)
      return value;
    if (value is double && value.isFinite) return value;
    if (value is! Map || value.length != 2 || !value.containsKey('v'))
      throw const FormatException('Invalid durable value');
    switch (value['t']) {
      case 'date':
        return DateTime.parse(value['v'] as String);
      case 'bytes':
        return base64Decode(value['v'] as String);
      case 'list':
        return (value['v'] as List).map(decodeValue).toList();
      case 'map':
        final out = <dynamic, dynamic>{};
        for (final row in value['v'] as List) {
          if (row is! List || row.length != 2)
            throw const FormatException('Invalid map entry');
          final key = decodeValue(row[0]);
          if (out.containsKey(key))
            throw const FormatException('Duplicate map key');
          out[key] = decodeValue(row[1]);
        }
        return out;
      default:
        throw const FormatException('Unknown durable value encoding');
    }
  }

  static void seal(Map<String, dynamic> payload) {
    payload['manifest'] = [
      for (final name in stores)
        {
          'store': name,
          'rows': (payload['stores'][name] as List).length,
          'sha256': digest(payload['stores'][name]),
        },
    ];
    payload['integrity'] = {'algorithm': 'SHA-256', 'sha256': digest(payload)};
  }

  static void validate(Map<String, dynamic> payload) {
    if (payload['formatVersion'] != version || payload['product'] != product)
      throw const FormatException('Unsupported POS backup format');
    if (payload['hiveSchemaVersion'] != 9 ||
        payload['menuLocalProtocolVersion'] != 1)
      throw const FormatException('Unsupported data/Menu protocol version');
    if (payload['compatibility'] is! Map ||
        payload['compatibility']['minimumReaderFormat'] != version)
      throw const FormatException('Invalid compatibility requirements');
    DateTime.parse(payload['createdAt'] as String);
    if (payload['appVersion'] is! String)
      throw const FormatException('Missing app version');
    if (![
      'complete-current-state',
      'legacy-history-incomplete',
    ].contains(payload['recoveryCompleteness']))
      throw const FormatException('Invalid recovery completeness');
    if (payload['venue'] is! Map)
      throw const FormatException('Missing Venue metadata');
    final integrity = payload['integrity'];
    final unsigned = Map<String, dynamic>.of(payload)..remove('integrity');
    if (integrity is! Map ||
        integrity['algorithm'] != 'SHA-256' ||
        integrity['sha256'] != digest(unsigned))
      throw const FormatException('Backup checksum mismatch');
    final data = payload['stores'];
    final manifest = payload['manifest'];
    if (data is! Map ||
        manifest is! List ||
        data.length != stores.length ||
        manifest.length != stores.length)
      throw const FormatException('Incomplete store manifest');
    final seen = <String>{};
    for (final entry in manifest) {
      if (entry is! Map ||
          entry['store'] is! String ||
          !stores.contains(entry['store']) ||
          !seen.add(entry['store']))
        throw const FormatException('Invalid store manifest');
      final rows = data[entry['store']];
      if (rows is! List ||
          rows.length != entry['rows'] ||
          digest(rows) != entry['sha256'])
        throw const FormatException('Invalid store checksum/count');
      final keys = <Object>{};
      for (final row in rows) {
        if (row is! Map ||
            row.length != 2 ||
            !row.containsKey('key') ||
            !row.containsKey('value'))
          throw const FormatException('Invalid store row');
        final key = row['key'];
        if ((key is! int && key is! String) || !keys.add(key as Object))
          throw const FormatException('Invalid/duplicate Hive key');
        decodeValue(row['value']);
      }
    }
  }

  static Future<String> encode(
    Map<String, dynamic> payload, {
    String? password,
  }) async {
    final plain = jsonEncode(payload);
    if (password == null) return plain;
    if (password.length < 12)
      throw const FormatException(
        'Backup password must contain at least 12 characters',
      );
    final aes = AesGcm.with256bits();
    final salt = aes.newNonce();
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final header = {
      'product': product,
      'formatVersion': version,
      'encryption': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 210000,
      'salt': base64Encode(salt),
    };
    final box = await aes.encrypt(
      utf8.encode(plain),
      secretKey: key,
      aad: utf8.encode(canonical(header)),
    );
    return jsonEncode({
      ...header,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
  }

  static Future<Map<String, dynamic>> decode(
    String text, {
    String? password,
  }) async {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>)
      throw const FormatException('Backup must be a JSON object');
    if (!raw.containsKey('encryption')) return raw;
    if (raw['product'] != product ||
        raw['formatVersion'] != version ||
        raw['encryption'] != 'AES-256-GCM' ||
        raw['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        raw['iterations'] != 210000)
      throw const FormatException('Unsupported encrypted backup');
    if (password == null)
      throw const FormatException('Backup password is required');
    final header = {
      for (final key in [
        'product',
        'formatVersion',
        'encryption',
        'kdf',
        'iterations',
        'salt',
      ])
        key: raw[key],
    };
    final salt = base64Decode(raw['salt'] as String);
    final nonce = base64Decode(raw['nonce'] as String);
    final tag = base64Decode(raw['tag'] as String);
    if (salt.length != 12 || nonce.length != 12 || tag.length != 16)
      throw const FormatException('Invalid encryption metadata');
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    try {
      final bytes = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(raw['ciphertext'] as String),
          nonce: nonce,
          mac: Mac(tag),
        ),
        secretKey: key,
        aad: utf8.encode(canonical(header)),
      );
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Wrong backup password or damaged encrypted backup',
      );
    }
  }
}
