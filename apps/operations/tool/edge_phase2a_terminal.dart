// Separate-process, separate-Hive terminal for the Phase 2A proof. No POS startup,
// printers, payment services, production settings, or Cloud transport are loaded.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/orders_tables/coordinator.dart';
import 'package:vynic/core/services/edge/orders_tables/projection_codec.dart';
import 'package:vynic/core/services/edge/orders_tables/shadow.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';

class LoseAck implements OrderTableTransport {
  LoseAck(this.inner);
  final OrderTableTransport inner;
  @override
  Future<CommitResult> commit(CommitIntent intent) async {
    await inner.commit(intent);
    // Abrupt process death after SQLite commit and before any Hive reconciliation.
    exit(17);
  }

  @override
  Future<ReplayPage> replay(ReplayRequest request) => inner.replay(request);
  @override
  Future<ProjectionSnapshot> snapshot(SnapshotRequest request) =>
      inner.snapshot(request);
}

Future<void> main(List<String> args) async {
  final config =
      jsonDecode(await File(args.single).readAsString())
          as Map<String, dynamic>;
  final dir = Directory(config['data'] as String);
  await dir.create(recursive: true);
  final lock = await File(
    '${dir.path}/terminal.lock',
  ).open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  ClientChannel? channel;
  try {
    Hive.init(dir.path);
    Hive.registerAdapter(OrderAdapter());
    Hive.registerAdapter(OrderItemAdapter());
    Hive.registerAdapter(TableModelAdapter());
    final meta = await Hive.openBox('coordination');
    final orders = await Hive.openBox<Order>('orders');
    final tables = await Hive.openBox<TableModel>('tables');
    var identity = (meta.get('identity') as Map?)?.cast<String, String>();
    if (identity == null) {
      identity = {
        'terminal': const Uuid().v4(),
        'request': const Uuid().v4(),
        'secret': base64UrlEncode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ).replaceAll('=', ''),
        'venue': config['venue'] as String,
        'installation': config['installation'] as String,
      };
      await meta.put('identity', identity);
      await meta.flush();
    }
    if (identity['venue'] != config['venue'] ||
        identity['installation'] != config['installation'])
      throw StateError('Immutable binding mismatch');
    final cert = await File(config['cert'] as String).readAsBytes();
    final der = base64Decode(
      utf8.decode(cert).replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
    );
    final address = (config['address'] as String).split(':');
    channel = ClientChannel(
      address[0],
      port: int.parse(address[1]),
      options: ChannelOptions(
        credentials: ChannelCredentials.secure(
          certificates: cert,
          authority: 'vynic-edge.local',
          onBadCertificate: (certificate, host) {
            final now = DateTime.now();
            final actual = certificate.der;
            if (host != 'vynic-edge.local' ||
                now.isBefore(certificate.startValidity) ||
                now.isAfter(certificate.endValidity) ||
                actual.length != der.length)
              return false;
            for (var i = 0; i < der.length; i++) {
              if (der[i] != actual[i]) return false;
            }
            return true;
          },
        ),
      ),
    );
    final scope = Scope(
      venueId: identity['venue'],
      installationId: identity['installation'],
      protocol: Protocol(
        major: 1,
        minor: 1,
        requiredCapabilities: ['orders_tables.shadow'],
      ),
    );
    final auth = AuthenticatedRequest(
      scope: scope,
      terminalId: identity['terminal'],
      terminalSecret: identity['secret'],
    );
    final options = CallOptions(timeout: const Duration(seconds: 8));
    if (config['ticket'] != null) {
      await FoundationClient(channel, options: options).pair(
        PairRequest(
          scope: scope,
          terminalId: auth.terminalId,
          terminalSecret: auth.terminalSecret,
          requestId: identity['request'],
          ticket: config['ticket'] as String,
          displayName: config['name'] as String,
        ),
      );
    }
    OrderTableTransport transport = GrpcOrderTableTransport(
      OrdersTablesClient(channel, options: options),
      shutdown: channel.shutdown,
    );
    if (config['loseAck'] == true) transport = LoseAck(transport);
    final isShadow = config['action'] == 'shadow';
    final coordinator = OrderTableCoordinator(
      box: meta,
      transport: transport,
      auth: auth,
      orders: isShadow ? null : orders,
      tables: isShadow ? null : tables,
    );
    await coordinator.open();
    CommitResult? result;
    final changes = (config['changes'] as List? ?? []).map((raw) {
      final c = Map<String, dynamic>.from(raw as Map);
      return EntityChange(
        expectedRevision: Int64(c['expected'] as int),
        entity: ProjectionEntity(
          kind: c['kind'] == 'order'
              ? ProjectionEntity_Kind.ORDER
              : ProjectionEntity_Kind.TABLE,
          id: c['id'] as String,
          tombstone: c['tombstone'] == true,
          document: c['tombstone'] == true
              ? []
              : utf8.encode(jsonEncode(c['document'])),
        ),
      );
    }).toList();
    if (config['action'] == 'commit' || config['action'] == 'prepare') {
      await coordinator.prepare(changes);
      if (config['action'] == 'commit')
        result = await coordinator.sendPending();
    } else if (config['action'] == 'snapshot') {
      await coordinator.bootstrap();
    } else if (isShadow) {
      OrderTableShadow.observer = OrderTableShadow(coordinator);
      final proposed = changes.map((c) => c.entity).toList();
      // Use the actual Flutter Order model and durable typed Hive boxes. The
      // deliberately injected mismatch proves diagnostics detect divergence.
      await OrderTableShadow.observe(
        proposed: () => proposed,
        operation: () async {
          for (final e in proposed) {
            if (e.kind == ProjectionEntity_Kind.ORDER) {
              final doc = OrderTableCodec.document(e);
              final order = Order.fromJson({
                ...doc,
                'tableNumbers': <String>[],
              });
              order.recalculateTotal();
              if (config['mismatch'] == true) order.items.first.quantity++;
              await orders.put(e.id, order);
            }
          }
          await orders.flush();
        },
        actual: () => [
          for (final e in proposed)
            if (e.kind == ProjectionEntity_Kind.ORDER)
              OrderTableCodec.order(orders.get(e.id)!, const [])
            else
              e,
        ],
      );
      OrderTableShadow.observer = null;
    }
    stdout.writeln(
      jsonEncode({
        'terminalId': auth.terminalId,
        'data': dir.path,
        'cursor': coordinator.cursor.toInt(),
        'pending': coordinator.pendingRequestId,
        'outcome': result?.outcome.name,
        'current': result?.current
            .map(
              (e) => {
                'id': e.id,
                'revision': e.revision.toInt(),
                'tombstone': e.tombstone,
              },
            )
            .toList(),
        'sequence': result?.event.sequence.toInt(),
        'projection': [
          for (final e in coordinator.entities)
            {
              'kind': e.kind.name,
              'id': e.id,
              'revision': e.revision.toInt(),
              'tombstone': e.tombstone,
              'document': e.tombstone ? null : OrderTableCodec.document(e),
            },
        ],
        'orders': [
          for (final o in orders.values)
            {
              'id': o.orderUuid,
              'revision': o.edgeRevision,
              'items': o.items.map((i) => i.toJson()).toList(),
              'total': o.totalAmount,
            },
        ],
        'tables': [
          for (final k in tables.keys)
            {
              'id': k,
              'revision': tables.get(k)!.edgeRevision,
              'activeOrderId': tables.get(k)!.activeOrderId,
            },
        ],
        'diagnostics': meta.get('diagnostics') ?? [],
      }),
    );
  } finally {
    await channel?.shutdown();
    await Hive.close();
    await lock.unlock();
    await lock.close();
  }
}
