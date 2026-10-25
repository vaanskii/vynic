import 'package:flutter/services.dart';

/// A boot identity must come from the OS, never wall-clock-derived boot time.
class LicenseClockSample {
  const LicenseClockSample(this.elapsed, this.boot);
  final int elapsed;
  final String boot;
  static Future<LicenseClockSample> read() async {
    final result = await const MethodChannel(
      'ge.vynic/license',
    ).invokeMapMethod<String, dynamic>('continuity');
    if (result == null ||
        result['elapsedMs'] is! int ||
        result['elapsedMs'] < 0 ||
        result['bootId'] is! String ||
        (result['bootId'] as String).isEmpty) {
      throw StateError('Trusted clock continuity unavailable');
    }
    return LicenseClockSample(result['elapsedMs'], result['bootId']);
  }
}

/// The vault contains the current record itself, not a key for a replayable file.
/// Missing/locked/unavailable storage never permits restoration from Hive.
class LicenseVault {
  const LicenseVault();
  static const _channel = MethodChannel('ge.vynic/license');
  Future<String?> read(String account) =>
      _channel.invokeMethod<String>('readAnchor', {'account': account});
  Future<void> write(String account, String value) => _channel
      .invokeMethod<void>('writeAnchor', {'account': account, 'value': value});
}
