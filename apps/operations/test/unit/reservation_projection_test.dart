import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// What Cloud is told a reservation is, and what the terminal keeps.
///
/// The reservation box has never held only bookings: every order-creation path
/// writes a row into it, so a restaurant's box is roughly one row per order it
/// has ever taken. Cloud's consumers already throw those away on read, so the
/// snapshot was carrying two thousand rows to have nearly all of them
/// discarded. These state the two properties that replace that — Cloud gets
/// bookings, and the terminal keeps everything — and the one that keeps them
/// from being the same statement: a backup is local history, not a projection.
late Directory _tempDir;

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

Future<void> _openBoxes() async {
  DatabaseCore.userBox = await Hive.openBox<User>('rp_users');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('rp_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('rp_orders');
  DatabaseCore.packageBox = await Hive.openBox<Package>('rp_packages');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('rp_menu');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('rp_res');
  DatabaseCore.quickOrderBox = await Hive.openBox<QuickOrderDraft>('rp_quick');
  DatabaseCore.settingsBox = await Hive.openBox('rp_settings');
  DatabaseCore.salesBox = await Hive.openBox('rp_sales');
  DatabaseCore.expenseBox = await Hive.openBox('rp_expenses');
  DatabaseCore.auditLogBox = await Hive.openBox('rp_audit');
  DatabaseCore.errorLogBox = await Hive.openBox('rp_errors');
  DatabaseCore.metaBox = await Hive.openBox('rp_meta');
}

// ── The five shapes a real box holds ─────────────────────────────────────────

/// A genuine advance booking, as the reservation screen creates one.
Reservation booking({
  String id = 'res-booking',
  String status = 'confirmed',
  int? linkedOrderId,
  List<OrderItem>? preOrderItems,
  String customerName = 'Nino Beridze',
  String? notes = 'Window table please',
}) => Reservation(
  id: id,
  customerName: customerName,
  customerPhone: '+995555111222',
  tableNumbers: const [501],
  tableRefs: const ['first/5'],
  reservationDate: DateTime(2026, 9, 20),
  reservationTime: '19:30',
  numberOfGuests: 4,
  notes: notes,
  createdAt: DateTime(2026, 9, 1),
  createdBy: 'Nino',
  status: status,
  preOrderItems: preOrderItems,
  linkedOrderId: linkedOrderId,
);

/// What `OrderRepository.createOrder` writes for an ordinary table order.
Reservation walkInBookkeeping({String id = 'res-walkin', int orderId = 1765}) =>
    Reservation(
      id: id,
      customerName: 'Walk-in',
      customerPhone: '-',
      tableNumbers: const [],
      tableRefs: const ['first/7'],
      reservationDate: DateTime(2026, 9, 3),
      reservationTime: '13:05',
      numberOfGuests: 0,
      notes: 'Order #$orderId',
      createdAt: DateTime(2026, 9, 3),
      createdBy: 'Nino',
      linkedOrderId: orderId,
    );

/// What `createTakeAwayOrder` writes.
Reservation takeawayBookkeeping({
  String id = 'res-takeaway',
  int orderId = 1766,
  String? notes,
}) => Reservation(
  id: id,
  customerName: 'Takeaway',
  customerPhone: '-',
  tableNumbers: const [],
  reservationDate: DateTime(2026, 9, 3),
  reservationTime: '14:00',
  numberOfGuests: 3,
  notes: notes ?? 'Take-away Order #$orderId',
  createdAt: DateTime(2026, 9, 3),
  createdBy: 'Nino',
  status: 'confirmed',
  isTakeAway: true,
  linkedOrderId: orderId,
  preOrderItems: [
    OrderItem(
      itemKey: 'khinkali',
      itemName: 'ხინკალი',
      unitPrice: 1.2,
      quantity: 5,
      total: 6.0,
    ),
  ],
);

/// What `createOrderForPackage` writes — it goes through `createOrder`, so the
/// row it leaves behind is a walk-in row and nothing marks it as a package.
Reservation packageBookkeeping({String id = 'res-package', int orderId = 1767}) =>
    walkInBookkeeping(id: id, orderId: orderId);

/// A legacy row named like a generated one but without the note that proves it.
Reservation ambiguousLegacy({String id = 'res-ambiguous'}) => Reservation(
  id: id,
  customerName: 'Walk-in',
  customerPhone: '-',
  tableNumbers: const [],
  reservationDate: DateTime(2025, 4, 4),
  reservationTime: '20:00',
  numberOfGuests: 2,
  notes: null,
  createdAt: DateTime(2025, 4, 4),
  createdBy: 'Unknown',
);

Future<void> _seedMixedBox() async {
  await DatabaseCore.reservationBox!.clear();
  for (final reservation in [
    booking(id: 'real-future'),
    walkInBookkeeping(id: 'bk-walkin'),
    takeawayBookkeeping(id: 'bk-takeaway'),
    packageBookkeeping(id: 'bk-package'),
    booking(id: 'real-activated', status: 'in-progress', linkedOrderId: 1770),
  ]) {
    await DatabaseCore.reservationBox!.add(reservation);
  }
}

List<String> _idsOf(Iterable<Reservation> rows) =>
    rows.map((r) => r.id).toList();

void main() {
  setUpAll(() async {
    dotenv.loadFromString(envString: 'POS_ENV=test');
    _tempDir = await Directory.systemTemp.createTemp('vynic_reservation_proj');
    DatabaseCore.dataDirectoryPath = _tempDir.path;
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _openBoxes();
  });

  tearDownAll(() async {
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await DatabaseCore.settingsBox!.clear();
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      DateTime(2026, 9, 3).toIso8601String(),
    );
  });

  group('classification', () {
    test('a future booking is a booking', () {
      expect(
        ReservationClassification.kindOf(booking()),
        ReservationRecordKind.advanceBooking,
      );
      expect(ReservationClassification.isRealAdvanceBooking(booking()), isTrue);
    });

    test('a booking with a pre-ordered menu is still a booking', () {
      final withPreOrder = booking(
        preOrderItems: [
          OrderItem(
            itemKey: 'wine',
            itemName: 'ღვინო',
            unitPrice: 25,
            quantity: 2,
            total: 50,
          ),
        ],
      );

      expect(
        ReservationClassification.kindOf(withPreOrder),
        ReservationRecordKind.advanceBooking,
      );
    });

    test('an activated booking is still a booking', () {
      // The guest arrived, ActivateReservationTransaction created the order
      // serving them and recorded it here. That is what activation *is*; it
      // must not make the booking look like walk-in bookkeeping.
      final activated = booking(status: 'in-progress', linkedOrderId: 1770);

      expect(
        ReservationClassification.kindOf(activated),
        ReservationRecordKind.advanceBooking,
      );
      expect(ReservationClassification.isRealAdvanceBooking(activated), isTrue);
    });

    test('a completed booking whose link close-day cleared is still a booking', () {
      final settled = booking(status: 'completed', linkedOrderId: null);

      expect(ReservationClassification.isRealAdvanceBooking(settled), isTrue);
    });

    test('walk-in bookkeeping is not a booking', () {
      expect(
        ReservationClassification.kindOf(walkInBookkeeping()),
        ReservationRecordKind.orderBookkeeping,
      );
      expect(
        ReservationClassification.isRealAdvanceBooking(walkInBookkeeping()),
        isFalse,
      );
    });

    test('takeaway bookkeeping is not a booking, with or without its note', () {
      expect(
        ReservationClassification.kindOf(takeawayBookkeeping()),
        ReservationRecordKind.takeawayBookkeeping,
      );
      // The POS also writes '<operator notes> (Order #N)', which does not begin
      // with the generated prefix — isTakeAway is what answers for these.
      expect(
        ReservationClassification.kindOf(
          takeawayBookkeeping(notes: 'no onions (Order #1766)'),
        ),
        ReservationRecordKind.takeawayBookkeeping,
      );
    });

    test('package-generated bookkeeping is not a booking', () {
      // A package order goes through createOrder, so what it leaves is a
      // walk-in row. There is no package marker on it, and this asserts the
      // shape rather than pretending one exists.
      expect(
        ReservationClassification.kindOf(packageBookkeeping()),
        ReservationRecordKind.orderBookkeeping,
      );
    });

    test('an unclassifiable legacy row is kept, not discarded', () {
      final legacy = ambiguousLegacy();

      expect(
        ReservationClassification.kindOf(legacy),
        ReservationRecordKind.ambiguousLegacy,
      );
      // Conservative on purpose: dropping a real booking hides it from the
      // manager and frees its table on the public site.
      expect(ReservationClassification.isRealAdvanceBooking(legacy), isTrue);
    });

    test('a booking that merely mentions an order id is a booking', () {
      final mentions = booking(notes: 'Regular — paid Order #12 last week');

      expect(
        ReservationClassification.kindOf(mentions),
        ReservationRecordKind.advanceBooking,
      );
    });

    test('the serialized shape classifies the same as the record', () {
      expect(
        ReservationClassification.kindOfFields(
          isTakeAway: false,
          notes: 'Order #1765',
          customerName: 'Walk-in',
        ),
        ReservationRecordKind.orderBookkeeping,
      );
      expect(
        ReservationClassification.kindOfFields(
          isTakeAway: true,
          notes: null,
          customerName: 'Takeaway',
        ),
        ReservationRecordKind.takeawayBookkeeping,
      );
      expect(
        ReservationClassification.kindOfFields(
          isTakeAway: false,
          notes: 'Window table please',
          customerName: 'Nino Beridze',
        ),
        ReservationRecordKind.advanceBooking,
      );
    });
  });

  group('cloud projection', () {
    test('a mixed box projects to bookings only, activated one included', () {
      final projection = ReservationClassification.projectForCloud([
        booking(id: 'real-future'),
        walkInBookkeeping(id: 'bk-walkin'),
        takeawayBookkeeping(id: 'bk-takeaway'),
        packageBookkeeping(id: 'bk-package'),
        booking(id: 'real-activated', status: 'in-progress', linkedOrderId: 1770),
      ]);

      expect(_idsOf(projection.bookings), ['real-future', 'real-activated']);
      expect(projection.localCount, 5);
      expect(projection.sentCount, 2);
      expect(projection.bookkeepingCount, 3);
      expect(projection.takeawayCount, 1);
      expect(projection.generatedOrderCount, 2);
      expect(projection.ambiguousCount, 0);
    });

    test('an unclassifiable row is sent and counted separately', () {
      final projection = ReservationClassification.projectForCloud([
        booking(id: 'real'),
        ambiguousLegacy(id: 'legacy'),
        walkInBookkeeping(id: 'bk'),
      ]);

      expect(_idsOf(projection.bookings), ['real', 'legacy']);
      expect(projection.ambiguousCount, 1);
      expect(projection.bookkeepingCount, 1);
    });

    test('a box of nothing but bookkeeping projects to nothing', () {
      final projection = ReservationClassification.projectForCloud([
        walkInBookkeeping(id: 'a', orderId: 1),
        takeawayBookkeeping(id: 'b', orderId: 2),
      ]);

      expect(projection.bookings, isEmpty);
      expect(projection.sentCount, 0);
    });

    test('the summary carries counts and no reservation content', () {
      final projection = ReservationClassification.projectForCloud([
        booking(customerName: 'Nino Beridze', notes: 'Window table please'),
        walkInBookkeeping(),
        takeawayBookkeeping(),
      ]);

      final line = projection.summaryLine;

      expect(line, contains('local=3'));
      expect(line, contains('sent=1'));
      expect(line, contains('bookkeeping=2'));
      expect(line, contains('takeaway=1'));
      expect(line, contains('generatedOrder=1'));
      expect(line, isNot(contains('Nino')));
      expect(line, isNot(contains('Window table')));
      expect(line, isNot(contains('+995')));
    });
  });

  group('local history is not the Cloud projection', () {
    test('a backup carries every row, bookkeeping included', () async {
      await _seedMixedBox();

      final file = File('${_tempDir.path}/mixed_backup.json');
      await BackupRepository.createDataBackup(targetFilePath: file.path);
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rows = (payload['reservations'] as List)
          .cast<Map<String, dynamic>>();

      expect(rows, hasLength(5));
      expect(rows.map((r) => r['id']), containsAll(<String>['bk-walkin', 'bk-takeaway', 'bk-package']));
      // The fields the classifier reads survive the round to JSON, or a
      // restored box could not be classified at all.
      final takeaway = rows.firstWhere((r) => r['id'] == 'bk-takeaway');
      expect(takeaway['isTakeAway'], isTrue);
      expect(takeaway['preOrderItems'], isNotEmpty);
      final walkIn = rows.firstWhere((r) => r['id'] == 'bk-walkin');
      expect(walkIn['notes'], startsWith('Order #'));
      expect(walkIn['linkedOrderId'], 1765);
    });

    test('restoring that backup brings every row back', () async {
      await _seedMixedBox();
      final file = File('${_tempDir.path}/restore_backup.json');
      await BackupRepository.createDataBackup(targetFilePath: file.path);
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      await DatabaseCore.reservationBox!.clear();
      await BackupRepository.replaceReservationsFromJson(
        payload['reservations'] as List,
      );

      final restored = DatabaseCore.reservationBox!.values.toList();
      expect(restored, hasLength(5));
      expect(
        _idsOf(restored)..sort(),
        <String>[
          'bk-package',
          'bk-takeaway',
          'bk-walkin',
          'real-activated',
          'real-future',
        ],
      );
      expect(
        restored.firstWhere((r) => r.id == 'bk-takeaway').isTakeAway,
        isTrue,
      );
      expect(
        restored.firstWhere((r) => r.id == 'real-activated').linkedOrderId,
        1770,
      );
    });

    test('a restored box still projects to bookings only', () async {
      // The invariant this whole phase rests on: the filter lives in the
      // projection, so restoring history and narrowing what Cloud is told are
      // not the same operation and cannot be confused for one.
      await _seedMixedBox();
      final file = File('${_tempDir.path}/roundtrip_backup.json');
      await BackupRepository.createDataBackup(targetFilePath: file.path);
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      await DatabaseCore.reservationBox!.clear();
      await BackupRepository.replaceReservationsFromJson(
        payload['reservations'] as List,
      );

      final projection = ReservationClassification.projectForCloud(
        DatabaseCore.reservationBox!.values,
      );

      expect(DatabaseCore.reservationBox!.length, 5);
      expect(_idsOf(projection.bookings)..sort(), [
        'real-activated',
        'real-future',
      ]);
    });

    test('an old backup with no tableRefs restores and classifies', () async {
      // What a build predating the canonical refs wrote: legacy integer codes,
      // no tableRefs, and the same mixed history.
      final legacyPayload = <Map<String, dynamic>>[
        {
          'id': 'old-real',
          'customerName': 'Giorgi',
          'customerPhone': '+995555000111',
          'tableNumbers': [501],
          'reservationDate': '2026-09-20T00:00:00.000',
          'reservationTime': '19:00',
          'numberOfGuests': 2,
          'notes': 'Anniversary',
          'createdAt': '2026-09-01T00:00:00.000',
          'createdBy': 'Nino',
          'status': 'confirmed',
        },
        {
          'id': 'old-walkin',
          'customerName': 'Walk-in',
          'customerPhone': '-',
          'tableNumbers': <int>[],
          'reservationDate': '2024-01-05T00:00:00.000',
          'reservationTime': '12:00',
          'numberOfGuests': 0,
          'notes': 'Order #431',
          'createdAt': '2024-01-05T00:00:00.000',
          'createdBy': 'Nino',
          'status': 'pending',
          'linkedOrderId': 431,
        },
        {
          'id': 'old-takeaway',
          'customerName': 'Takeaway',
          'customerPhone': '-',
          'tableNumbers': <int>[],
          'reservationDate': '2024-01-05T00:00:00.000',
          'reservationTime': '12:30',
          'numberOfGuests': 1,
          'notes': 'Take-away Order #432',
          'createdAt': '2024-01-05T00:00:00.000',
          'createdBy': 'Nino',
          'status': 'completed',
          'isTakeAway': true,
          'linkedOrderId': 432,
        },
      ];

      await DatabaseCore.reservationBox!.clear();
      await BackupRepository.replaceReservationsFromJson(legacyPayload);

      final restored = DatabaseCore.reservationBox!.values.toList();
      final projection = ReservationClassification.projectForCloud(restored);

      expect(restored, hasLength(3), reason: 'no row is dropped on restore');
      expect(_idsOf(projection.bookings), ['old-real']);
      expect(projection.bookkeepingCount, 2);
    });
  });

  group('the box itself is never narrowed', () {
    test('projecting does not touch a single stored row', () async {
      await _seedMixedBox();
      final before = DatabaseCore.reservationBox!.values
          .map(
            (r) =>
                '${r.id}|${r.status}|${r.isTakeAway}|${r.linkedOrderId}|${r.notes}',
          )
          .toList();

      ReservationClassification.projectForCloud(
        DatabaseCore.reservationBox!.values,
      );
      ReservationClassification.projectForCloud(
        DatabaseCore.reservationBox!.values,
      );

      final after = DatabaseCore.reservationBox!.values
          .map(
            (r) =>
                '${r.id}|${r.status}|${r.isTakeAway}|${r.linkedOrderId}|${r.notes}',
          )
          .toList();
      expect(after, before);
      expect(DatabaseCore.reservationBox!.length, 5);
    });

    test('the takeaway rows the home panel reads are still there', () async {
      // Phase 2 moves that panel onto orders. Until it does, these rows and
      // their pre-order items have to stay exactly where the panel looks.
      await _seedMixedBox();

      ReservationClassification.projectForCloud(
        DatabaseCore.reservationBox!.values,
      );

      final takeaways = DatabaseCore.reservationBox!.values
          .where((r) => r.isTakeAway)
          .toList();
      expect(takeaways, hasLength(1));
      expect(takeaways.single.preOrderItems, isNotEmpty);
      expect(takeaways.single.status, ReservationStatus.confirmed.storageValue);
    });
  });
}
