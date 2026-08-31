import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/contracts/edge_command.dart';

/// The generated Cloud → Edge envelope, exercised the way the transport uses it.
///
/// Parsing is deliberately strict about the two fields the transport cannot do
/// without: a command with no id can never be acknowledged, and one with no type
/// can never be routed to a handler. Everything else has a defined fallback,
/// because losing a whole batch to one soft field would be worse than the field.
void main() {
  Map<String, dynamic> envelope({
    Object? commandId = 'cmd-1',
    Object? type = 'NOOP',
    Object? contractVersion = 1,
  }) => <String, dynamic>{
    'contractVersion': contractVersion,
    'commandId': commandId,
    'type': type,
    'payload': <String, dynamic>{'note': 'hello'},
    'idempotencyKey': 'key-1',
    'attempt': 2,
    'issuedAt': '2026-09-01T10:00:00.000Z',
    'leaseExpiresAt': '2026-09-01T10:02:00.000Z',
  };

  group('EdgeCommandEnvelope.fromJson', () {
    test('reads a well-formed envelope', () {
      final command = EdgeCommandEnvelope.fromJson(envelope());

      expect(command.commandId, 'cmd-1');
      expect(command.type, EdgeCommandTypes.noop);
      expect(command.idempotencyKey, 'key-1');
      expect(command.attempt, 2);
      expect(command.contractVersion, 1);
      expect(command.issuedAt.isUtc, isTrue);
      expect(
        command.leaseExpiresAt.difference(command.issuedAt),
        const Duration(minutes: 2),
      );
      expect((command.payload as Map)['note'], 'hello');
    });

    test('refuses an envelope with nothing to acknowledge or route', () {
      expect(
        () => EdgeCommandEnvelope.fromJson(envelope(commandId: null)),
        throwsFormatException,
      );
      expect(
        () => EdgeCommandEnvelope.fromJson(envelope(commandId: '')),
        throwsFormatException,
      );
      expect(
        () => EdgeCommandEnvelope.fromJson(envelope(type: null)),
        throwsFormatException,
      );
    });

    test('falls back rather than failing on soft fields', () {
      final command = EdgeCommandEnvelope.fromJson(<String, dynamic>{
        'commandId': 'cmd-2',
        'type': 'NOOP',
      });

      expect(command.attempt, 1);
      expect(command.idempotencyKey, '');
      expect(command.issuedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('contract version', () {
    test('accepts this version and older', () {
      expect(
        EdgeCommandEnvelope.fromJson(
          envelope(contractVersion: edgeCommandContractVersion),
        ).isSupportedVersion,
        isTrue,
      );
      expect(
        EdgeCommandEnvelope.fromJson(
          envelope(contractVersion: edgeCommandContractVersion - 1),
        ).isSupportedVersion,
        isTrue,
      );
    });

    test('refuses a newer contract instead of guessing at it', () {
      expect(
        EdgeCommandEnvelope.fromJson(
          envelope(contractVersion: edgeCommandContractVersion + 1),
        ).isSupportedVersion,
        isFalse,
      );
    });
  });

  group('EdgeCommandResult', () {
    test('carries the version it was produced by', () {
      final json = const EdgeCommandResult.succeeded('cmd-1').toJson();

      expect(json['contractVersion'], edgeCommandContractVersion);
      expect(json['status'], 'SUCCEEDED');
      expect(json.containsKey('code'), isFalse);
    });

    test('reports a failure reason without a payload', () {
      final json = const EdgeCommandResult.failed(
        'cmd-1',
        code: 'printer_offline',
        detail: 'no response',
      ).toJson();

      expect(json['status'], 'FAILED');
      expect(json['code'], 'printer_offline');
      expect(json['detail'], 'no response');
    });
  });

  test('NOOP is the only type this build ships, and it is idempotent', () {
    // Guards the rule the queue enforces on the other side: a type that cannot
    // absorb being delivered twice must not be executable here either.
    expect(EdgeCommandTypes.all, <String>{EdgeCommandTypes.noop});
    expect(EdgeCommandTypes.idempotent, contains(EdgeCommandTypes.noop));
  });
}
