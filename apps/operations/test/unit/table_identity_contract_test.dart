import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

/// Golden compatibility tests for the table-identity contract.
///
/// The vectors in `packages/contracts/schema/table-identity.vectors.json` are
/// read by this suite and by the TypeScript suite in
/// `apps/backend/src/website/reservation/table-identity-contract.spec.ts`.
/// One fixture, two languages: that is what proves the two implementations
/// agree, rather than a comment asserting that they do.
///
/// These tests were written against the hand-written implementations, before
/// either side was switched to the generated contract, so they pin existing
/// behaviour rather than describing the intended behaviour.

Map<String, dynamic> _loadVectors() {
  // Flutter runs tests with the package directory as the working directory.
  final file = File('../../packages/contracts/schema/table-identity.vectors.json');
  if (!file.existsSync()) {
    throw StateError(
      'Contract vectors not found at ${file.absolute.path}. '
      'They live in packages/contracts and are shared with apps/backend.',
    );
  }
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _cases(Object? raw) =>
    (raw as List).cast<Map<String, dynamic>>();

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors = _loadVectors();
  });

  test('the fixture is the contract version this build expects', () {
    expect(vectors['contractVersion'], 1);
  });

  group('encodeTableCode', () {
    test('every valid vector encodes to its recorded code', () {
      for (final v in _cases(vectors['encode']['valid'])) {
        expect(
          ReservationTableAvailability.encodeTableCode(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          ),
          v['code'],
          reason: 'floor=${v['floor']} tableNumber="${v['tableNumber']}"',
        );
      }
    });

    test('every invalid vector is rejected rather than mis-encoded', () {
      for (final v in _cases(vectors['encode']['invalid'])) {
        expect(
          () => ReservationTableAvailability.encodeTableCode(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          ),
          throwsArgumentError,
          reason:
              'floor=${v['floor']} tableNumber="${v['tableNumber']}" — ${v['why']}',
        );
      }
    });
  });

  group('decodeTableCode', () {
    test('every vector decodes to its recorded floor and table', () {
      for (final v in _cases(vectors['decode']['cases'])) {
        final decoded = ReservationTableAvailability.decodeTableCode(
          v['code'] as int,
        );
        expect(decoded.floor, v['floor'], reason: 'code=${v['code']}');
        expect(
          decoded.tableNumber,
          v['tableNumber'],
          reason: 'code=${v['code']}',
        );
      }
    });

    test('encode and decode round-trip for every valid encode vector', () {
      for (final v in _cases(vectors['encode']['valid'])) {
        final code = ReservationTableAvailability.encodeTableCode(
          floor: v['floor'] as String,
          tableNumber: v['tableNumber'] as String,
        );
        final back = ReservationTableAvailability.decodeTableCode(code);
        expect(back.floor, v['floor'], reason: 'code=$code');
        expect(
          back.tableNumber,
          (v['tableNumber'] as String).trim(),
          reason: 'code=$code',
        );
      }
    });
  });

  group('canEncodeTableCode', () {
    test('decides bookability exactly as recorded', () {
      for (final v in _cases(vectors['canEncode']['cases'])) {
        expect(
          ReservationTableAvailability.canEncodeTableCode(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          ),
          v['expected'],
          reason: 'floor=${v['floor']} tableNumber="${v['tableNumber']}"',
        );
      }
    });

    test('agrees with encodeTableCode on every canEncode vector', () {
      // Whatever canEncode permits, encode must accept — and vice versa.
      // A disagreement is how a table becomes visible in a picker and then
      // throws when the booking is submitted.
      for (final v in _cases(vectors['canEncode']['cases'])) {
        final permitted = v['expected'] as bool;
        var encoded = true;
        try {
          ReservationTableAvailability.encodeTableCode(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          );
        } on ArgumentError {
          encoded = false;
        }
        expect(
          encoded,
          permitted,
          reason: 'floor=${v['floor']} tableNumber="${v['tableNumber']}"',
        );
      }
    });
  });

  group('TableRef', () {
    test('encodes to floor/tableNumber', () {
      for (final v in _cases(vectors['tableRef']['encode'])) {
        expect(
          TableRef(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          ).encode(),
          v['encoded'],
        );
      }
    });

    test('decodes every valid form', () {
      for (final v in _cases(vectors['tableRef']['decode'])) {
        final ref = TableRef.tryDecode(v['raw'] as String);
        expect(ref, isNotNull, reason: 'raw="${v['raw']}"');
        expect(ref!.floor, v['floor'], reason: 'raw="${v['raw']}"');
        expect(ref.tableNumber, v['tableNumber'], reason: 'raw="${v['raw']}"');
      }
    });

    test('returns null for every malformed form', () {
      for (final v in _cases(vectors['tableRef']['decodeInvalid'])) {
        expect(
          TableRef.tryDecode(v['raw'] as String),
          isNull,
          reason: 'raw="${v['raw']}" — ${v['why']}',
        );
      }
    });
  });

  group('legacy divergence', () {
    test('Dart is the strict side the contract converges on', () {
      // The TypeScript implementation accepted these and returned a number;
      // Dart rejects them. The contract adopts the Dart behaviour, so this
      // asserts the side that does NOT change.
      expect(vectors['legacyDivergence']['resolution'], 'strict');
      for (final v in _cases(vectors['legacyDivergence']['cases'])) {
        expect(v['dart'], 'throws');
        expect(
          () => ReservationTableAvailability.encodeTableCode(
            floor: v['floor'] as String,
            tableNumber: v['tableNumber'] as String,
          ),
          throwsArgumentError,
          reason: 'floor=${v['floor']} tableNumber="${v['tableNumber']}"',
        );
      }
    });
  });
}
