import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';

void main() {
  late Directory directory;
  final now = DateTime(2026, 9, 13, 14);
  AuditEvent edit() => AuditEvent(
    type: AuditEventType.addItem,
    itemName: 'Tea',
    previousQty: 0,
    newQty: 1,
    waiterId: 'waiter',
    waiterName: 'Waiter',
    timestamp: now,
  );
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('open_order_audit_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    DatabaseCore.orderBox = await Hive.openBox<Order>('orders');
    DatabaseCore.auditLogBox = await Hive.openBox('audit');
    DatabaseCore.settingsBox = await Hive.openBox('settings');
    DatabaseCore.salesBox = await Hive.openBox('sales');
    DatabaseCore.closureJournalBox = await Hive.openBox('journal');
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.orderBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.closureJournalBox = null;
    directory.deleteSync(recursive: true);
  });
  Future<void> seed(
    int id, {
    String status = 'confirmed',
    bool locked = false,
    List<AuditEvent>? events,
  }) async {
    await DatabaseCore.orderBox!.add(
      Order(
        orderId: id,
        tableNumbers: ['2'],
        floor: 'first',
        items: [],
        totalAmount: 0,
        createdAt: now,
        createdBy: 'waiter',
        status: status,
      ),
    );
    // Report retains the original table after an Order moves to table 2.
    await AuditRepository.saveAuditReport(
      AuditReport(
        reportId: AuditRepository.buildAuditReportKey(id),
        orderId: id,
        tableNumbers: ['1'],
        floor: 'first',
        openedById: 'waiter',
        openedByName: 'Waiter',
        openedAt: now,
        status: locked ? AuditReportStatus.closed : AuditReportStatus.open,
        events: events ?? [edit()],
        updatedAt: now.add(Duration(minutes: id)),
        locked: locked,
        closedAt: locked ? now : null,
      ),
    );
  }

  test('reusing the original table never locks the moved live Order', () async {
    await seed(1);
    await AuditRepository.finalizeConflictingOpenAuditReports(
      currentOrderId: 2,
      floor: 'first',
      tableNumbers: ['1'],
      closedBy: 'waiter',
    );
    expect(AuditRepository.getAuditReport(1)!.locked, isFalse);
    await AuditRepository.appendOrderAuditEvents(orderId: 1, events: [edit()]);
    expect(AuditRepository.getAuditReport(1)!.locked, isFalse);
  });
  test('startup duplicate cleanup preserves every live Order', () async {
    await seed(1);
    await seed(2);
    await AuditRepository.runAuditDuplicateOpenCleanupOnce();
    expect(AuditRepository.getAuditReport(1)!.locked, isFalse);
    expect(AuditRepository.getAuditReport(2)!.locked, isFalse);
  });
  test(
    'legacy cleanup-only lock is repaired with a visible audit event',
    () async {
      await seed(1, locked: true);
      await AuditRepository.appendOrderAuditEvents(
        orderId: 1,
        events: [edit()],
      );
      final report = AuditRepository.getAuditReport(1)!;
      expect(report.locked, isFalse);
      expect(report.closedAt, isNull);
      expect(
        report.events.where(
          (e) => e.details?['reason'] == 'open_order_cleanup_lock_repair',
        ),
        hasLength(1),
      );
      await AuditRepository.appendOrderAuditEvents(
        orderId: 1,
        events: [edit()],
      );
      expect(
        AuditRepository.getAuditReport(1)!.events.where(
          (e) => e.details?['reason'] == 'open_order_cleanup_lock_repair',
        ),
        hasLength(1),
      );
    },
  );
  for (final type in [
    AuditEventType.close,
    AuditEventType.internalClose,
    AuditEventType.cancelTable,
    AuditEventType.transferClose,
  ]) {
    test(
      'never unlocks a real ${type.name} even if the Order looks open',
      () async {
        await seed(1, locked: true, events: [edit().copyWith(type: type)]);
        await expectLater(
          AuditRepository.appendOrderAuditEvents(orderId: 1, events: [edit()]),
          throwsStateError,
        );
        expect(AuditRepository.getAuditReport(1)!.locked, isTrue);
      },
    );
  }
  test('a live closure journal prevents synthetic-lock repair', () async {
    await seed(1, locked: true);
    await DatabaseCore.closureJournalBox!.put('closing', {
      'closureId': 'closing',
      'orderId': 1,
      'phase': 'started',
      'startedAt': now.toIso8601String(),
    });
    await expectLater(
      AuditRepository.appendOrderAuditEvents(orderId: 1, events: [edit()]),
      throwsStateError,
    );
  });
  test('closed Orders without typed close events remain locked', () async {
    await seed(1, locked: true, status: 'paid');
    await expectLater(
      AuditRepository.appendOrderAuditEvents(orderId: 1, events: [edit()]),
      throwsStateError,
    );
  });
  test('cleanup still finalizes a terminal old Order', () async {
    await seed(1, status: 'closed');
    await AuditRepository.finalizeConflictingOpenAuditReports(
      currentOrderId: 2,
      floor: 'first',
      tableNumbers: ['1'],
      closedBy: 'waiter',
    );
    expect(AuditRepository.getAuditReport(1)!.locked, isTrue);
  });
  test('recorded sale prevents repair of an inconsistent open Order', () async {
    await seed(1, locked: true);
    await DatabaseCore.salesBox!.add({'orderId': 1, 'restoredToOrder': false});
    await expectLater(
      AuditRepository.appendOrderAuditEvents(orderId: 1, events: [edit()]),
      throwsStateError,
    );
  });
}
