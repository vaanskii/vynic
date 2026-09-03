import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why an enrollment attempt did not produce a credential.
enum EdgeEnrollmentOutcome {
  enrolled,

  /// The server could not be reached at all — wrong address, or nothing there.
  unreachable,

  /// The code was rejected: unknown, wrong, spent, expired or cancelled.
  rejected,

  /// This terminal already belongs somewhere else, or the code already does.
  conflict,

  /// Too many attempts. The server is asking us to stop for a while.
  throttled,

  /// The request itself was malformed, or the server answered with something
  /// this build cannot read.
  serverError,
}

/// What the backend returned for a redeemed enrollment code.
class EdgeEnrollmentResult {
  const EdgeEnrollmentResult({
    required this.outcome,
    this.message,
    this.credential,
    this.deviceId,
    this.deviceName,
    this.venueId,
    this.venueName,
    this.apiBaseUrl,
    this.enrolledAt,
  });

  const EdgeEnrollmentResult.failed(this.outcome, {this.message})
    : credential = null,
      deviceId = null,
      deviceName = null,
      venueId = null,
      venueName = null,
      apiBaseUrl = null,
      enrolledAt = null;

  final EdgeEnrollmentOutcome outcome;

  /// What to show the operator. The server's wording where it has one, because
  /// "expired" and "already used" need different actions from the same person.
  final String? message;

  /// Issued once. Held only long enough to persist it.
  final String? credential;
  final String? deviceId;
  final String? deviceName;
  final String? venueId;
  final String? venueName;

  /// Where this fleet should talk to Cloud, when the deployment declares one.
  final String? apiBaseUrl;
  final DateTime? enrolledAt;

  bool get isEnrolled => outcome == EdgeEnrollmentOutcome.enrolled;
}

/// `POST /edge/enroll` — the one call a POS makes before it has an identity.
///
/// The Venue is deliberately absent from the request. A terminal cannot name
/// the restaurant it would like to join; the enrollment code an administrator
/// created is what decides that, and the response reports which Venue it turned
/// out to be so the operator can check it before trusting the till.
///
/// Never throws. A failed enrollment leaves the POS exactly as it was.
class EdgeEnrollmentClient {
  EdgeEnrollmentClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _timeout = timeout;

  final http.Client _http;
  final Duration _timeout;

  Future<EdgeEnrollmentResult> enroll({
    required String baseUrl,
    required String code,
    required String installationId,
    required String platform,
    String? displayName,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse('$baseUrl/edge/enroll');
    } on FormatException {
      return const EdgeEnrollmentResult.failed(
        EdgeEnrollmentOutcome.unreachable,
        message: 'That server address cannot be read.',
      );
    }

    http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: json.encode(<String, dynamic>{
              'enrollmentCode': code,
              'installationId': installationId,
              'platform': platform,
              if (displayName != null && displayName.isNotEmpty)
                'displayName': displayName,
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      return const EdgeEnrollmentResult.failed(
        EdgeEnrollmentOutcome.unreachable,
      );
    }

    final body = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return EdgeEnrollmentResult.failed(
        _classify(response.statusCode),
        message: _message(body),
      );
    }
    if (body == null) {
      return const EdgeEnrollmentResult.failed(
        EdgeEnrollmentOutcome.serverError,
        message: 'The server answered with something this POS cannot read.',
      );
    }

    final credential = _string(body['credential']);
    final venue = body['venue'];
    final device = body['device'];
    if (credential == null || venue is! Map || device is! Map) {
      return const EdgeEnrollmentResult.failed(
        EdgeEnrollmentOutcome.serverError,
        message: 'The server did not return a usable device credential.',
      );
    }

    return EdgeEnrollmentResult(
      outcome: EdgeEnrollmentOutcome.enrolled,
      credential: credential,
      deviceId: _string(device['id']),
      deviceName: _string(device['displayName']),
      venueId: _string(venue['id']),
      venueName: _string(venue['name']),
      apiBaseUrl: _string(body['apiBaseUrl']),
      enrolledAt: DateTime.tryParse(_string(body['enrolledAt']) ?? ''),
    );
  }

  void close() => _http.close();

  static EdgeEnrollmentOutcome _classify(int statusCode) {
    if (statusCode == 401 || statusCode == 403 || statusCode == 400) {
      return EdgeEnrollmentOutcome.rejected;
    }
    if (statusCode == 409) return EdgeEnrollmentOutcome.conflict;
    if (statusCode == 429) return EdgeEnrollmentOutcome.throttled;
    if (statusCode == 404) {
      // A backend too old to know this route. Say so rather than blaming the
      // code the operator just typed correctly.
      return EdgeEnrollmentOutcome.serverError;
    }
    return EdgeEnrollmentOutcome.serverError;
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = json.decode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _message(Map<String, dynamic>? body) {
    final raw = body?['message'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List && raw.isNotEmpty) return '${raw.first}';
    return null;
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
