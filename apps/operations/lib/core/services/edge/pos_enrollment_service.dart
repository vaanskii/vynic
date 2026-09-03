import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';

/// How far an enrollment attempt got.
enum PosEnrollmentStatus {
  connected,

  /// The address is not a URL this POS can use.
  invalidAddress,

  /// Nothing answered at that address.
  unreachable,

  /// The server refused the code.
  rejected,

  /// The code or this terminal is already spoken for.
  conflict,
  throttled,
  serverError,

  /// The credential was issued but could not be written to disk. Retrying the
  /// same code recovers; nothing has been lost yet.
  notPersisted,
}

class PosEnrollmentResult {
  const PosEnrollmentResult(
    this.status, {
    this.message,
    this.venueName,
    this.backendUrl,
  });

  final PosEnrollmentStatus status;
  final String? message;
  final String? venueName;
  final String? backendUrl;

  bool get isConnected => status == PosEnrollmentStatus.connected;
}

/// Connects this terminal to Vynic from one screen.
///
/// It replaces two manual steps that had to be done in the right order through
/// different surfaces — writing a credential file next to the data directory,
/// and typing a backend address into the connection panel — with a code an
/// operator types once. The address the terminal enrolled through is kept as
/// its backend URL, because it is by definition an address that reached the
/// server; a deployment that wants the fleet somewhere else says so in the
/// response, and even then a loopback answer is ignored rather than used to
/// break the connection that had just worked.
///
/// Nothing here is on the path of taking an order, and nothing it does can stop
/// the POS from starting.
class PosEnrollmentService {
  PosEnrollmentService({EdgeEnrollmentClient? client})
    : _client = client ?? EdgeEnrollmentClient();

  final EdgeEnrollmentClient _client;

  /// True when this terminal has no Cloud identity yet.
  static bool get needsEnrollment => !EdgeDeviceCredentialStore.hasCredential;

  /// What this platform calls itself to the control plane.
  static String get platformName {
    if (kIsWeb) return 'WEB';
    if (Platform.isWindows) return 'WINDOWS';
    if (Platform.isMacOS) return 'MACOS';
    if (Platform.isLinux) return 'LINUX';
    return 'UNKNOWN';
  }

  Future<PosEnrollmentResult> enroll({
    required String serverAddress,
    required String code,
  }) async {
    final baseUrl = ApiConfig.normalizeEditableBackendUrl(serverAddress);
    if (baseUrl == null) {
      return const PosEnrollmentResult(
        PosEnrollmentStatus.invalidAddress,
        message: 'Use an address like 10.10.10.3 or http://10.10.10.3:3000.',
      );
    }

    if (!EdgeDeviceCredentialStore.isLoaded) {
      await EdgeDeviceCredentialStore.load();
    }
    final installationId = EdgeDeviceCredentialStore.installationId;
    if (installationId == null) {
      return const PosEnrollmentResult(
        PosEnrollmentStatus.serverError,
        message:
            'This terminal has no installation id yet. Restart the POS and try again.',
      );
    }

    final result = await _client.enroll(
      baseUrl: baseUrl,
      code: code,
      installationId: installationId,
      platform: platformName,
      displayName: DatabaseService.getVenueName(),
    );

    if (!result.isEnrolled) {
      return PosEnrollmentResult(
        _map(result.outcome),
        message: result.message ?? _fallbackMessage(result.outcome, baseUrl),
      );
    }

    // The credential first: it is issued once, and it is the only part of this
    // that cannot simply be entered again.
    final persisted = await EdgeDeviceCredentialStore.saveEnrollment(
      rawCredential: result.credential!,
      venueId: result.venueId ?? '',
      venueName: result.venueName ?? '',
      enrolledAt: result.enrolledAt,
    );
    if (!persisted) {
      return const PosEnrollmentResult(
        PosEnrollmentStatus.notPersisted,
        message:
            'The credential could not be saved on this machine. Check disk '
            'permissions and enter the same code again — it stays valid for '
            'this terminal until it expires.',
      );
    }

    final effectiveUrl = _resolveBackendUrl(
      enrolledThrough: baseUrl,
      offered: result.apiBaseUrl,
    );
    await DatabaseService.saveBackendUrlOverride(effectiveUrl);
    ApiConfig.resetResolvedUrlLog();

    // Polling is off on an unenrolled terminal, so it has to be told to begin.
    // Not awaited for its result: an unreachable Cloud is not a failed
    // enrollment, and the credential is already safely on disk.
    unawaited(EdgeTransportService.instance().start());

    return PosEnrollmentResult(
      PosEnrollmentStatus.connected,
      venueName: result.venueName,
      backendUrl: effectiveUrl,
    );
  }

  void close() => _client.close();

  /// Prefers what the deployment declares, but never over a working address.
  ///
  /// A server whose declared URL is loopback is describing itself to itself.
  /// Adopting that on a till on another machine would replace an address that
  /// demonstrably reaches the backend with one that cannot.
  @visibleForTesting
  static String resolveBackendUrl({
    required String enrolledThrough,
    String? offered,
  }) => _resolveBackendUrl(enrolledThrough: enrolledThrough, offered: offered);

  static String _resolveBackendUrl({
    required String enrolledThrough,
    String? offered,
  }) {
    if (offered == null || offered.isEmpty) return enrolledThrough;
    final normalized = ApiConfig.normalizeEditableBackendUrl(offered);
    if (normalized == null) return enrolledThrough;
    if (_isLoopback(normalized) && !_isLoopback(enrolledThrough)) {
      return enrolledThrough;
    }
    return normalized;
  }

  static bool _isLoopback(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static PosEnrollmentStatus _map(EdgeEnrollmentOutcome outcome) {
    switch (outcome) {
      case EdgeEnrollmentOutcome.enrolled:
        return PosEnrollmentStatus.connected;
      case EdgeEnrollmentOutcome.unreachable:
        return PosEnrollmentStatus.unreachable;
      case EdgeEnrollmentOutcome.rejected:
        return PosEnrollmentStatus.rejected;
      case EdgeEnrollmentOutcome.conflict:
        return PosEnrollmentStatus.conflict;
      case EdgeEnrollmentOutcome.throttled:
        return PosEnrollmentStatus.throttled;
      case EdgeEnrollmentOutcome.serverError:
        return PosEnrollmentStatus.serverError;
    }
  }

  static String _fallbackMessage(EdgeEnrollmentOutcome outcome, String url) {
    switch (outcome) {
      case EdgeEnrollmentOutcome.unreachable:
        return 'Nothing answered at $url. Check the address and that the '
            'terminal is on the same network as the server.';
      case EdgeEnrollmentOutcome.rejected:
        return 'That enrollment code was not accepted. Check it, or ask for a '
            'new one.';
      case EdgeEnrollmentOutcome.conflict:
        return 'That code has already been used, or this terminal belongs to '
            'another venue.';
      case EdgeEnrollmentOutcome.throttled:
        return 'Too many attempts. Wait a few minutes before trying again.';
      case EdgeEnrollmentOutcome.serverError:
      case EdgeEnrollmentOutcome.enrolled:
        return 'The server could not complete the enrollment.';
    }
  }
}
