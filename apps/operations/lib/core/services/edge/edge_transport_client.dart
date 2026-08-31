import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/sync/api_config.dart';

/// Why a transport call did not produce work.
enum EdgeTransportOutcome {
  ok,

  /// No Device credential on this installation — nothing to authenticate with.
  notProvisioned,

  /// Cloud rejected the credential: revoked device, disabled venue, wrong secret.
  unauthorized,

  /// Cloud answered with something else — a 5xx, a malformed body.
  serverError,

  /// Cloud could not be reached at all. The normal state of an offline POS.
  unreachable,
}

class EdgeClaimResponse {
  const EdgeClaimResponse(this.outcome, {this.commands = const []});

  final EdgeTransportOutcome outcome;
  final List<EdgeCommandEnvelope> commands;

  bool get isOk => outcome == EdgeTransportOutcome.ok;
}

/// HTTP for `POST /edge/commands/claim` and `POST /edge/commands/ack`.
///
/// The Edge opens every connection; Cloud never dials this machine. The Venue
/// is deliberately absent from both requests — Cloud derives it from the Device
/// credential, and a POS that could name its own Venue would be a POS that
/// could name someone else's.
///
/// Never throws. Every failure is an outcome the caller can act on, because a
/// POS that cannot reach Cloud has to keep taking orders.
class EdgeTransportClient {
  EdgeTransportClient({
    http.Client? httpClient,
    String Function()? baseUrl,
    String? Function()? credential,
    Duration timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? (() => ApiConfig.baseUrl),
       _credential =
           credential ?? (() => EdgeDeviceCredentialStore.credential),
       _timeout = timeout;

  final http.Client _http;
  final String Function() _baseUrl;
  final String? Function() _credential;
  final Duration _timeout;

  /// Asks Cloud for work this installation may run.
  Future<EdgeClaimResponse> claim({int? limit}) async {
    final headers = _headers();
    if (headers == null) {
      return const EdgeClaimResponse(EdgeTransportOutcome.notProvisioned);
    }

    try {
      final response = await _http
          .post(
            Uri.parse('${_baseUrl()}/edge/commands/claim'),
            headers: headers,
            body: json.encode(<String, dynamic>{
              'limit': limit ?? edgeCommandDefaultBatchSize,
              // Only work this build understands. Cloud withholds the rest
              // rather than handing over an envelope we would have to guess at.
              'acceptedContractVersions': <int>[edgeCommandContractVersion],
            }),
          )
          .timeout(_timeout);

      final outcome = _classify(response.statusCode);
      if (outcome != EdgeTransportOutcome.ok) {
        return EdgeClaimResponse(outcome);
      }

      // Parsed separately from the request: a body we cannot read is a server
      // problem, not an unreachable network, and the two lead to different
      // conclusions about whether to keep trying.
      final Object? decoded;
      try {
        decoded = json.decode(response.body);
      } on FormatException {
        return const EdgeClaimResponse(EdgeTransportOutcome.serverError);
      }
      if (decoded is! Map<String, dynamic>) {
        return const EdgeClaimResponse(EdgeTransportOutcome.serverError);
      }
      final raw = decoded['commands'];
      if (raw is! List) {
        return const EdgeClaimResponse(EdgeTransportOutcome.serverError);
      }

      final commands = <EdgeCommandEnvelope>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          commands.add(
            EdgeCommandEnvelope.fromJson(Map<String, dynamic>.from(item)),
          );
        } on FormatException {
          // One unusable envelope must not discard the rest of the batch.
          continue;
        }
      }
      return EdgeClaimResponse(EdgeTransportOutcome.ok, commands: commands);
    } catch (_) {
      return const EdgeClaimResponse(EdgeTransportOutcome.unreachable);
    }
  }

  /// Reports what happened to one command. Safe to repeat: Cloud keeps the
  /// first outcome a command ended with.
  Future<EdgeTransportOutcome> acknowledge(EdgeCommandResult result) async {
    final headers = _headers();
    if (headers == null) return EdgeTransportOutcome.notProvisioned;

    try {
      final response = await _http
          .post(
            Uri.parse('${_baseUrl()}/edge/commands/ack'),
            headers: headers,
            body: json.encode(result.toJson()),
          )
          .timeout(_timeout);
      return _classify(response.statusCode);
    } catch (_) {
      return EdgeTransportOutcome.unreachable;
    }
  }

  void close() => _http.close();

  Map<String, String>? _headers() {
    final credential = _credential();
    if (credential == null || credential.isEmpty) return null;
    return <String, String>{
      'Content-Type': 'application/json',
      'X-POS-Sync-Key': credential,
    };
  }

  static EdgeTransportOutcome _classify(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return EdgeTransportOutcome.ok;
    if (statusCode == 401 || statusCode == 403) {
      return EdgeTransportOutcome.unauthorized;
    }
    return EdgeTransportOutcome.serverError;
  }
}
