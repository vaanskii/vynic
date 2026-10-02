import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/table.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import '../support/pos01_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Pos01Fixture fixture;
  late HttpOverrides? previous;
  setUp(() async {
    previous = HttpOverrides.current;
    directory = await Directory.systemTemp.createTemp('vynic-pos01-unit-');
    fixture = Pos01Fixture();
    await fixture.open(directory.path);
    await fixture.seed();
  });
  tearDown(() async {
    await fixture.close();
    HttpOverrides.global = previous;
    await directory.delete(recursive: true);
  });

  test('legacy store without journal keeps date/totals until close', () async {
    expect(CloseDayJournalRepository.read(), isNull);
    await CloseDayTransaction.recoverPending();
    expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    expect(
      DatabaseCore.settingsBox!.get('currentDate'),
      startsWith('2026-10-01'),
    );
    expect(await CloseDayTransaction.run(actorId: 'operator'), true);
    fixture.verify();
    final snapshot = jsonEncode(DatabaseCore.auditLogBox!.toMap());
    await CloseDayTransaction.recoverPending();
    expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), snapshot);
  });

  test(
    'fault before and after every real Hive write/flush boundary recovers once',
    () async {
      expect(await CloseDayTransaction.run(actorId: 'operator'), true);
      final checkpoints = List<String>.of(fixture.trace);
      expect(checkpoints.length, greaterThan(50));
      await fixture.close();
      for (var index = 0; index < checkpoints.length; index++) {
        final path = '${directory.path}/fault-$index';
        await Directory(path).create();
        await fixture.open(path);
        await fixture.seed();
        fixture.fault = (point, position) async {
          if (position == index + 1)
            throw FileSystemException('synthetic failure', point);
        };
        expect(
          await CloseDayTransaction.run(actorId: 'operator'),
          false,
          reason: 'boundary $index ${checkpoints[index]}',
        );
        final raw = DatabaseCore.metaBox!.get(CloseDayJournalRepository.key);
        final id = raw is Map ? raw['transitionId'] as String : null;
        final phase = raw is Map ? raw['phase'] : null;
        if (raw != null && phase != 'completed') {
          await expectLater(
            LocalDataAdmission.track(() async => true),
            throwsStateError,
          );
        }
        fixture.fault = null;
        await fixture.close();
        // DatabaseCore.open replays before Menu initialization/migrations.
        await fixture.open(path);
        if (id == null)
          expect(await CloseDayTransaction.run(actorId: 'operator'), true);
        fixture.verify(transitionId: id);
        await CloseDayTransaction.recoverPending();
        fixture.verify(transitionId: id);
        expect(
          await CloseDayTransaction.run(expectedBusinessDate: '2026-10-01'),
          false,
        );
        fixture.verify(transitionId: id);
        await fixture.close();
      }
      await fixture.open(directory.path);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'queued writer fails closed before gate releases on interrupted date write',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.fault = (point, _) async {
        if (point == 'settings.put:currentDate:after') {
          entered.complete();
          await release.future;
          throw const FileSystemException('synthetic interrupted date');
        }
      };
      final closing = CloseDayTransaction.run();
      await entered.future;
      var admitted = false;
      final writer = UpdateReadiness.track('test writer', () async {
        admitted = true;
      });
      final denied = expectLater(writer, throwsStateError);
      release.complete();
      expect(await closing, false);
      await denied;
      expect(admitted, false);
      expect(LocalDataAdmission.failure, contains('Close Day'));
      fixture.fault = null;
      await fixture.close();
      await fixture.open(directory.path);
      fixture.verify();
    },
  );

  for (final remote in [false, true]) {
    test(
      '${remote ? 'remote admitted command' : 'local dated request'} waits for Close Day and preserves retry ownership',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        fixture.fault = (point, _) async {
          if (point == 'meta.put:closeDayTransitionV1:intent:after') {
            entered.complete();
            await release.future;
          }
        };
        final closing = CloseDayTransaction.run();
        await entered.future;
        var done = false;
        final create = remote
            ? PosCommandApplier.upsertDineInOrder({
                'posOrderId': 8,
                'tableNumbers': ['4'],
                'floor': 'first',
                'waiterName': 'remote',
                'status': 'confirmed',
                'items': [
                  {
                    'itemKey': 'new',
                    'itemName': 'New',
                    'unitPrice': 5,
                    'quantity': 1,
                    'total': 5,
                  },
                ],
              }).then((_) {
                done = true;
              })
            : OrderRepository.createOrder(
                tableNumbers: ['4'],
                floor: 'first',
                createdBy: 'local',
                items: [
                  OrderItem(
                    itemKey: 'new',
                    itemName: 'New',
                    unitPrice: 5,
                    quantity: 1,
                    total: 5,
                  ),
                ],
                includeServiceFee: false,
              ).then(
                (_) {
                  done = true;
                },
                onError: (Object error) {
                  expect(
                    error,
                    isA<OrderMutationConflict>().having(
                      (v) => v.code,
                      'stale business date',
                      'stale_date',
                    ),
                  );
                  done = true;
                },
              );
        await Future<void>.delayed(Duration.zero);
        expect(done, false);
        release.complete();
        expect(await closing, true);
        await create;
        if (!remote) {
          expect(
            DatabaseCore.orderBox!.values.where(
              (o) => o.tableNumbers.contains('4'),
            ),
            isEmpty,
          );
          expect(DatabaseCore.tableBox!.get('free')!.activeOrderId, isNull);
          await OrderRepository.createOrder(
            tableNumbers: ['4'],
            floor: 'first',
            createdBy: 'local',
            items: [
              OrderItem(
                itemKey: 'new',
                itemName: 'New',
                unitPrice: 5,
                quantity: 1,
                total: 5,
              ),
            ],
            includeServiceFee: false,
          );
        }
        final order = DatabaseCore.orderBox!.values.singleWhere(
          (o) => o.tableNumbers.contains('4'),
        );
        expect(BusinessDayRepository.dateKey(order.createdAt), '2026-10-02');
        expect(
          DatabaseCore.tableBox!.get('free')!.activeOrderId,
          order.orderId,
        );
        await CloseDayTransaction.recoverPending();
        expect(
          DatabaseCore.orderBox!.values.where(
            (o) => o.orderId == order.orderId,
          ),
          hasLength(1),
        );
        expect(
          DatabaseCore.tableBox!.get('free')!.activeOrderId,
          order.orderId,
        );
      },
    );
  }

  test(
    'admitted settlement drains before Close Day checks and cleanup',
    () async {
      UpdateReadiness.enabled = true;
      UpdateReadiness.startupReady = true;
      final order = Order(
        orderId: 10,
        tableNumbers: ['4'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'payment',
            itemName: 'Payment',
            unitPrice: 7,
            quantity: 2,
            total: 14,
          ),
        ],
        totalAmount: 14,
        createdAt: DateTime.parse('2026-10-01'),
        createdBy: 'synthetic',
        status: 'confirmed',
        includeServiceFee: false,
      );
      await DatabaseCore.orderBox!.put('settling', order);
      await DatabaseCore.tableBox!.put(
        'free',
        TableModel(tableNumber: '4', floor: 'first')..reserve('synthetic', 10),
      );
      await OrderRepository.updateOrder(order);
      await AuditRepository.ensureAuditReport(
        orderId: order.orderId,
        orderSnapshot: order,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final settling = UpdateReadiness.track('settlement', () async {
        entered.complete();
        await release.future;
        return CloseTableTransaction.run(
          orderId: order.orderId,
          money: ClosureMoney.fromOrder(order, collectedNow: 14),
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 14},
          closedById: 'operator',
          isFiscal: true,
        );
      });
      await entered.future;
      final closing = CloseDayTransaction.run();
      expect(LocalDataAdmission.exclusiveOperation, 'closeDay');
      release.complete();
      final settled = await settling;
      final dayClosed = await closing;
      expect(
        settled.isSuccess,
        true,
        reason:
            '${settled.outcome.name}: ${settled.detail}; failure=${UpdateReadiness.failure}; sales=${DatabaseCore.salesBox!.length}',
      );
      expect(dayClosed, true, reason: CloseDayTransaction.lastFailureReason);
      expect(DatabaseCore.orderBox!.get('settling'), isNull);
      expect(DatabaseCore.orderBox!.get('closed'), isNull);
      expect(DatabaseCore.salesBox!.length, 2);
      expect(DatabaseCore.salesBox!.get('history')['totalAmount'], 70.0);
      expect(
        BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
        '2026-10-02',
      );
    },
  );

  test('already admitted create is a blocker, not a lost order', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final creating = UpdateReadiness.track('create', () async {
      entered.complete();
      await release.future;
      return OrderRepository.createOrder(
        tableNumbers: ['4'],
        floor: 'first',
        createdBy: 'local',
        items: [],
        includeServiceFee: false,
      );
    });
    await entered.future;
    final closing = CloseDayTransaction.run();
    release.complete();
    final order = await creating;
    expect(await closing, false);
    expect(BusinessDayRepository.dateKey(order.createdAt), '2026-10-01');
    expect(DatabaseCore.tableBox!.get('free')!.activeOrderId, order.orderId);
    expect(CloseDayJournalRepository.read(), isNull);
  });

  test(
    'a concurrent duplicate close cannot poison the successful owner',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.fault = (point, _) async {
        if (point == 'meta.put:closeDayTransitionV1:intent:after') {
          entered.complete();
          await release.future;
        }
      };
      final owner = CloseDayTransaction.run();
      await entered.future;
      final duplicate = await CloseDayTransaction.run();
      expect(duplicate, false);
      expect(LocalDataAdmission.failure, isNull);
      var admitted = false;
      final writer = UpdateReadiness.track('queued', () async {
        admitted = true;
      });
      release.complete();
      expect(await owner, true);
      await writer;
      expect(admitted, true);
      fixture.verify();
    },
  );

  test('Order model helper waits before in-memory mutation', () async {
    final order = DatabaseCore.orderBox!.get('older-active')!;
    await DatabaseCore.tableBox!.put(
      'older-owned',
      TableModel(tableNumber: '3', floor: 'first')..reserve('synthetic', 3),
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final exclusive = LocalDataAdmission.exclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final change = order.setManualAdjustment(5);
    expect(order.manualAdjustmentAmount, 0);
    release.complete();
    await exclusive;
    await change;
    expect(order.manualAdjustmentAmount, 5);
  });

  test('waiter rechecks a second exclusive before entering', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = LocalDataAdmission.exclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var admitted = false;
    final secondEntered = Completer<void>();
    final secondRelease = Completer<void>();
    final second = first.then(
      (_) => LocalDataAdmission.exclusive(() async {
        secondEntered.complete();
        await secondRelease.future;
      }),
    );
    final write = LocalDataAdmission.track(() async {
      admitted = true;
    });
    release.complete();
    await secondEntered.future;
    expect(admitted, false);
    secondRelease.complete();
    await second;
    await write;
    expect(admitted, true);
  });

  test(
    'calendar successor preserves UTC/time and crosses month/year boundaries',
    () {
      final date = DateTime.utc(2026, 12, 31, 15, 40, 10);
      expect(
        BusinessDayRepository.nextCalendarDate(date),
        DateTime.utc(2027, 1, 1, 15, 40, 10),
      );
      expect(
        BusinessDayRepository.nextCalendarDate(DateTime(2026, 10, 31, 23, 50)),
        DateTime(2026, 11, 1, 23, 50),
      );
    },
  );
}
