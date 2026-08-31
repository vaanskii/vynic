import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';

/// Where this installation's Cloud identity lives on disk.
///
/// The credential is authentication secret material, so it deliberately does
/// **not** live in the Hive settings box: `BackupRepository.createDataBackup`
/// serializes that box wholesale into an exportable JSON file, which would put
/// a device secret into every backup an operator copies off the machine. A
/// dedicated file keeps it out of backups entirely.
///
/// **Boundary, stated plainly.** This is file protection inside a per-user
/// application-data directory, tightened to owner-only where the platform
/// supports it. It is not an OS keychain. Anything running as the same user can
/// read it. Moving to Windows DPAPI / macOS Keychain is recorded as deferred
/// work in docs/CLOUD_EDGE_TRANSPORT.md rather than papered over here.
///
/// The secret is never logged, never rendered, and never committed.
class EdgeDeviceCredentialStore {
  EdgeDeviceCredentialStore._();

  static const String _fileName = 'edge_device.json';

  /// One-shot drop file an operator places next to the data directory.
  ///
  /// This is how a credential reaches a machine without a network endpoint that
  /// mints one and without a UI that displays one. It is read once on startup,
  /// stored, and deleted — see docs/CLOUD_EDGE_TRANSPORT.md.
  static const String _provisionFileName = 'edge_device_provision.txt';
  static const String _credentialPrefix = 'vynic-device-v1';
  static const Uuid _uuid = Uuid();

  /// Test seam: point the store at a temporary directory.
  @visibleForTesting
  static String? directoryOverride;

  static String? _credential;
  static String? _installationId;
  static String? _deviceId;
  static bool _loaded = false;

  /// Reads the stored identity, creating an installation id on first run.
  ///
  /// Never throws: a POS whose credential file is unreadable must still start
  /// and take orders. It simply has no Cloud identity until one is provisioned.
  static Future<void> load() async {
    _loaded = true;
    try {
      final file = _file();
      if (file == null) return;

      if (await file.exists()) {
        final raw = json.decode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          _installationId = _asNonEmptyString(raw['installationId']);
          final stored = _asNonEmptyString(raw['credential']);
          if (stored != null && _isWellFormed(stored)) {
            _credential = stored;
            _deviceId = stored.split('.')[1];
          }
        }
      }

      if (_installationId == null) {
        _installationId = _uuid.v4();
        await _write();
      }

      await _absorbProvisionFile();
    } catch (error) {
      // Deliberately no credential material in the message.
      debugPrint('[Edge] Could not read the device identity file: $error');
    }
  }

  static bool get isLoaded => _loaded;

  /// A stable id for this installation, used when a credential is provisioned.
  static String? get installationId => _installationId;

  /// The Device id half of the credential. Safe to log; the secret half is not.
  static String? get deviceId => _deviceId;

  static bool get hasCredential => _credential != null;

  /// The raw credential, for the `X-POS-Sync-Key` header only.
  static String? get credential => _credential;

  /// Stores a credential issued by the platform for this installation.
  ///
  /// Rejects a malformed value rather than persisting something that would fail
  /// on every request with no way to tell why.
  static Future<bool> save(String rawCredential) async {
    final trimmed = rawCredential.trim();
    if (!_isWellFormed(trimmed)) return false;

    _credential = trimmed;
    _deviceId = trimmed.split('.')[1];
    _installationId ??= _uuid.v4();
    await _write();
    return true;
  }

  /// Forgets this installation's credential, keeping its installation id.
  static Future<void> clear() async {
    _credential = null;
    _deviceId = null;
    await _write();
  }

  @visibleForTesting
  static void resetForTest() {
    _credential = null;
    _installationId = null;
    _deviceId = null;
    _loaded = false;
  }

  /// Takes a credential from the operator drop file, then removes it.
  ///
  /// The drop file is deleted whether or not the value was usable, so a bad
  /// paste is not retried forever and a good one does not sit on disk as a
  /// second copy of the secret.
  static Future<void> _absorbProvisionFile() async {
    final directory = directoryOverride ?? _appDataDirectory();
    if (directory == null) return;
    final dropFile = File('$directory/$_provisionFileName');
    if (!await dropFile.exists()) return;

    String? contents;
    try {
      contents = (await dropFile.readAsString()).trim();
    } catch (error) {
      debugPrint('[Edge] Could not read the provisioning file: $error');
    }

    if (contents != null && _isWellFormed(contents)) {
      _credential = contents;
      _deviceId = contents.split('.')[1];
      await _write();
      debugPrint('[Edge] Device credential provisioned (device $_deviceId).');
    } else if (contents != null) {
      debugPrint('[Edge] Provisioning file ignored — not a device credential.');
    }

    try {
      await dropFile.delete();
    } catch (error) {
      debugPrint('[Edge] Could not remove the provisioning file: $error');
    }
  }

  static Future<void> _write() async {
    final file = _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        json.encode(<String, dynamic>{
          'installationId': _installationId,
          if (_credential != null) 'credential': _credential,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await _restrictPermissions(file);
    } catch (error) {
      debugPrint('[Edge] Could not write the device identity file: $error');
    }
  }

  /// Owner-only where the platform has POSIX permissions. On Windows the
  /// application-data directory is already ACL-scoped to the user account.
  static Future<void> _restrictPermissions(File file) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', <String>['600', file.path]);
    } catch (_) {
      // Best effort; the file is inside a per-user directory either way.
    }
  }

  static File? _file() {
    final directory = directoryOverride ?? _appDataDirectory();
    if (directory == null) return null;
    return File('$directory/$_fileName');
  }

  static String? _appDataDirectory() {
    try {
      return DatabaseCore.dataDirectoryPath;
    } catch (_) {
      // DatabaseService.init() has not run — e.g. the mobile manager client.
      return null;
    }
  }

  static bool _isWellFormed(String value) {
    final parts = value.split('.');
    if (parts.length != 3) return false;
    if (parts[0] != _credentialPrefix) return false;
    if (parts[1].length != 36) return false;
    return parts[2].length >= 32;
  }

  static String? _asNonEmptyString(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
