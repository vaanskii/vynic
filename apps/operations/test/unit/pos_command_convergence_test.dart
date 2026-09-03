import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// The property that makes at-least-once delivery survivable.
///
/// Cloud hands a command over at least once and sometimes twice — a lease can
/// expire after the POS executed but before the acknowledgment landed. So every
/// command the queue accepts has to be safe to run again, and "safe" has to mean
/// something checkable rather than something asserted in a comment.
///
/// Each test below runs a command twice and asserts what the restaurant is left
/// holding: one reservation, one expense, one staff user, one order in the state
/// the payload asked for. The two commands that are not naturally convergent —
/// creating a reservation and recording an expense — are the ones where identity
/// had to move to Cloud, and those are checked first.
void main() {
  late Directory tempDir;

  void registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MenuCategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(MenuVariantDBAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(ReservationAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(SaleRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
  }

  const boxes = [
    'cv_settings',
    'cv_sales',
    'cv_expenses',
    'cv_audit',
    'cv_tables',
    'cv_orders',
    'cv_users',
    'cv_reservations',
  ];

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_command_convergence');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('cv_settings');
    DatabaseCore.salesBox = await Hive.openBox('cv_sales');
    DatabaseCore.expenseBox = await Hive.openBox('cv_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('cv_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('cv_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('cv_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('cv_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'cv_reservations',
    );
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-09-01T00:00:00.000',
    );
  });

  tearDown(() async {
    for (final name in boxes) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.expenseBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('reservation creation', () {
    // Cloud allocates a 16-digit numeric id; the POS mints 13-digit ones, so
    // the two can never collide.
    const reservationId = '1756900000000123';

    Map<String, dynamic> command() => <String, dynamic>{
      'reservationId': reservationId,
      'customerName': 'Nino',
      'customerPhone': '+995500000000',
      'tableNumbers': <int>[5],
      'reservationDate': '2026-09-10T00:00:00.000',
      'reservationTime': '19:30',
      'numberOfGuests': 4,
      'createdBy': 'website',
      'status': 'confirmed',
      'isTakeAway': false,
    };

    test('delivered twice, the restaurant has one booking', () async {
      final first = await PosCommandApplier.createReservation(command());
      final second = await PosCommandApplier.createReservation(command());

      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(second.code, 'already_exists');
      expect(ReservationRepository.getAllReservations(), hasLength(1));
    });

    test('the reservation carries the id Cloud gave it', () async {
      await PosCommandApplier.createReservation(command());
      final stored = ReservationRepository.getAllReservations().single;

      expect(stored.id, reservationId);
      expect(stored.customerName, 'Nino');
      // Cloud can link its own booking record immediately, without waiting for
      // the restaurant to answer — which is the point of moving the id here.
      expect(
        ReservationRepository.findReservationById(reservationId),
        isNotNull,
      );
    });

    test('a booking taken at the till still gets a local id', () async {
      final localId = await ReservationRepository.createReservation(
        customerName: 'Walk-in',
        customerPhone: '-',
        reservationDate: DateTime(2026, 9, 10),
        reservationTime: '20:00',
        numberOfGuests: 2,
        createdBy: 'waiter',
      );

      expect(localId, isNotEmpty);
      expect(localId, isNot(reservationId));
      expect(ReservationRepository.getAllReservations(), hasLength(1));
    });

    test('status and delete converge on the goal state', () async {
      await PosCommandApplier.createReservation(command());

      await PosCommandApplier.updateReservationStatus(<String, dynamic>{
        'reservationId': reservationId,
        'status': 'cancelled',
      });
      await PosCommandApplier.updateReservationStatus(<String, dynamic>{
        'reservationId': reservationId,
        'status': 'cancelled',
      });
      expect(
        ReservationRepository.findReservationById(reservationId)!.status,
        'cancelled',
      );

      final firstDelete = await PosCommandApplier.deleteReservation(
        <String, dynamic>{'reservationId': reservationId},
      );
      final secondDelete = await PosCommandApplier.deleteReservation(
        <String, dynamic>{'reservationId': reservationId},
      );
      // The goal state is "gone", which an absent reservation already satisfies.
      expect(firstDelete.ok, isTrue);
      expect(secondDelete.ok, isTrue);
      expect(ReservationRepository.getAllReservations(), isEmpty);
    });
  });

  group('expense recording', () {
    Map<String, dynamic> command({double amount = 42.5}) => <String, dynamic>{
      'id': 'expense-uuid-1',
      'description': 'Napkins',
      'amount': amount,
      'category': 'supplies',
      'paymentType': 'cash',
      'businessDate': '2026-09-01',
    };

    test('delivered twice, the day shows one expense', () async {
      await PosCommandApplier.createExpense(command());
      await PosCommandApplier.createExpense(command());

      final expenses = SalesRepository.getExpensesForDate('2026-09-01');
      expect(expenses, hasLength(1));
      expect(expenses.single['amount'], 42.5);
    });

    test(
      'a corrected amount replaces the record rather than adding one',
      () async {
        await PosCommandApplier.createExpense(command());
        await PosCommandApplier.createExpense(command(amount: 50));

        final expenses = SalesRepository.getExpensesForDate('2026-09-01');
        expect(expenses, hasLength(1));
        expect(expenses.single['amount'], 50.0);
      },
    );

    test('two different expenses are still two expenses', () async {
      await PosCommandApplier.createExpense(command());
      await PosCommandApplier.createExpense(<String, dynamic>{
        ...command(),
        'id': 'expense-uuid-2',
        'description': 'Cleaning',
      });

      expect(SalesRepository.getExpensesForDate('2026-09-01'), hasLength(2));
    });
  });

  group('staff', () {
    Map<String, dynamic> create() => <String, dynamic>{
      'username': 'nino',
      'pinCode': '4321',
      'role': 'waiter',
    };

    test('delivered twice, there is one user', () async {
      final first = await PosCommandApplier.createStaff(
        create(),
        treatExistingAsDone: true,
      );
      final second = await PosCommandApplier.createStaff(
        create(),
        treatExistingAsDone: true,
      );

      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(second.code, 'already_exists');
      expect(
        UserRepository.getAllUsers().where((u) => u.username == 'nino'),
        hasLength(1),
      );
    });

    test(
      'the LAN transport still reports the conflict it always did',
      () async {
        await PosCommandApplier.createStaff(create());
        // Without the reconciliation flag — which is how the legacy callback
        // server calls it — a duplicate is a 409, exactly as before.
        final second = await PosCommandApplier.createStaff(create());

        expect(second.ok, isFalse);
        expect(second.conflict, isTrue);
      },
    );

    test('a rename delivered twice leaves one renamed user', () async {
      await PosCommandApplier.createStaff(create(), treatExistingAsDone: true);

      final payload = <String, dynamic>{
        'oldUsername': 'nino',
        'newUsername': 'nino.k',
      };
      final first = await PosCommandApplier.renameStaff(
        payload,
        treatRenamedAsDone: true,
      );
      final second = await PosCommandApplier.renameStaff(
        payload,
        treatRenamedAsDone: true,
      );

      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(second.code, 'already_renamed');
      expect(UserRepository.getUserByUsername('nino'), isNull);
      expect(UserRepository.getUserByUsername('nino.k'), isNotNull);
    });

    test('a delete delivered twice is still just gone', () async {
      await PosCommandApplier.createStaff(create(), treatExistingAsDone: true);

      final first = await PosCommandApplier.deleteStaff(<String, dynamic>{
        'username': 'nino',
      }, treatMissingAsDone: true);
      final second = await PosCommandApplier.deleteStaff(<String, dynamic>{
        'username': 'nino',
      }, treatMissingAsDone: true);

      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(second.code, 'already_absent');
      expect(UserRepository.getUserByUsername('nino'), isNull);
    });

    test(
      'a PIN and a role are assignments, so repeating them changes nothing',
      () async {
        await PosCommandApplier.createStaff(
          create(),
          treatExistingAsDone: true,
        );

        for (var i = 0; i < 2; i++) {
          expect(
            (await PosCommandApplier.updateStaffPin(<String, dynamic>{
              'username': 'nino',
              'pinCode': '9876',
            })).ok,
            isTrue,
          );
          expect(
            (await PosCommandApplier.updateStaffRole(<String, dynamic>{
              'username': 'nino',
              'role': 'supervisor',
            })).ok,
            isTrue,
          );
        }

        final user = UserRepository.getUserByUsername('nino')!;
        expect(user.role.toLowerCase(), 'supervisor');
        expect(UserRepository.getAllUsers(), hasLength(1));
      },
    );
  });

  group('orders', () {
    test('a cancel delivered twice reports done, not missing', () async {
      // The order does not exist here at all, which is what a redelivery finds
      // after the first one removed it. A 404 would turn a duplicate into a
      // failure somebody has to go and re-issue by hand.
      final result = await PosCommandApplier.cancelOrder(<String, dynamic>{
        'posOrderId': 4242,
      }, treatMissingAsDone: true);

      expect(result.ok, isTrue);
      expect(result.code, 'already_absent');
    });

    test(
      'the LAN transport still reports a missing order as missing',
      () async {
        final result = await PosCommandApplier.cancelOrder(<String, dynamic>{
          'posOrderId': 4242,
        });

        expect(result.ok, isFalse);
        expect(result.notFound, isTrue);
        expect(result.httpStatus, 404);
      },
    );

    test('an update refuses an order it does not have', () async {
      final result = await PosCommandApplier.updateOrder(<String, dynamic>{
        'posOrderId': 4242,
        'items': <Map<String, dynamic>>[],
      });

      expect(result.ok, isFalse);
      expect(result.code, 'order_not_found');
    });
  });

  group('payload reading', () {
    test('accepts either the POS or the Manager spelling of an item', () {
      final items = PosCommandApplier.parseOrderItems(<Map<String, dynamic>>[
        {'itemName': 'Khachapuri', 'unitPrice': 12.0, 'quantity': 2},
        {'name': 'Wine', 'price': 20.0, 'quantity': 1},
      ]);

      expect(items, hasLength(2));
      expect(items[0].itemName, 'Khachapuri');
      expect(items[0].total, 24.0);
      expect(items[1].itemName, 'Wine');
      expect(items[1].unitPrice, 20.0);
    });

    test('a malformed payload is refused rather than half-applied', () async {
      final result = await PosCommandApplier.updateOrderStatus(
        <String, dynamic>{'posOrderId': 1},
      );

      expect(result.ok, isFalse);
      expect(result.badRequest, isTrue);
      expect(result.httpStatus, 400);
    });
  });
}
