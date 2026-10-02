import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import '../support/pos03_fixture.dart';

/// Real historical bytes omit UUID fields, without editing generated adapters.
class Pos03LegacyItemAdapter extends OrderItemAdapter {
  @override
  void write(BinaryWriter writer, OrderItem item) {
    final fields = [
      item.itemKey,
      item.itemName,
      item.unitPrice,
      item.quantity,
      item.total,
      item.comment,
      item.menuItemId,
      item.variantId,
    ];
    writer.writeByte(fields.length);
    for (var field = 0; field < fields.length; field++) {
      writer.writeByte(field);
      writer.write(fields[field]);
    }
  }
}

class Pos03LegacyOrderAdapter extends OrderAdapter {
  @override
  void write(BinaryWriter writer, Order order) {
    final fields = <int, dynamic>{
      0: order.orderId,
      1: order.tableNumbers,
      2: order.floor,
      3: order.items,
      4: order.totalAmount,
      5: order.createdAt,
      6: order.createdBy,
      7: order.status,
      8: order.updatedAt,
      9: order.includeServiceFee,
      10: order.paymentMethod,
      11: order.closedAt,
      12: order.discountAmount,
      13: order.packageId,
      14: order.packageName,
      15: order.packagePrice,
      16: order.packageItems,
      17: order.packageUnitPrice,
      18: order.packageGuestCount,
      19: order.manualAdjustmentAmount,
      20: order.openedByUserId,
      21: order.customServiceFeePercentage,
      22: order.closureId,
      23: order.advanceAmount,
      24: order.advanceCollectedOn,
      25: order.advanceReceiptId,
      26: order.customerName,
      27: order.customerPhone,
      28: order.pickupTime,
      30: order.edgeRevision,
    };
    writer.writeByte(fields.length);
    for (final entry in fields.entries) {
      writer.writeByte(entry.key);
      writer.write(entry.value);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos03Fixture fixture;
  late HttpOverrides? previous;
  setUp(() async {
    previous = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos03-compat-');
    fixture = Pos03Fixture();
    await fixture.open(root.path);
    await fixture.seed();
  });
  tearDown(() async {
    await fixture.close();
    HttpOverrides.global = previous;
    Hive.registerAdapter(OrderAdapter(), override: true);
    Hive.registerAdapter(OrderItemAdapter(), override: true);
    await root.delete(recursive: true);
  });
  Future<String> backup() async => (await BackupRepository.createDataBackup(
    targetFilePath: '${root.path}/portable.json',
  )).readAsString();
  Future<void> fresh(String payload) async {
    await fixture.close();
    final destination = '${root.path}/fresh';
    await Directory(destination).create();
    await fixture.open(destination);
    await BackupRepository.restoreDataBackupFromJson(
      payload,
      backupBeforeRestore: false,
    );
  }

  String reseal(Map<String, dynamic> payload) {
    payload.remove('integrity');
    PosBackupFormat.seal(payload);
    PosBackupFormat.validate(payload);
    return jsonEncode(payload);
  }

  void verifyRestored() {
    final source = DatabaseCore.orderBox!.get('source')!;
    final destination = DatabaseCore.orderBox!.get('destination')!;
    expect(source.orderUuid, pos03SourceUuid);
    expect(destination.orderUuid, pos03DestinationUuid);
    expect(source.items, isEmpty);
    expect(source.status, 'closed');
    expect(destination.items.single.quantity, 5);
    expect(destination.items.single.total, 12.51);
    expect(destination.items.single.menuItemId, 'menu-identity');
    expect(destination.items.single.variantId, 'variant-identity');
    expect(source.openedByUserId, 'owner');
    expect(source.customerName, 'Synthetic guest');
    expect(DatabaseCore.tableBox!.get('source-table')!.activeOrderId, isNull);
    expect(DatabaseCore.tableBox!.get('destination-table')!.activeOrderId, 2);
    expect(DatabaseCore.reservationBox!.get('booking')!.status, 'completed');
    expect(
      DatabaseCore.reservationBox!.get('bookkeeping')!.status,
      'in-progress',
    );
    expect(DatabaseCore.salesBox!.length, 1);
    expect(DatabaseCore.salesBox!.get('historical')['totalAmount'], 70.0);
    expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    final sourceReport = AuditReport.fromMap(
      DatabaseCore.auditLogBox!.get('audit_report_order_1') as Map,
    );
    final destinationReport = AuditReport.fromMap(
      DatabaseCore.auditLogBox!.get('audit_report_order_2') as Map,
    );
    expect(sourceReport.events.map((e) => e.type), [
      AuditEventType.moveItems,
      AuditEventType.transferClose,
    ]);
    expect(sourceReport.locked, true);
    expect(destinationReport.events.map((e) => e.type), [
      AuditEventType.moveItems,
    ]);
    for (final event in [...sourceReport.events, ...destinationReport.events])
      expect(event.details!['transferId'], pos03Id);
    final audits = DatabaseCore.auditLogBox!.values
        .whereType<Map>()
        .where((row) => row['action'] != null)
        .map((row) => AuditEventLog.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    expect(audits, hasLength(2));
    expect(
      audits.where((row) => row.action == GlobalAuditAction.backupRestored),
      hasLength(1),
    );
    final completed = audits.singleWhere(
      (row) => row.action == 'COMPLETE_RESERVATION',
    );
    expect(completed.data['transferId'], pos03Id);
    expect(completed.data['previousStatus'], 'in-progress');
    expect(OrderTransferJournalRepository.read(pos03Id)!.pending, false);
    expect(LocalDataAdmission.failure, isNull);
  }

  Map<dynamic, dynamic> stableTransferAudits() =>
      Map.of(DatabaseCore.auditLogBox!.toMap())..removeWhere(
        (key, value) =>
            value is Map && value['action'] == GlobalAuditAction.backupRestored,
      );

  test(
    'completed format2 receipt restores exact audits and frozen line total',
    () async {
      expect((await fixture.apply()).ok, true);
      final payload = await backup();
      await fresh(payload);
      verifyRestored();
      final before = jsonEncode(stableTransferAudits());
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      verifyRestored();
      expect(jsonEncode(stableTransferAudits()), before);
      expect(DatabaseCore.dbVersion, 9);
    },
  );

  test(
    'pending portable image replays before restore admission is released',
    () async {
      final envelope = await PosBackupFormat.decode(await backup());
      Map? pending;
      fixture.fault = (point, _) async {
        if (point == 'meta.put:transfer:intent:after') {
          pending = Map.of(
            DatabaseCore.metaBox!.get(
                  OrderTransferJournalRepository.key(pos03Id),
                )
                as Map,
          );
          throw const FileSystemException('synthetic intent interruption');
        }
      };
      expect((await fixture.apply()).ok, false);
      expect(LocalDataAdmission.failure, isNotNull);
      // Assemble the pre-effect snapshot already captured above; admission is
      // never disabled to export a half-applied live operation.
      (envelope['stores']['meta'] as List).add({
        'key': OrderTransferJournalRepository.key(pos03Id),
        'value': PosBackupFormat.encodeValue(pending),
      });
      await fresh(reseal(envelope));
      verifyRestored();
      expect(LocalDataAdmission.blocked, false);
    },
  );

  test(
    'completed retry marker does not restore old images over later normal edits',
    () async {
      expect((await fixture.apply()).ok, true);
      final row = DatabaseCore.orderBox!.get('destination')!.clone();
      row.items.single.quantity = 8;
      row.items.single.total = 20.01;
      await DatabaseCore.orderBox!.put('destination', row);
      final payload = await backup();
      await fresh(payload);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        8,
      );
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.total,
        20.01,
      );
      expect((await fixture.apply()).ok, true);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        8,
      );
    },
  );

  test(
    'journal-less schema9 format2 stays readable and lossless; legacy import contract stays separate',
    () async {
      await fixture.seed(rich: true);
      final before = OrderTransferIntent.snapshot(fixture.originalSource!);
      final payload = await backup();
      await fresh(payload);
      expect(OrderTransferJournalRepository.records(), isEmpty);
      expect(
        OrderTransferIntent.snapshot(DatabaseCore.orderBox!.get('source')!),
        before,
      );
      expect(DatabaseCore.orderBox!.get('source')!.items.single.total, 10.01);
      expect(
        DatabaseCore.orderBox!.get('source')!.packageItems.single.total,
        7.11,
      );
      expect(DatabaseCore.orderBox!.get('source')!.advanceAmount, 1.17);
      final legacy = BackupRepository.serializeOrder(fixture.originalSource!);
      await BackupRepository.replaceOrdersFromJson([legacy]);
      final imported = DatabaseCore.orderBox!.values.single;
      // Legacy loose JSON import intentionally keeps its existing recalculation.
      expect(imported.items.single.total, 10.0);
      expect(DatabaseCore.salesBox!.get('historical')['totalAmount'], 70.0);
    },
  );

  test(
    'valid-envelope unsupported journal is rejected before replacement',
    () async {
      final envelope = await PosBackupFormat.decode(await backup());
      (envelope['stores']['meta'] as List).add({
        'key': OrderTransferJournalRepository.key(pos03Id),
        'value': PosBackupFormat.encodeValue({
          'version': 99,
          'phase': 'completed',
        }),
      });
      final before = OrderTransferIntent.snapshot(
        DatabaseCore.orderBox!.get('source')!,
      );
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          reseal(envelope),
          backupBeforeRestore: false,
        ),
        throwsA(
          isA<FormatException>().having(
            (v) => v.message,
            'journal reason',
            contains('Order transfer journal'),
          ),
        ),
      );
      expect(
        OrderTransferIntent.snapshot(DatabaseCore.orderBox!.get('source')!),
        before,
      );
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    },
  );

  test(
    'legacy missing Order and line UUID bytes stabilize before durable intent',
    () async {
      await fixture.seed(rich: true);
      await fixture.close();
      Hive.registerAdapter(Pos03LegacyOrderAdapter(), override: true);
      Hive.registerAdapter(Pos03LegacyItemAdapter(), override: true);
      Hive.init(root.path);
      final old = await Hive.openBox<Order>(DatabaseCore.orderBoxName);
      await old.put('source', fixture.originalSource!);
      await old.put('destination', fixture.originalDestination!);
      await old.flush();
      await Hive.close();
      Hive.registerAdapter(OrderAdapter(), override: true);
      Hive.registerAdapter(OrderItemAdapter(), override: true);
      await fixture.open(root.path);
      final ephemeral = DatabaseCore.orderBox!.get('source')!.orderUuid;
      final lineEphemeral = DatabaseCore.orderBox!
          .get('source')!
          .items
          .single
          .lineUuid;
      await fixture.close();
      await fixture.open(root.path);
      final source = DatabaseCore.orderBox!.get('source')!.clone();
      final destination = DatabaseCore.orderBox!.get('destination')!.clone();
      expect(source.orderUuid, isNot(ephemeral));
      expect(source.items.single.lineUuid, isNot(lineEphemeral));
      fixture.originalSource = source;
      fixture.originalDestination = destination;
      fixture.fault = (point, _) async {
        if (point == 'meta.put:transfer:intent:after')
          throw const FileSystemException('synthetic legacy interruption');
      };
      expect((await fixture.apply(quantity: 2)).ok, false);
      final plan = OrderTransferJournalRepository.read(pos03Id)!;
      final before = plan.request['sourceOrder'] as Map;
      expect(before['orderUuid'], source.orderUuid);
      expect(
        before['packageItems'][0]['lineUuid'],
        source.packageItems.single.lineUuid,
      );
      await fixture.close();
      await fixture.open(root.path);
      final saved = DatabaseCore.orderBox!.get('source')!;
      expect(saved.orderUuid, source.orderUuid);
      expect(saved.items.single.lineUuid, source.items.single.lineUuid);
      expect(
        saved.packageItems.single.lineUuid,
        source.packageItems.single.lineUuid,
      );
      expect(saved.packageItems.single.total, 7.11);
      expect(saved.advanceAmount, 1.17);
      expect(
        DatabaseCore.orderBox!.get('destination')!.orderUuid,
        destination.orderUuid,
      );
      expect(
        saved.items.single.quantity +
            DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        5,
      );
      expect(
        ((saved.items.single.total +
                    DatabaseCore.orderBox!
                        .get('destination')!
                        .items
                        .single
                        .total) *
                100)
            .round(),
        1251,
      );
      expect(OrderTransferJournalRepository.read(pos03Id)!.pending, false);
      expect(DatabaseCore.salesBox!.length, 1);
    },
  );
}
