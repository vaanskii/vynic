import 'dart:convert';
import 'package:fixnum/fixnum.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';
import 'projection_codec.dart';

abstract interface class OrderTableTransport {
  Future<CommitResult> commit(CommitIntent intent);
  Future<ReplayPage> replay(ReplayRequest request);
  Future<ProjectionSnapshot> snapshot(SnapshotRequest request);
}

class GrpcOrderTableTransport implements OrderTableTransport {
  GrpcOrderTableTransport(this.client);
  final OrdersTablesClient client;
  @override
  Future<CommitResult> commit(CommitIntent intent) => client.commit(intent);
  @override
  Future<ReplayPage> replay(ReplayRequest request) => client.replay(request);
  @override
  Future<ProjectionSnapshot> snapshot(SnapshotRequest request) =>
      client.snapshot(request);
}

/// A durable shadow/isolated projection. Never pass the production Order/Table
/// boxes here. One Hive value stores a complete event frame and its cursor;
/// optional typed boxes are rebuildable views, made ready only after reconcile.
/// There is intentionally no production authority/cutover switch in Phase 2A.
class OrderTableCoordinator {
  OrderTableCoordinator({
    required this.box,
    required this.transport,
    required this.auth,
    this.orders,
    this.tables,
  });
  final Box box;
  final OrderTableTransport transport;
  final AuthenticatedRequest auth;
  final Box<Order>? orders;
  final Box<TableModel>? tables;
  bool _busy = false;
  bool ready = false;
  Map<String, dynamic> _frame = {};
  Int64 get cursor => Int64.parseInt(_frame['cursor'] as String? ?? '0');
  Int64 get epoch => Int64.parseInt(_frame['epoch'] as String? ?? '1');
  String? get pendingRequestId => _pending?.requestId;
  CommitResult? get lastResult {
    final value = _frame['lastResult'] as String?;
    return value == null ? null : CommitResult.fromBuffer(base64Decode(value));
  }

  CommitIntent? get _pending {
    final raw = _frame['pending'] as String?;
    return raw == null
        ? null
        : (CommitIntent.fromBuffer(base64Decode(raw))..auth = auth);
  }

  List<ProjectionEntity> get entities => (_frame['entities'] as Map? ?? {})
      .values
      .map((v) => ProjectionEntity.fromBuffer(base64Decode(v as String)))
      .toList();
  ProjectionEntity? entity(ProjectionEntity_Kind kind, String id) {
    for (final e in entities) {
      if (e.kind == kind && e.id == id) return e;
    }
    return null;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('Coordination operation already in flight');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<void> _save() async {
    // Encoding severs references from Hive's in-memory cache before mutation.
    try {
      await box.put('frame', jsonEncode(_frame));
      await box.flush();
    } catch (_) {
      ready = false;
      rethrow;
    }
  }

  Future<void> open() => _exclusive(() async {
    ready = false;
    final stored = box.get('frame') as String?;
    _frame = stored == null ? {} : jsonDecode(stored) as Map<String, dynamic>;
    final binding =
        '${auth.scope.venueId}/${auth.scope.installationId}/${auth.terminalId}';
    if (_frame['binding'] != null && _frame['binding'] != binding) {
      throw StateError(
        'Hive projection belongs to another Venue/Edge/terminal',
      );
    }
    _frame['binding'] = binding;
    _frame.putIfAbsent('epoch', () => '1');
    await _save();
    if (_pending != null) await _sendPending();
    await _catchUp();
    await _materialize();
    ready = true;
  });

  /// Persists exactly the expected revisions the operator read. It does not
  /// silently replace them after catching up, which would defeat conflict checks.
  Future<CommitIntent> prepare(List<EntityChange> changes) =>
      _exclusive(() async {
        if (!ready || _pending != null)
          throw StateError('Reconcile pending intent first');
        final intent = CommitIntent(
          auth: auth,
          requestId: const Uuid().v4(),
          authorityEpoch: epoch,
          changes: changes,
        );
        final stored = intent.deepCopy()..clearAuth();
        _frame['pending'] = base64Encode(stored.writeToBuffer());
        await _save();
        return intent;
      });
  Future<CommitResult> sendPending() => _exclusive(() async {
    if (!ready) throw StateError('Coordinator is not ready');
    return _sendPending();
  });
  Future<CommitResult> _sendPending() async {
    final pending = _pending;
    if (pending == null) throw StateError('No durable pending intent');
    final result = await transport.commit(pending);
    if (result.authorityEpoch != epoch) throw StateError('Epoch changed');
    if (result.outcome == CommitResult_Outcome.COMMITTED) {
      // Replay includes prior events from other terminals before our own ACK.
      // Never advance to the ACK's head while skipping unseen events.
      await _catchUp();
      if (cursor < result.event.sequence)
        throw StateError('ACK missing from replay');
    } else if (result.outcome == CommitResult_Outcome.CONFLICT) {
      await _catchUp();
    } else {
      throw StateError('Invalid commit outcome');
    }
    _frame['lastResult'] = base64Encode(result.writeToBuffer());
    _frame.remove('pending');
    await _save();
    await _materialize();
    return result;
  }

  Future<void> catchUp() => _exclusive(() async {
    if (!ready) throw StateError('Coordinator is not ready');
    await _catchUp();
    await _materialize();
  });
  Future<void> _catchUp() async {
    while (true) {
      final page = await transport.replay(
        ReplayRequest(
          auth: auth,
          authorityEpoch: epoch,
          afterSequence: cursor,
          limit: 50,
        ),
      );
      if (page.authorityEpoch != epoch || page.headSequence < cursor) {
        throw StateError('Edge projection rollback/epoch mismatch');
      }
      if (page.events.isEmpty && page.headSequence > cursor) {
        throw StateError('Replay gap; explicit bootstrap required');
      }
      for (final event in page.events) {
        if (event.authorityEpoch != epoch ||
            event.sequence != cursor + Int64.ONE) {
          throw StateError('Non-contiguous event replay');
        }
        final state = Map<String, dynamic>.from(
          _frame['entities'] as Map? ?? {},
        );
        for (final e in event.entities) {
          state[OrderTableCodec.key(e)] = base64Encode(e.writeToBuffer());
        }
        _frame['entities'] = state;
        _frame['cursor'] = event.sequence.toString();
        await _save();
      }
      if (cursor == page.headSequence) return;
    }
  }

  Future<void> bootstrap() => _exclusive(() async {
    if (!ready || _pending != null)
      throw StateError('Resolve pending intent before bootstrap');
    final snapshot = await transport.snapshot(
      SnapshotRequest(auth: auth, authorityEpoch: epoch),
    );
    if (snapshot.mode != 'SHADOW' ||
        snapshot.authorityEpoch != epoch ||
        snapshot.sequence < cursor) {
      throw StateError('Incompatible/rolled-back snapshot');
    }
    _frame['entities'] = {
      for (final e in snapshot.entities)
        OrderTableCodec.key(e): base64Encode(e.writeToBuffer()),
    };
    _frame['cursor'] = snapshot.sequence.toString();
    await _save();
    await _materialize();
  });
  Future<void> _materialize() async {
    if (orders == null || tables == null) return;
    ready = false;
    final displayIds = Map<String, dynamic>.from(
      _frame['displayIds'] as Map? ?? {},
    );
    for (final e in entities.where(
      (e) => e.kind == ProjectionEntity_Kind.ORDER,
    )) {
      displayIds.putIfAbsent(e.id, () => displayIds.length + 1);
    }
    _frame['displayIds'] = displayIds;
    await _save();
    final byId = {
      for (final e in entities.where(
        (e) => e.kind == ProjectionEntity_Kind.TABLE,
      ))
        e.id: e,
    };
    // Views are keyed by UUID, never by another terminal's display integer.
    for (final e in entities) {
      if (e.kind == ProjectionEntity_Kind.ORDER) {
        if (e.tombstone) {
          await orders!.delete(e.id);
          continue;
        }
        final doc = OrderTableCodec.document(e);
        final tableIds = (doc['tableIds'] as List).cast<String>();
        final order = Order.fromJson({
          ...doc,
          'orderId': displayIds[e.id],
          'edgeRevision': e.revision.toInt(),
          'tableNumbers': tableIds
              .map((id) => OrderTableCodec.document(byId[id]!)['tableNumber'])
              .toList(),
        });
        await orders!.put(e.id, order);
      } else {
        if (e.tombstone) {
          await tables!.delete(e.id);
          continue;
        }
        final doc = OrderTableCodec.document(e);
        final active = doc['activeOrderUuid'] as String?;
        await tables!.put(
          e.id,
          TableModel(
            floor: doc['floor'] as String,
            tableNumber: doc['tableNumber'] as String,
            isReserved: active != null,
            activeOrderId: active == null ? null : displayIds[active] as int,
            edgeRevision: e.revision.toInt(),
          ),
        );
      }
    }
    await orders!.flush();
    await tables!.flush();
    ready = true;
  }
}
