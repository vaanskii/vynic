import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos03Fixture fixture;
  late HttpOverrides? previous;
  setUp(() async {
    previous = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos03-unit-');
    fixture = Pos03Fixture();
    await fixture.open(root.path);
    await fixture.seed();
  });
  tearDown(() async {
    AuditRepository.registerAuditChangedCallback(() {});
    await fixture.close();
    HttpOverrides.global = previous;
    await root.delete(recursive: true);
  });

  test(
    'post-commit notification failure cannot change durable success',
    () async {
      AuditRepository.registerAuditChangedCallback(
        () => throw StateError('synthetic notification fault'),
      );
      expect((await fixture.apply()).ok, true);
      fixture.verify();
      expect(LocalDataAdmission.failure, isNull);
    },
  );

  test(
    'every put/flush boundary recovers quantity, frozen value and exact audits',
    () async {
      expect((await fixture.apply()).ok, true);
      fixture.verify();
      final boundaries = List<String>.of(fixture.trace);
      expect(
        boundaries.where((v) => v.contains('destinationWritten')),
        isNotEmpty,
      );
      expect(boundaries.where((v) => v.contains('sourceClosed')), isNotEmpty);
      for (var position = 1; position <= boundaries.length; position++) {
        await fixture.close();
        final path = '${root.path}/boundary-$position';
        await Directory(path).create();
        await fixture.open(path);
        await fixture.seed();
        fixture.fault = (point, count) async {
          if (count == position) {
            expect(point, boundaries[position - 1]);
            throw const FileSystemException('synthetic boundary failure');
          }
        };
        expect(
          (await fixture.apply()).ok,
          false,
          reason: '$position ${boundaries[position - 1]}',
        );
        await fixture.close();
        await fixture.open(path);
        if (OrderTransferJournalRepository.read(pos03Id) == null) {
          expect((await fixture.apply()).ok, true);
        }
        fixture.verify();
        final audits = jsonEncode(DatabaseCore.auditLogBox!.toMap());
        await OrderItemTransfer.recoverPending();
        expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), audits);
        expect((await fixture.apply()).ok, true);
        fixture.verify();
      }
    },
  );

  test(
    'queued stale Hive model is refused without undoing committed items',
    () async {
      final cached = DatabaseCore.orderBox!.get('source')!;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.fault = (point, _) async {
        if (point == 'meta.put:transfer:intent:after') {
          entered.complete();
          await release.future;
        }
      };
      final owner = fixture.apply(quantity: 2);
      await entered.future;
      final adjustment = cached.setManualAdjustment(0.11);
      final refused = expectLater(
        adjustment,
        throwsA(
          isA<HiveError>().having(
            (v) => v.message,
            'stale handle reason',
            contains('not in a box'),
          ),
        ),
      );
      release.complete();
      expect((await owner).ok, true);
      await refused;
      final source = DatabaseCore.orderBox!.get('source')!;
      final destination = DatabaseCore.orderBox!.get('destination')!;
      expect(
        source.items.single.quantity + destination.items.single.quantity,
        5,
      );
      expect(
        ((source.items.single.total + destination.items.single.total) * 100)
            .round(),
        1251,
      );
      expect(source.manualAdjustmentAmount, 0.0);
      expect(LocalDataAdmission.failure, isNull);
      expect(OrderTransferJournalRepository.read(pos03Id)!.pending, false);
    },
  );

  test('pending failure latches before queued writers can enter', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.fault = (point, _) async {
      if (point == 'orders.put:destination:after' &&
          OrderTransferJournalRepository.read(pos03Id) != null) {
        entered.complete();
        await release.future;
        throw const FileSystemException('synthetic destination fault');
      }
    };
    final owner = fixture.apply();
    await entered.future;
    var wrote = false;
    final writer = UpdateReadiness.track('queued', () async {
      wrote = true;
    });
    final rejection = expectLater(writer, throwsStateError);
    expect(LocalDataAdmission.exclusiveOperation, 'transferItems');
    release.complete();
    expect((await owner).error, OrderTransferError.recoveryRequired);
    await rejection;
    expect(wrote, false);
    expect(LocalDataAdmission.failure, isNotNull);
  });

  test(
    'duplicate transfer, Close Day and backup cannot poison exclusive owner',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.fault = (point, _) async {
        if (point == 'meta.put:transfer:intent:after') {
          entered.complete();
          await release.future;
        }
      };
      final owner = fixture.apply();
      await entered.future;
      expect((await fixture.apply()).error, OrderTransferError.busy);
      expect(await CloseDayTransaction.run(), false);
      await expectLater(
        BackupRepository.createDataBackup(
          targetFilePath: '${root.path}/blocked.json',
        ),
        throwsStateError,
      );
      expect(LocalDataAdmission.failure, isNull);
      var wrote = false;
      final writer = UpdateReadiness.track('queued', () async {
        wrote = true;
      });
      expect(wrote, false);
      release.complete();
      expect((await owner).ok, true);
      await writer;
      expect(wrote, true);
      fixture.verify();
    },
  );

  test(
    'already admitted source edit drains then immutable selection is refused',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final writer = UpdateReadiness.track('prior', () async {
        entered.complete();
        await release.future;
        final row = DatabaseCore.orderBox!.get('source')!.clone();
        row.items.single.quantity = 6;
        row.items.single.total = 15.01;
        await DatabaseCore.orderBox!.put('source', row);
      });
      await entered.future;
      final transfer = fixture.apply();
      release.complete();
      await writer;
      expect((await transfer).error, OrderTransferError.staleSource);
      expect(OrderTransferJournalRepository.read(pos03Id), isNull);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        1,
      );
    },
  );

  test(
    'completed stable ID retry retains original date and never overwrites later edits',
    () async {
      expect((await fixture.apply()).ok, true);
      final row = DatabaseCore.orderBox!.get('destination')!.clone();
      row.items.single.quantity = 9;
      row.items.single.total = 22.51;
      await DatabaseCore.orderBox!.put('destination', row);
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-10-02T00:00:00.000',
      );
      final before = OrderTransferIntent.snapshot(row);
      final audits = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      expect((await fixture.apply()).ok, true);
      expect(
        OrderTransferIntent.snapshot(
          DatabaseCore.orderBox!.get('destination')!,
        ),
        before,
      );
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), audits);
      expect(
        (await fixture.apply(quantity: 1)).error,
        OrderTransferError.transferIdConflict,
      );
      await OrderItemTransfer.recoverPending();
      expect(
        OrderTransferIntent.snapshot(
          DatabaseCore.orderBox!.get('destination')!,
        ),
        before,
      );
    },
  );

  test('stale business date and UUID reject before intent', () async {
    expect(
      (await fixture.apply(expectedBusinessDate: '2026-09-30')).error,
      OrderTransferError.businessDateChanged,
    );
    final row = DatabaseCore.orderBox!.get('source')!.clone()
      ..orderUuid = 'replacement-identity';
    await DatabaseCore.orderBox!.put('source', row);
    expect((await fixture.apply()).error, OrderTransferError.identityConflict);
    expect(OrderTransferJournalRepository.read(pos03Id), isNull);
  });

  test(
    'locked report is an explicit refusal before any transfer write',
    () async {
      await AuditRepository.ensureAuditReport(
        orderId: 1,
        orderSnapshot: fixture.originalSource!,
      );
      final key = AuditRepository.buildAuditReportKey(1);
      final report = AuditReport.fromMap(
        DatabaseCore.auditLogBox!.get(key) as Map,
      );
      await DatabaseCore.auditLogBox!.put(
        key,
        report.copyWith(locked: true).toMap(),
      );
      expect((await fixture.apply()).error, OrderTransferError.auditLocked);
      expect(OrderTransferJournalRepository.read(pos03Id), isNull);
      expect(DatabaseCore.orderBox!.get('source')!.items.single.quantity, 4);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        1,
      );
    },
  );

  test(
    'unrelated table owner is refused; virtual Takeaway is never released',
    () async {
      DatabaseCore.tableBox!.get('source-table')!.activeOrderId = 99;
      expect((await fixture.apply()).error, OrderTransferError.tableOwnership);
      expect(OrderTransferJournalRepository.read(pos03Id), isNull);
      await fixture.close();
      final path = '${root.path}/takeaway';
      await Directory(path).create();
      await fixture.open(path);
      await fixture.seed(takeaway: true);
      expect((await fixture.apply()).ok, true);
      fixture.verify(takeaway: true);
    },
  );

  test(
    'partial transfer preserves lossless package, advance and guest fields on restart',
    () async {
      await fixture.seed(rich: true);
      final before = OrderTransferIntent.snapshot(fixture.originalSource!);
      expect((await fixture.apply(quantity: 2)).ok, true);
      await fixture.close();
      await fixture.open(root.path);
      final source = DatabaseCore.orderBox!.get('source')!;
      final after = OrderTransferIntent.snapshot(source);
      for (final field in ['items', 'totalAmount', 'updatedAt']) {
        before.remove(field);
        after.remove(field);
      }
      expect(after, before);
      expect(source.items.single.total, 5.01);
      expect(source.items.single.quantity, 2);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.total,
        7.50,
      );
      expect(
        DatabaseCore.reservationBox!.get('booking')!.status,
        'in-progress',
      );
      expect(DatabaseCore.tableBox!.get('source-table')!.activeOrderId, 1);
      expect(DatabaseCore.salesBox!.length, 1);
    },
  );

  test(
    'pending identity conflict and damaged journal fail closed on startup',
    () async {
      fixture.fault = (point, _) async {
        if (point == 'meta.put:transfer:intent:after')
          throw const FileSystemException('synthetic intent fault');
      };
      expect((await fixture.apply()).ok, false);
      await fixture.close();
      // Only a raw, test-owned storage mutation simulates external corruption.
      Hive.init(root.path);
      final raw = await Hive.openBox<Order>(DatabaseCore.orderBoxName);
      final swapped = raw.get('source')!.clone()..orderUuid = 'unrelated-order';
      await raw.put('source', swapped);
      await raw.flush();
      await Hive.close();
      await expectLater(fixture.open(root.path), throwsStateError);
      expect(LocalDataAdmission.failure, contains('persisted image disagrees'));
      await expectLater(
        LocalDataAdmission.track(() async {}),
        throwsStateError,
      );
      await fixture.close();
      await Directory('${root.path}/bad').create();
      await fixture.open('${root.path}/bad');
      await fixture.seed();
      await DatabaseCore.metaBox!.put(
        OrderTransferJournalRepository.key(pos03Id),
        {'version': 99},
      );
      await DatabaseCore.metaBox!.flush();
      await fixture.close();
      await expectLater(
        fixture.open('${root.path}/bad'),
        throwsFormatException,
      );
      expect(
        LocalDataAdmission.failure,
        contains('Order transfer recovery failed'),
      );
      await expectLater(
        LocalDataAdmission.track(() async {}),
        throwsStateError,
      );
    },
  );

  test(
    'self-consistent digest cannot excuse request/before image substitution',
    () async {
      expect((await fixture.apply()).ok, true);
      final value = OrderTransferJournalRepository.read(pos03Id)!.data;
      final changed = OrderTransferIntent.cloneMap(value)..remove('sha256');
      changed['request']['sourceOrder']['customerName'] =
          'Different immutable payload';
      changed['fingerprint'] = PosBackupFormat.digest(changed['request']);
      expect(
        () => OrderTransferIntent.fromMap(OrderTransferIntent(changed).toMap()),
        throwsA(
          isA<FormatException>().having(
            (v) => v.message,
            'reason',
            contains('request/before'),
          ),
        ),
      );
    },
  );

  test(
    'legacy empty cleanup shares durable coordinator and remains idempotent',
    () async {
      final order = DatabaseCore.orderBox!.get('source')!.clone()
        ..items = <OrderItem>[];
      order.recalculateTotal();
      await DatabaseCore.orderBox!.put('source', order);
      await OrderItemTransfer.releaseEmptiedOrder(
        order,
        user: pos03User,
        transferId: pos03Id,
      );
      final report = AuditReport.fromMap(
        DatabaseCore.auditLogBox!.get(AuditRepository.buildAuditReportKey(1))
            as Map,
      );
      expect(report.events.map((e) => e.type), [AuditEventType.transferClose]);
      expect(report.locked, true);
      await OrderItemTransfer.releaseEmptiedOrder(order, user: pos03User);
      expect(
        AuditReport.fromMap(
          DatabaseCore.auditLogBox!.get(report.reportId) as Map,
        ).events,
        hasLength(1),
      );
      expect(DatabaseCore.salesBox!.length, 1);
    },
  );
}
