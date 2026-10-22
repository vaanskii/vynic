import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/security/developer_access.dart';

import 'print_identity_admission.dart';
import 'printer_agent_client.dart';
import 'printer_agent_profile.dart';

const printerAgentProfilePath = String.fromEnvironment(
  'VYNIC_PRINTER_AGENT_PROFILE',
);

enum PrinterAgentRuntimeFailure {
  notConfigured,
  invalidProfile,
  profileUnavailable,
  missingDevice,
  missingVenue,
  missingInstallation,
  identityChanging,
  restorationHeld,
  bindingMismatch,
  profileChanged,
  scopeDenied,
}

class PrinterAgentRuntimeException implements Exception {
  const PrinterAgentRuntimeException(this.reason);
  final PrinterAgentRuntimeFailure reason;
  @override
  String toString() => 'PrinterAgentRuntimeException(${reason.name})';
}

/// Current local enrollment is an inspection guard, not Cloud tenancy or
/// admission authority. No getter loads, creates or persists an identity.
class PrinterAgentRuntimeBinding {
  const PrinterAgentRuntimeBinding({
    required this.deviceId,
    required this.venueId,
    required this.deviceInstallationId,
    required this.loaded,
    required this.enrolled,
    this.changing = false,
    this.restorationHeld = false,
  });
  final String? deviceId, venueId, deviceInstallationId;
  final bool loaded, enrolled, changing, restorationHeld;

  void requireUsable() {
    if (changing) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.identityChanging,
      );
    }
    if (restorationHeld) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.restorationHeld,
      );
    }
    if (!loaded || !enrolled || !printerAgentUuid(deviceId ?? '')) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.missingDevice,
      );
    }
    if (!printerAgentUuid(venueId ?? '')) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.missingVenue,
      );
    }
    if (!printerAgentUuid(deviceInstallationId ?? '')) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.missingInstallation,
      );
    }
  }

  bool sameEnrollment(PrinterAgentRuntimeBinding other) =>
      deviceId == other.deviceId &&
      venueId == other.venueId &&
      deviceInstallationId == other.deviceInstallationId &&
      loaded == other.loaded &&
      enrolled == other.enrolled;

  void requirePins(PrinterAgentPins pins) {
    requireUsable();
    // The Go store installation is distinct from this POS enrollment's
    // installation. Its identity is pinned by the profile/TLS health codec.
    if (pins.deviceId != deviceId || pins.venueId != venueId) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.bindingMismatch,
      );
    }
  }

  void requireDeviceInstallation(String expected) {
    requireUsable();
    if (!printerAgentUuid(expected) || expected != deviceInstallationId) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.bindingMismatch,
      );
    }
  }
}

PrinterAgentRuntimeBinding currentPrinterAgentBinding() {
  final settings = DatabaseCore.settingsBox;
  final venue = EdgeDeviceCredentialStore.venueId;
  final restorationHeld =
      settings != null &&
      settings.isOpen &&
      (settings.get('restoreLegacyIncomplete') == true ||
          (settings.get('restoreVenueBinding') != null &&
              settings.get('restoreVenueBinding') != venue));
  return PrinterAgentRuntimeBinding(
    deviceId: EdgeDeviceCredentialStore.deviceId,
    venueId: venue,
    deviceInstallationId: EdgeDeviceCredentialStore.installationId,
    loaded: EdgeDeviceCredentialStore.isLoaded,
    enrolled: EdgeDeviceCredentialStore.hasCredential,
    changing: PrintIdentityAdmission.identityTransitionActive,
    restorationHeld: restorationHeld,
  );
}

abstract interface class PrinterAgentRuntimeHealthSource
    implements PrinterAgentHealthReader {
  bool get isConfigured;
  PrinterAgentRuntimeBinding get currentBinding;
}

abstract interface class PrinterAgentRuntimeConnection
    implements PrinterAgentHealthReader {
  Future<void> close();
}

typedef PrinterAgentRuntimeConnector =
    PrinterAgentRuntimeConnection Function(
      PrinterAgentProfile profile,
      List<int> clientCertificate,
      List<int> clientKey,
    );

class _AgentConnection implements PrinterAgentRuntimeConnection {
  _AgentConnection(this.client);
  final PrinterAgentClient client;
  @override
  Future<PrinterAgentHealth> health() => client.health();
  @override
  Future<void> close() => client.close();
}

PrinterAgentRuntimeConnection _connectAgent(
  PrinterAgentProfile profile,
  List<int> certificate,
  List<int> key,
) => _AgentConnection(
  PrinterAgentClient.connect(
    profile: profile,
    clientCertificate: certificate,
    clientKey: key,
  ),
);

/// Explicit opt-in, read-only health factory. It never loads at startup,
/// discovers a host, installs trust/service files, writes credentials or sends
/// a job. An empty build flag leaves existing printing entirely unchanged.
class PrinterAgentRuntimeProfile implements PrinterAgentRuntimeHealthSource {
  const PrinterAgentRuntimeProfile({
    this.profilePath = printerAgentProfilePath,
    this.bindingReader = currentPrinterAgentBinding,
    this.connector = _connectAgent,
  });

  final String profilePath;
  final PrinterAgentRuntimeBinding Function() bindingReader;
  final PrinterAgentRuntimeConnector connector;
  static const _maxProfileBytes = 64 * 1024;
  static const _maxPemBytes = 16 * 1024;
  static const _keys = {
    'version',
    'provisionStatus',
    'listenAddress',
    'clientId',
    'currentDeviceInstallationId',
    'pins',
    'serverCertificatePath',
    'serverCertificateSha256',
    'clientCertificatePath',
    'clientPrivateKeyPath',
    'clientCertificateSha256',
  };

  @override
  bool get isConfigured => profilePath.isNotEmpty;
  @override
  PrinterAgentRuntimeBinding get currentBinding => bindingReader();

  void _requireScope() {
    if (!DeveloperAccess.can(DeveloperScope.printers)) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.scopeDenied,
      );
    }
  }

  void _requireCurrent(PrinterAgentRuntimeBinding captured) {
    _requireScope();
    final current = currentBinding;
    current.requireUsable();
    if (!captured.sameEnrollment(current)) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.bindingMismatch,
      );
    }
  }

  @override
  Future<PrinterAgentHealth> health() async {
    _requireScope();
    if (!isConfigured) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.notConfigured,
      );
    }
    final captured = currentBinding;
    captured.requireUsable();
    try {
      _requireAbsolute(profilePath);
      final root = await File(profilePath).parent.resolveSymbolicLinks();
      final raw = await _readRegular(profilePath, root, _maxProfileBytes);
      final json = _ProfileJson(utf8.decode(raw)).decode();
      if (json.length != _keys.length ||
          !json.keys.toSet().containsAll(_keys) ||
          json['version'] is! int ||
          json['version'] != 1 ||
          json['provisionStatus'] != 'HELD_PROVISIONING' ||
          json['pins'] is! Map<String, dynamic>) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.invalidProfile,
        );
      }
      final pins = PrinterAgentPins.fromJson(
        json['pins'] as Map<String, dynamic>,
      );
      // Refuse another Device/Venue/installation before reading a private key.
      captured.requirePins(pins);
      final deviceInstallation = _string(json, 'currentDeviceInstallationId');
      if (!printerAgentUuid(deviceInstallation)) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.invalidProfile,
        );
      }
      captured.requireDeviceInstallation(deviceInstallation);
      _requireCurrent(captured);
      final address = _string(json, 'listenAddress');
      final match = RegExp(
        r'^127\.0\.0\.1:([1-9][0-9]{0,4})$',
      ).firstMatch(address);
      final port = match == null ? 0 : int.parse(match.group(1)!);
      if (port < 1 || port > 65535) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.invalidProfile,
        );
      }
      final serverPath = _string(json, 'serverCertificatePath');
      final clientPath = _string(json, 'clientCertificatePath');
      final keyPath = _string(json, 'clientPrivateKeyPath');
      final server = await _readRegular(serverPath, root, _maxPemBytes);
      final certificate = await _readRegular(clientPath, root, _maxPemBytes);
      final key = await _readRegular(keyPath, root, _maxPemBytes);
      _requireCertificateDigest(
        server,
        _string(json, 'serverCertificateSha256'),
      );
      _requireCertificateDigest(
        certificate,
        _string(json, 'clientCertificateSha256'),
      );
      final profile = PrinterAgentProfile(
        pins: pins,
        clientId: _string(json, 'clientId'),
        currentDeviceInstallationId: deviceInstallation,
        port: port,
        pinnedServerCertificate: server,
      );
      _requireCurrent(captured);
      final connection = connector(profile, certificate, key);
      late PrinterAgentHealth result;
      try {
        result = await connection.health();
      } finally {
        await connection.close();
      }
      _requireCurrent(captured);
      captured.requirePins(result.pins);
      if (!profile.pins.matches(result.pins) ||
          profile.clientId != result.clientId ||
          !result.physicalHeld ||
          !result.admissionHeld) {
        throw const PrinterAgentException(PrinterAgentFailure.profileMismatch);
      }
      // A response from the old configuration must not look current after an
      // operator replaces the explicit profile or credential files mid-call.
      final unchanged = await _readRegular(profilePath, root, _maxProfileBytes);
      if (_digest(raw) != _digest(unchanged)) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.profileChanged,
        );
      }
      for (final asset in [
        (serverPath, server),
        (clientPath, certificate),
        (keyPath, key),
      ]) {
        if (_digest(await _readRegular(asset.$1, root, _maxPemBytes)) !=
            _digest(asset.$2)) {
          throw const PrinterAgentRuntimeException(
            PrinterAgentRuntimeFailure.profileChanged,
          );
        }
      }
      _requireCurrent(captured);
      return result;
    } on PrinterAgentRuntimeException {
      rethrow;
    } on PrinterAgentException {
      rethrow;
    } on FileSystemException {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.profileUnavailable,
      );
    } on FormatException {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    } catch (_) {
      // Never render a filesystem/TLS exception containing credential paths
      // or secret material. The failure remains explicit and typed.
      throw const PrinterAgentException(PrinterAgentFailure.unavailable);
    }
  }

  static String _string(Map<String, dynamic> json, String name) {
    final value = json[name];
    if (value is! String || value.isEmpty || value.length > 2048) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    }
    return value;
  }

  static void _requireAbsolute(String value) {
    if (value.length > 2048 ||
        !File(value).isAbsolute ||
        value != value.trim() ||
        Uri.file(
              value,
              windows: Platform.isWindows,
            ).normalizePath().toFilePath(windows: Platform.isWindows) !=
            value ||
        value.startsWith('\\\\') ||
        value.startsWith('//') ||
        value.contains('://') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    }
  }

  static Future<Uint8List> _readRegular(
    String name,
    String root,
    int limit,
  ) async {
    _requireAbsolute(name);
    if (await FileSystemEntity.type(name, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.profileUnavailable,
      );
    }
    final file = File(name);
    final resolved = await file.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    final prefix = root.endsWith(separator) ? root : '$root$separator';
    final inside = Platform.isWindows
        ? resolved.toLowerCase().startsWith(prefix.toLowerCase())
        : resolved.startsWith(prefix);
    if (!inside) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    }
    final handle = await file.open(mode: FileMode.read);
    try {
      final builder = BytesBuilder(copy: false);
      while (builder.length <= limit) {
        final chunk = await handle.read(limit + 1 - builder.length);
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty || bytes.length > limit) {
        throw const PrinterAgentRuntimeException(
          PrinterAgentRuntimeFailure.invalidProfile,
        );
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  static String _digest(List<int> value) => sha256.convert(value).toString();

  static void _requireCertificateDigest(List<int> pem, String expected) {
    if (!printerAgentDigest(expected)) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    }
    final text = utf8.decode(pem);
    final match = RegExp(
      r'^\s*-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\r\n]+)\s*-----END CERTIFICATE-----\s*$',
    ).firstMatch(text);
    if (match == null ||
        _digest(base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''))) !=
            expected) {
      throw const PrinterAgentRuntimeException(
        PrinterAgentRuntimeFailure.invalidProfile,
      );
    }
  }
}

/// Bounded duplicate-aware parsing of the profile's two object levels. Arrays
/// are not part of this contract. ASN.1/X509 validation stays in the TLS layer.
class _ProfileJson {
  _ProfileJson(this.text);
  final String text;
  int offset = 0;

  Map<String, dynamic> decode() {
    final value = _value(0);
    _space();
    if (offset != text.length || value is! Map<String, dynamic>) {
      throw const FormatException('Invalid agent profile');
    }
    return value;
  }

  void _space() {
    while (offset < text.length && ' \n\r\t'.contains(text[offset])) {
      offset++;
    }
  }

  dynamic _value(int depth) {
    _space();
    if (depth > 4 || offset >= text.length) {
      throw const FormatException('Invalid agent profile');
    }
    if (text[offset] == '{') {
      offset++;
      final values = <String, dynamic>{};
      _space();
      if (offset < text.length && text[offset] == '}') {
        offset++;
        return values;
      }
      while (true) {
        _space();
        final key = _string();
        _space();
        if (values.containsKey(key) ||
            values.length >= 64 ||
            offset >= text.length ||
            text[offset++] != ':') {
          throw const FormatException('Invalid agent profile');
        }
        values[key] = _value(depth + 1);
        _space();
        if (offset >= text.length) {
          throw const FormatException('Invalid agent profile');
        }
        final end = text[offset++];
        if (end == '}') return values;
        if (end != ',') {
          throw const FormatException('Invalid agent profile');
        }
      }
    }
    if (text[offset] == '"') return _string();
    final start = offset;
    while (offset < text.length && !',} \n\r\t'.contains(text[offset])) {
      if ('[]{}"'.contains(text[offset])) {
        throw const FormatException('Invalid agent profile');
      }
      offset++;
    }
    if (start == offset) {
      throw const FormatException('Invalid agent profile');
    }
    return jsonDecode(text.substring(start, offset));
  }

  String _string() {
    if (offset >= text.length || text[offset] != '"') {
      throw const FormatException('Invalid agent profile');
    }
    final start = offset++;
    while (offset < text.length) {
      final next = text[offset++];
      if (next == '"') {
        return jsonDecode(text.substring(start, offset)) as String;
      }
      if (next == '\\') offset++;
    }
    throw const FormatException('Invalid agent profile');
  }
}
