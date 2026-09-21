import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:fixnum/fixnum.dart';
import 'package:collection/collection.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';
import 'coordinator.dart';
import 'projection_codec.dart';

/// Explicit development attachment only. No startup/Cloud setting enables this
/// observer. Failure never redirects or authorizes the primary POS operation.
class OrderTableShadow {
  OrderTableShadow(this.coordinator);
  final OrderTableCoordinator coordinator;
  static OrderTableShadow? observer;
  static final _zoneKey = Object();

  /// Called explicitly on the Phase 0 Primary's stopped-at-a-quiescent-point
  /// ordinary Order/Table state. Never clears/replaces existing Edge history.
  Future<void> seedPrimary(List<ProjectionEntity> Function() capture) async {
    await coordinator.catchUp();
    if (coordinator.cursor != Int64.ZERO || coordinator.entities.isNotEmpty) {
      throw StateError('Shadow seed requires an empty Edge projection');
    }
    if (!identical(observer, this))
      throw StateError('Attach this shadow observer first');
    await observe(proposed: capture, operation: () async {}, actual: capture);
    final diagnostics = coordinator.box.get('diagnostics') as List?;
    if (coordinator.cursor == Int64.ZERO ||
        diagnostics == null ||
        diagnostics.isEmpty ||
        jsonDecode(diagnostics.last as String)['kind'] != 'matched') {
      throw StateError('Shadow seed was not verified; inspect diagnostics');
    }
  }

  static Future<T> observe<T>({
    required List<ProjectionEntity> Function() proposed,
    required Future<T> Function() operation,
    required List<ProjectionEntity> Function() actual,
  }) async {
    final shadow = observer;
    if (shadow == null || Zone.current[_zoneKey] == true) return operation();
    return runZoned(() async {
      CommitResult? result;
      try {
        if (shadow.coordinator.pendingRequestId != null) {
          await shadow.coordinator.sendPending();
        }
        await shadow.coordinator.catchUp();
        final changes = proposed()
            .map(
              (entity) => EntityChange(
                entity: entity,
                expectedRevision:
                    shadow.coordinator
                        .entity(entity.kind, entity.id)
                        ?.revision ??
                    Int64.ZERO,
              ),
            )
            .toList();
        await shadow.coordinator.prepare(changes);
        result = await shadow.coordinator.sendPending();
      } catch (error, stack) {
        await shadow._diagnostic('proposal_failed', error.toString(), stack);
      }
      T value;
      try {
        value = await operation();
      } catch (error, stack) {
        await shadow._diagnostic('operational_failed', error.toString(), stack);
        rethrow;
      }
      try {
        if (result == null ||
            result.outcome != CommitResult_Outcome.COMMITTED) {
          await shadow._diagnostic(
            'uncompared',
            'No committed shadow proposal',
          );
        } else {
          final expected = {
            for (final e in result.event.entities)
              OrderTableCodec.key(e): _comparison(e),
          };
          final observed = {
            for (final e in actual()) OrderTableCodec.key(e): _comparison(e),
          };
          final matches = const DeepCollectionEquality().equals(
            expected,
            observed,
          );
          await shadow._diagnostic(
            matches ? 'matched' : 'mismatch',
            result.event.requestId,
          );
        }
      } catch (error, stack) {
        await shadow._diagnostic('comparison_failed', error.toString(), stack);
      }
      return value;
    }, zoneValues: {_zoneKey: true});
  }

  static Object _comparison(ProjectionEntity e) => {
    'tombstone': e.tombstone,
    'document': e.tombstone ? null : jsonDecode(utf8.decode(e.document)),
  };
  Future<void> _diagnostic(
    String kind,
    String detail, [
    StackTrace? stack,
  ]) async {
    developer.log(
      '$kind: $detail',
      name: 'EdgeOrdersTablesShadow',
      stackTrace: stack,
    );
    // Bounded local diagnostics; projection/event retention is independent.
    try {
      final box = coordinator.box;
      final previous = (box.get('diagnostics') as List? ?? []).cast<String>();
      final next = [
        ...previous,
        jsonEncode({'kind': kind, 'detail': detail}),
      ];
      await box.put(
        'diagnostics',
        next.skip(next.length > 100 ? next.length - 100 : 0).toList(),
      );
      await box.flush();
    } catch (error, trace) {
      developer.log(
        'Cannot persist shadow diagnostic',
        name: 'EdgeOrdersTablesShadow',
        error: error,
        stackTrace: trace,
      );
    }
  }
}
