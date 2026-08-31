// GENERATED FILE — DO NOT EDIT.
//
// Rendered from packages/contracts/schema/table-identity.contract.json
// by packages/contracts/scripts/generate.mjs.
//
// Change the schema and regenerate; edits here are overwritten and
// CI fails on a stale or hand-edited output.

/// The Cloud → Edge work contract, as the POS sees it.
///
/// Cloud cannot reach a restaurant's LAN, so the Edge opens the connection with
/// its Device credential, claims work, executes it locally, and reports the
/// outcome. Delivery is at-least-once: a claim is a lease, and a lease that
/// expires unacknowledged is offered again, so every command type must be safe
/// to execute twice.
library;

/// The envelope version this build speaks. Sent on every claim so Cloud
/// withholds work this POS would not understand.
const int edgeCommandContractVersion = 1;

/// Batch size requested when none is given, and the ceiling Cloud enforces.
const int edgeCommandDefaultBatchSize = 20;
const int edgeCommandMaxBatchSize = 50;

/// How long a claimed command stays leased before Cloud offers it again.
const int edgeCommandClaimLeaseSeconds = 120;

/// Redeliveries before Cloud gives up on a command.
const int edgeCommandMaxAttempts = 10;

/// Every command type this contract version defines.
class EdgeCommandTypes {
  EdgeCommandTypes._();

  /// Does nothing on the Edge. Exists so the transport can be exercised end to end without performing restaurant work.
  static const String noop = 'NOOP';

  static const Set<String> all = <String>{'NOOP'};

  /// Types safe to execute more than once.
  ///
  /// A type absent from this set must not be executed on redelivery without a
  /// handler-specific idempotency boundary of its own.
  static const Set<String> idempotent = <String>{'NOOP'};
}

/// What the Edge may report back about a command.
class EdgeCommandResultStatus {
  EdgeCommandResultStatus._();

  static const String succeeded = 'SUCCEEDED';
  static const String failed = 'FAILED';
}

/// One unit of work, as the Edge receives it.
class EdgeCommandEnvelope {
  const EdgeCommandEnvelope({
    required this.contractVersion,
    required this.commandId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    required this.attempt,
    required this.issuedAt,
    required this.leaseExpiresAt,
  });

  final int contractVersion;
  final String commandId;
  final String type;
  final Object? payload;

  /// Stable per Venue: the same intent enqueued twice is the same command.
  final String idempotencyKey;

  /// How many times this command has been handed out, this delivery included.
  final int attempt;
  final DateTime issuedAt;

  /// After this instant Cloud may offer the command to an Edge again.
  final DateTime leaseExpiresAt;

  /// Whether this build understands the envelope well enough to execute it.
  bool get isSupportedVersion => contractVersion <= edgeCommandContractVersion;

  /// Parses one envelope, or throws [FormatException] on a malformed one.
  ///
  /// Deliberately strict about the fields the transport depends on: a command
  /// without an id or a type cannot be acknowledged, and silently defaulting
  /// either would lose work rather than report it.
  factory EdgeCommandEnvelope.fromJson(Map<String, dynamic> json) {
    final commandId = json['commandId'];
    final type = json['type'];
    if (commandId is! String || commandId.isEmpty) {
      throw const FormatException('Edge command is missing commandId');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('Edge command is missing type');
    }
    return EdgeCommandEnvelope(
      contractVersion: _asInt(json['contractVersion'], 0),
      commandId: commandId,
      type: type,
      payload: json['payload'],
      idempotencyKey: json['idempotencyKey'] is String
          ? json['idempotencyKey'] as String
          : '',
      attempt: _asInt(json['attempt'], 1),
      issuedAt: _asTime(json['issuedAt']),
      leaseExpiresAt: _asTime(json['leaseExpiresAt']),
    );
  }
}

/// What the Edge sends back once it has executed — or failed to execute — one.
class EdgeCommandResult {
  const EdgeCommandResult({
    required this.commandId,
    required this.status,
    this.code,
    this.detail,
  });

  const EdgeCommandResult.succeeded(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.succeeded;

  const EdgeCommandResult.failed(this.commandId, {this.code, this.detail})
    : status = EdgeCommandResultStatus.failed;

  final String commandId;
  final String status;

  /// Short machine-readable outcome, e.g. `printer_offline`.
  final String? code;
  final String? detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'contractVersion': edgeCommandContractVersion,
    'commandId': commandId,
    'status': status,
    if (code != null) 'code': code,
    if (detail != null) 'detail': detail,
  };
}

int _asInt(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

DateTime _asTime(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
