import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/database/transactions/activate_reservation_transaction.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// Phase 3: a booking has a timeline of its own. Every path that touches
/// one — POS, Admin, Manager and website commands, Close Day, the Order it
/// becomes — writes the same shape of entry, and a redelivery writes nothing.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-04';

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
    'ra_settings',
    'ra_sales',
    'ra_expenses',
    'ra_audit',
    'ra_tables',
    'ra_orders',
    'ra_users',
    'ra_reservations',
    'ra_journal',
  ];

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_reservation_audit');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('ra_settings');
    DatabaseCore.salesBox = await Hive.openBox('ra_sales');
    DatabaseCore.expenseBox = await Hive.openBox('ra_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('ra_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('ra_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('ra_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('ra_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'ra_reservations',
    );
    DatabaseCore.closureJournalBox = await Hive.openBox('ra_journal');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '${businessDate}T00:00:00.000',
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
    DatabaseCore.closureJournalBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  /// The Reservation timeline as written to the append-only log.
  List<Map<String, dynamic>> timeline({String? action, String? reservationId}) {
    final entries = <Map<String, dynamic>>[];
    for (final raw in DatabaseCore.auditLogBox!.values) {
      if (raw is! Map || raw['action'] == null) continue;
      final normalized = ReservationAuditAction.normalize(
        raw['action']?.toString(),
      );
      if (normalized == null) continue;
      if (action != null && normalized != action) continue;
      final data = raw['data'] is String
          ? Map<String, dynamic>.from(jsonDecode(raw['data'] as String) as Map)
          : Map<String, dynamic>.from(raw['data'] as Map);
      if (reservationId != null && data['reservationId'] != reservationId) {
        continue;
      }
      entries.add({
        'action': normalized,
        'userId': raw['userId'],
        '_createdAt': raw['createdAt']?.toString() ?? '',
        ...data,
      });
    }
    // The box iterates by uuid key; the timeline is read in the order it
    // was written.
    entries.sort(
      (a, b) =>
          (a['_createdAt'] as String).compareTo(b['_createdAt'] as String),
    );
    return entries;
  }

  Future<void> seedTable(String number, {String floor = 'first'}) =>
      DatabaseCore.tableBox!.put(
        '$floor-$number',
        TableModel(tableNumber: number, floor: floor),
      );

  OrderItem line(
    String name,
    double price,
    int qty, {
    String? menuItemId,
    String? variantId,
  }) => OrderItem(
    itemKey: name,
    itemName: name,
    unitPrice: price,
    quantity: qty,
    total: price * qty,
    menuItemId: menuItemId,
    variantId: variantId,
  );

  Future<String> createPosBooking({
    String status = 'confirmed',
    List<TableRef>? tables,
    List<OrderItem>? preOrder,
    String createdBy = 'Giorgi',
  }) => ReservationRepository.createReservation(
    customerName: 'ნინო გ.',
    customerPhone: '+995555000000',
    tableRefs: tables ?? const [TableRef(floor: 'first', tableNumber: '5')],
    reservationDate: DateTime.parse('${businessDate}T00:00:00'),
    reservationTime: '19:00',
    numberOfGuests: 4,
    createdBy: createdBy,
    status: status,
    preOrderItems: preOrder,
  );

  void expectEntry(
    Map<String, dynamic> entry, {
    required String action,
    required String source,
    required String actor,
    String? previousStatus,
    String? newStatus,
  }) {
    expect(entry['action'], action);
    expect(entry['source'], source);
    expect(entry['actorId'], actor);
    expect(entry['userId'], actor);
    expect(entry['businessDate'], businessDate);
    if (previousStatus != null) {
      expect(entry['previousStatus'], previousStatus);
    }
    if (newStatus != null) expect(entry['newStatus'], newStatus);
    expect(entry.keys.map((k) => k.toLowerCase()), isNot(contains('pin')));
  }

  group('create', () {
    test(
      'POS booking writes CREATE_RESERVATION with the booking fields',
      () async {
        final id = await createPosBooking();

        final entries = timeline(reservationId: id);
        expect(entries, hasLength(1));
        final created = entries.single;
        expectEntry(
          created,
          action: ReservationAuditAction.create,
          source: 'POS',
          actor: 'Giorgi',
          newStatus: 'confirmed',
        );
        expect(created['customerName'], 'ნინო გ.');
        expect(created['customerPhone'], '+995555000000');
        expect(created['date'], businessDate);
        expect(created['time'], '19:00');
        expect(created['guestCount'], 4);
        expect(created['tableRefs'], ['first/5']);
      },
    );

    test(
      'Manager command is source MANAGER and a redelivery writes once',
      () async {
        final payload = <String, dynamic>{
          'reservationId': 'res-m1',
          'customerName': 'Guest',
          'customerPhone': '555',
          'tableNumbers': <int>[5],
          'reservationDate': '${businessDate}T00:00:00',
          'reservationTime': '20:00',
          'numberOfGuests': 2,
          'createdBy': 'Nino',
          'status': 'confirmed',
        };

        final first = await PosCommandApplier.createReservation(payload);
        final second = await PosCommandApplier.createReservation(payload);

        expect(first.ok, isTrue);
        expect(second.code, 'already_exists');
        expect(DatabaseCore.reservationBox!.values, hasLength(1));
        final entries = timeline(reservationId: 'res-m1');
        expect(entries, hasLength(1));
        expectEntry(
          entries.single,
          action: ReservationAuditAction.create,
          source: 'MANAGER',
          actor: 'Nino',
          newStatus: 'confirmed',
        );
      },
    );

    test('website bridge command is source WEBSITE', () async {
      final result = await PosCommandApplier.createReservation(
        <String, dynamic>{
          'reservationId': 'res-w1',
          'customerName': 'Website Guest',
          'customerPhone': '-',
          'tableNumbers': <int>[5],
          'reservationDate': '${businessDate}T00:00:00',
          'reservationTime': '21:00',
          'numberOfGuests': 2,
          'createdBy': 'website',
          'status': 'confirmed',
          'source': 'website',
        },
      );

      expect(result.ok, isTrue);
      expectEntry(
        timeline(reservationId: 'res-w1').single,
        action: ReservationAuditAction.create,
        source: 'WEBSITE',
        actor: 'website',
        newStatus: 'confirmed',
      );
    });
  });

  group('update and confirm', () {
    test(
      'a details edit names the fields that changed, and only once',
      () async {
        final id = await createPosBooking();

        final changed = await ReservationRepository.updateReservationDetails(
          id,
          numberOfGuests: 6,
          customerPhone: '+995555111111',
          actorId: 'Giorgi',
        );
        final unchanged = await ReservationRepository.updateReservationDetails(
          id,
          numberOfGuests: 6,
          actorId: 'Giorgi',
        );

        expect(changed, isTrue);
        expect(unchanged, isFalse);
        final updates = timeline(
          action: ReservationAuditAction.update,
          reservationId: id,
        );
        expect(updates, hasLength(1));
        final update = updates.single;
        expectEntry(
          update,
          action: ReservationAuditAction.update,
          source: 'POS',
          actor: 'Giorgi',
        );
        expect(update['changedFields'], ['customerPhone', 'guestCount']);
        expect(update['previousValues'], {
          'customerPhone': '+995555000000',
          'guestCount': 4,
        });
        expect(update['newValues'], {
          'customerPhone': '+995555111111',
          'guestCount': 6,
        });
      },
    );

    test(
      'a pre-order change is one UPDATE; the same items again are none',
      () async {
        final id = await createPosBooking();
        final items = [line('საფერავი', 42.0, 1)];

        await ReservationRepository.updateReservationPreOrderItems(
          id,
          items,
          actorId: 'Giorgi',
        );
        await ReservationRepository.updateReservationPreOrderItems(
          id,
          items,
          actorId: 'Giorgi',
        );

        final updates = timeline(
          action: ReservationAuditAction.update,
          reservationId: id,
        );
        expect(updates, hasLength(1));
        expect(updates.single['changedFields'], ['preOrderItems']);
        expect((updates.single['newValues'] as Map)['preOrderItems'], [
          {'itemName': 'საფერავი', 'quantity': 1, 'unitPrice': 42.0},
        ]);
      },
    );

    test('assigning tables to a pending booking is its confirmation', () async {
      final id = await createPosBooking(status: 'pending', tables: const []);

      await ReservationRepository.updateReservationTables(
        id,
        const [],
        tableRefs: const [TableRef(floor: 'first', tableNumber: '7')],
        actorId: 'Giorgi',
      );

      final confirmations = timeline(
        action: ReservationAuditAction.confirm,
        reservationId: id,
      );
      expect(confirmations, hasLength(1));
      expectEntry(
        confirmations.single,
        action: ReservationAuditAction.confirm,
        source: 'POS',
        actor: 'Giorgi',
        previousStatus: 'pending',
        newStatus: 'confirmed',
      );
      expect(confirmations.single['newValues'], {
        'tableRefs': ['first/7'],
      });
    });

    test(
      'a status confirmation is CONFIRM_RESERVATION, delivered once',
      () async {
        final id = await createPosBooking(status: 'pending');

        await ReservationRepository.updateReservationStatus(
          id,
          'confirmed',
          actorId: 'Giorgi',
        );
        await ReservationRepository.updateReservationStatus(
          id,
          'confirmed',
          actorId: 'Giorgi',
        );

        final entries = timeline(reservationId: id);
        expect(entries.map((e) => e['action']), [
          ReservationAuditAction.create,
          ReservationAuditAction.confirm,
        ]);
        expectEntry(
          entries.last,
          action: ReservationAuditAction.confirm,
          source: 'POS',
          actor: 'Giorgi',
          previousStatus: 'pending',
          newStatus: 'confirmed',
        );
      },
    );
  });

  group('activation and close linkage', () {
    test(
      'seating writes the status move and the Order names the booking',
      () async {
        await seedTable('5');
        final id = await createPosBooking(
          preOrder: [
            line(
              'საფერავი',
              42.0,
              1,
              menuItemId: 'menu-saperavi',
              variantId: 'variant-bottle',
            ),
          ],
        );

        final first = await ActivateReservationTransaction.activate(
          reservationId: id,
          activatedBy: 'Giorgi',
        );
        final again = await ActivateReservationTransaction.activate(
          reservationId: id,
          activatedBy: 'Giorgi',
        );

        expect(first.isSuccess, isTrue);
        expect(again.orderId, first.orderId);
        final activatedOrder = DatabaseCore.orderBox!.values.firstWhere(
          (order) => order.orderId == first.orderId,
        );
        expect(activatedOrder.items.single.menuItemId, 'menu-saperavi');
        expect(activatedOrder.items.single.variantId, 'variant-bottle');
        final updates = timeline(
          action: ReservationAuditAction.update,
          reservationId: id,
        );
        expect(updates, hasLength(1));
        expectEntry(
          updates.single,
          action: ReservationAuditAction.update,
          source: 'POS',
          actor: 'Giorgi',
          previousStatus: 'confirmed',
          newStatus: 'in-progress',
        );
        expect(updates.single['orderId'], first.orderId);
        expect(updates.single['reason'], 'Activated');

        final report = AuditRepository.getAuditReport(first.orderId!)!;
        expect(report.events.first.type, AuditEventType.activateReservation);
        expect(report.events.first.details, containsPair('reservationId', id));
      },
    );

    test('CREATE → CONFIRM → ACTIVATE → CLOSE with reservationId', () async {
      await seedTable('5');
      final id = await createPosBooking(
        status: 'pending',
        preOrder: [line('საფერავი', 42.0, 1)],
      );
      await ReservationRepository.updateReservationStatus(
        id,
        'confirmed',
        actorId: 'Giorgi',
      );
      final activation = await ActivateReservationTransaction.activate(
        reservationId: id,
        activatedBy: 'Giorgi',
      );
      final orderId = activation.orderId!;
      final order = DatabaseCore.orderBox!.values.firstWhere(
        (o) => o.orderId == orderId,
      );

      final result = await CloseTableTransaction.run(
        orderId: orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: order.totalAmount),
        paymentMethod: 'cash',
        tenderBreakdown: {'cash': order.totalAmount},
        closedById: 'Giorgi',
        isFiscal: true,
      );
      expect(result.outcome, ClosureOutcome.closed);

      final report = AuditRepository.getAuditReport(orderId)!;
      final closeEvent = report.events.last;
      expect(closeEvent.type, AuditEventType.close);
      expect(closeEvent.details, containsPair('reservationId', id));
      expect(closeEvent.details, containsPair('paymentMethod', 'cash'));

      final entries = timeline(reservationId: id);
      expect(entries.map((e) => e['action']), [
        ReservationAuditAction.create,
        ReservationAuditAction.confirm,
        ReservationAuditAction.update,
        ReservationAuditAction.complete,
      ]);
      expectEntry(
        entries.last,
        action: ReservationAuditAction.complete,
        source: 'POS',
        actor: 'Giorgi',
        previousStatus: 'in-progress',
        newStatus: 'completed',
      );
      expect(entries.last['orderId'], orderId);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
    });
  });

  group('cancel', () {
    test(
      'Admin panel cancel is CANCEL_RESERVATION source POS with reason',
      () async {
        final id = await createPosBooking();

        await ReservationRepository.updateReservationStatus(
          id,
          'cancelled',
          actorId: 'Giorgi',
          source: AuditSource.pos,
          reason: 'Reservation cancelled via Admin panel',
        );

        final cancels = timeline(
          action: ReservationAuditAction.cancel,
          reservationId: id,
        );
        expect(cancels, hasLength(1));
        expectEntry(
          cancels.single,
          action: ReservationAuditAction.cancel,
          source: 'POS',
          actor: 'Giorgi',
          previousStatus: 'confirmed',
          newStatus: 'cancelled',
        );
        expect(
          cancels.single['reason'],
          'Reservation cancelled via Admin panel',
        );
        // No lowercase legacy row is written any more.
        expect(
          DatabaseCore.auditLogBox!.values.where(
            (raw) => raw is Map && raw['action'] == 'reservation_cancelled',
          ),
          isEmpty,
        );
      },
    );

    test(
      'Manager cancel is source MANAGER and a redelivery writes once',
      () async {
        final id = await createPosBooking();
        final payload = <String, dynamic>{
          'reservationId': id,
          'status': 'cancelled',
        };

        expect(
          (await PosCommandApplier.updateReservationStatus(payload)).ok,
          isTrue,
        );
        expect(
          (await PosCommandApplier.updateReservationStatus(payload)).ok,
          isTrue,
        );

        final cancels = timeline(
          action: ReservationAuditAction.cancel,
          reservationId: id,
        );
        expect(cancels, hasLength(1));
        expectEntry(
          cancels.single,
          action: ReservationAuditAction.cancel,
          source: 'MANAGER',
          actor: PosCommandApplier.defaultActor,
          previousStatus: 'confirmed',
          newStatus: 'cancelled',
        );
      },
    );

    test('website cancel is source WEBSITE', () async {
      final id = await createPosBooking();

      await PosCommandApplier.updateReservationStatus(<String, dynamic>{
        'reservationId': id,
        'status': 'cancelled',
        'updatedBy': 'website',
        'source': 'website',
        'reason': 'Cancelled on the website',
      });

      final cancel = timeline(
        action: ReservationAuditAction.cancel,
        reservationId: id,
      ).single;
      expectEntry(
        cancel,
        action: ReservationAuditAction.cancel,
        source: 'WEBSITE',
        actor: 'website',
        previousStatus: 'confirmed',
        newStatus: 'cancelled',
      );
      expect(cancel['reason'], 'Cancelled on the website');
    });

    test(
      'cancelling the seated Order cancels the booking with the reason',
      () async {
        await seedTable('5');
        final id = await createPosBooking(
          preOrder: [line('საფერავი', 42.0, 1)],
        );
        final activation = await ActivateReservationTransaction.activate(
          reservationId: id,
          activatedBy: 'Giorgi',
        );

        final outcome = await CancelOrderTransaction.run(
          orderId: activation.orderId!,
          actorId: 'Giorgi',
          source: AuditSource.pos,
          reason: 'Guest left',
          approvedBy: 'Manager',
        );
        expect(outcome, CancelOrderOutcome.cancelled);

        final cancel = timeline(
          action: ReservationAuditAction.cancel,
          reservationId: id,
        ).single;
        expectEntry(
          cancel,
          action: ReservationAuditAction.cancel,
          source: 'POS',
          actor: 'Giorgi',
          previousStatus: 'in-progress',
          newStatus: 'cancelled',
        );
        expect(cancel['orderId'], activation.orderId);
        expect(cancel['reason'], 'Guest left');

        // The Order side stores the approver structurally, not only in a note.
        final cancelEvent = AuditRepository.getAuditReport(
          activation.orderId!,
        )!.events.last;
        expect(cancelEvent.type, AuditEventType.cancelTable);
        expect(cancelEvent.details, containsPair('approvedById', 'Manager'));
        expect(cancelEvent.details, containsPair('approvedByName', 'Manager'));
        expect(cancelEvent.details, containsPair('reason', 'Guest left'));
      },
    );
  });

  group('Close Day', () {
    test(
      'an unseated booking is NO_SHOW, a seated one COMPLETE, by the system',
      () async {
        final unseated = await createPosBooking();
        final seated = await createPosBooking(
          tables: const [TableRef(floor: 'first', tableNumber: '9')],
        );
        final seatedBooking = ReservationRepository.findReservationById(
          seated,
        )!;
        seatedBooking.status = 'in-progress';
        seatedBooking.linkedOrderId = 77;
        await seatedBooking.save();

        final first = await CloseDayTransaction.finalizeReservationsForDay(
          businessDate,
        );
        final second = await CloseDayTransaction.finalizeReservationsForDay(
          businessDate,
        );

        expect(first, (completed: 1, noShow: 1));
        expect(second, (completed: 0, noShow: 0));

        final noShow = timeline(
          action: ReservationAuditAction.noShow,
          reservationId: unseated,
        ).single;
        expectEntry(
          noShow,
          action: ReservationAuditAction.noShow,
          source: 'SYSTEM',
          actor: 'system',
          previousStatus: 'confirmed',
          newStatus: 'no-show',
        );
        expect(noShow['reason'], 'Close Day');

        final completed = timeline(
          action: ReservationAuditAction.complete,
          reservationId: seated,
        ).single;
        expectEntry(
          completed,
          action: ReservationAuditAction.complete,
          source: 'SYSTEM',
          actor: 'system',
          previousStatus: 'in-progress',
          newStatus: 'completed',
        );
        expect(completed['orderId'], 77);
        expect(timeline(reservationId: unseated), hasLength(2));
        expect(timeline(reservationId: seated), hasLength(2));
      },
    );
  });

  group('delete', () {
    test('the row goes; its last snapshot stays in the timeline', () async {
      final id = await createPosBooking();

      await ReservationRepository.deleteReservation(id, actorId: 'Giorgi');
      await ReservationRepository.deleteReservation(id, actorId: 'Giorgi');

      expect(ReservationRepository.findReservationById(id), isNull);
      final deletes = timeline(
        action: ReservationAuditAction.delete,
        reservationId: id,
      );
      expect(deletes, hasLength(1));
      expectEntry(
        deletes.single,
        action: ReservationAuditAction.delete,
        source: 'POS',
        actor: 'Giorgi',
        previousStatus: 'confirmed',
      );
      expect(deletes.single['customerName'], 'ნინო გ.');
      expect(deletes.single['tableRefs'], ['first/5']);
    });

    test('a Manager delete is source MANAGER', () async {
      final id = await createPosBooking();

      await PosCommandApplier.deleteReservation(<String, dynamic>{
        'reservationId': id,
      });

      expectEntry(
        timeline(
          action: ReservationAuditAction.delete,
          reservationId: id,
        ).single,
        action: ReservationAuditAction.delete,
        source: 'MANAGER',
        actor: PosCommandApplier.defaultActor,
      );
    });
  });

  group('registry', () {
    test('legacy reservation_cancelled reads as CANCEL_RESERVATION', () {
      expect(
        ReservationAuditAction.normalize('reservation_cancelled'),
        ReservationAuditAction.cancel,
      );
      expect(
        ReservationAuditAction.normalize('confirm_reservation'),
        ReservationAuditAction.confirm,
      );
      expect(ReservationAuditAction.normalize('ORDER_CREATED'), isNull);
    });
  });
}
