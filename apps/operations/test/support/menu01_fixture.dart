import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/edge/edge_command_handler.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/contracts/edge_command.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';
import 'package:vynic/core/services/pos/closure_recovery_service.dart';

class Menu01NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('MENU01 fixture forbids actual HTTP');
}

const menu01Venue = 'menu01-venue-a';
const menu01Category = '10000000-0000-4000-8000-000000000001';
const menu01Item = '10000000-0000-4000-8000-000000000002';
const menu01ConflictItem = '10000000-0000-4000-8000-000000000003';
const menu01Closure = '10000000-0000-4000-8000-000000000004';
const menu01Device = '20000000-0000-4000-8000-000000000001';
const menu01Password = 'synthetic-backup-password-only';

Future<void> openMenu01(String path) async {
  dotenv.loadFromString(envString: 'POS_ENV=test');
  LocalDataAdmission.failure = null;
  EdgeDeviceCredentialStore.resetForTest();
  EdgeDeviceCredentialStore.directoryOverride = path;
  await DatabaseCore.open(managedDataDirectory: path);
  await EdgeDeviceCredentialStore.load();
}

Future<void> closeMenu01() async {
  await EdgeCommandJournal.close();
  await AuditSyncState.close();
  await StaffCredentialSyncState.close();
  await Hive.close();
  DatabaseCore.menuCanonicalBox = null;
  DatabaseCore.menuJournalBox = null;
  DatabaseCore.closureJournalBox = null;
}

EdgeCommandEnvelope menu01Command(
  String id, {
  String type = EdgeCommandTypes.noop,
}) => EdgeCommandEnvelope(
  contractVersion: 1,
  commandId: id,
  type: type,
  payload: null,
  idempotencyKey: 'key-$id',
  attempt: 1,
  issuedAt: DateTime.now().toUtc(),
  leaseExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
);

Future<void> seedMenu01({int itemCount = 2, int salesCount = 1}) async {
  await EdgeDeviceCredentialStore.saveEnrollment(
    rawCredential: 'vynic-device-v1.$menu01Device.${'s' * 40}',
    venueId: menu01Venue,
    venueName: 'Synthetic restaurant',
  );
  await DatabaseCore.settingsBox!.putAll({
    'currentDate': '2026-10-01T00:00:00.000',
    'serviceFeePercent': 0.0,
    'serviceFeeEnabled': false,
    'lastOrderId': 42,
    'posIngestConnectionKey': 'SYNTHETIC_CALLBACK_SECRET',
    'developerTerminalId': 'SOURCE_DEVELOPER_ID',
    'deviceRuntimeConfig': {'version': 1, 'deviceId': menu01Device},
    'venueName': 'Synthetic restaurant',
  });
  await DatabaseCore.userBox!.put(
    'staff-1',
    User(username: 'manager', pinCode: '852963', role: 'manager'),
  );
  final canonical = CanonicalMenu(
    venueId: menu01Venue,
    sequence: 15,
    nodes: {
      menu01Category: CanonicalNode(
        kind: MenuKind.category,
        id: menu01Category,
        revision: 1,
        fields: {
          'slug': 'food',
          'nameEn': 'Food',
          'nameKa': 'Food',
          'sendToKitchen': true,
          'enabled': true,
          'sortOrder': 0,
        },
      ),
      for (var i = 0; i < itemCount; i++)
        (i == 0
            ? menu01Item
            : i == 1
            ? menu01ConflictItem
            : 'item-$i'): CanonicalNode(
          kind: MenuKind.item,
          id: i == 0
              ? menu01Item
              : i == 1
              ? menu01ConflictItem
              : 'item-$i',
          revision: 1,
          fields: {
            'categoryId': menu01Category,
            'subcategoryId': null,
            'nameEn': i == 0 ? 'Item' : 'Item $i',
            'nameKa': i == 0 ? 'Item' : 'Item $i',
            'price': i == 0 ? 10.0 : 20.0,
            'sendToKitchen': true,
            'enabled': true,
            'sortOrder': i,
          },
        ),
    },
  );
  final local = MenuLocalStore.forBox(DatabaseCore.menuBox!);
  await local.run(
    () => local.commit(canonical, expectedGeneration: local.generation),
  );
  await MenuRepository.updateItemInCategory(
    categoryIndex: 0,
    itemIndex: 0,
    nameEn: 'Item',
    nameKa: 'Item',
    price: 12,
  );
  await local.run(() async {
    final conflict = MenuMutationEntry(
      seq: 2,
      mutationId: 'conflict-original-id',
      venueId: menu01Venue,
      entityType: 'ITEM',
      operation: 'UPSERT',
      entityId: menu01ConflictItem,
      expectedRevision: 1,
      patch: {'price': 22.0},
      status: MenuMutationStatus.conflict,
      createdAt: DateTime.utc(2026, 10, 1),
      conflict: {'revision': 2, 'price': 21.0},
    );
    final synced = MenuMutationEntry(
      seq: 3,
      mutationId: 'accepted-diagnostic-id',
      venueId: menu01Venue,
      entityType: 'ITEM',
      operation: 'UPSERT',
      entityId: menu01Item,
      expectedRevision: 1,
      patch: {'price': 10.0},
      status: MenuMutationStatus.synced,
      createdAt: DateTime.utc(2026, 10, 1),
    );
    await local.commit(
      canonical,
      puts: [conflict, synced],
      expectedGeneration: local.generation,
    );
  });
  Order order(int id) => Order(
    orderId: id,
    orderUuid: 'stable-order-$id',
    tableNumbers: ['$id'],
    floor: 'first',
    items: [
      OrderItem(
        itemKey: 'captured',
        itemName: 'Item',
        unitPrice: 7,
        quantity: 2,
        total: 14,
        menuItemId: menu01Item,
      ),
    ],
    totalAmount: 14,
    createdAt: DateTime.utc(2026, 10, 1, 10),
    createdBy: 'manager',
    status: 'confirmed',
    includeServiceFee: false,
  );
  final closing = order(41)..closureId = menu01Closure;
  await DatabaseCore.orderBox!.put(8, closing);
  await DatabaseCore.orderBox!.put(9, order(42));
  await DatabaseCore.tableBox!.put(
    4,
    TableModel(tableNumber: '41', floor: 'first', activeOrderId: 41),
  );
  await DatabaseCore.tableBox!.put(
    5,
    TableModel(tableNumber: '42', floor: 'first', activeOrderId: 42),
  );
  await AuditRepository.ensureAuditReport(orderId: 41, orderSnapshot: closing);
  final saleKey = await SalesRepository.saveSaleRecord(
    orderId: 41,
    tableNumbers: ['41'],
    floor: 'first',
    items: closing.items,
    totalAmount: 14,
    paymentMethod: 'cash',
    paymentBreakdown: {'cash': 14},
    createdBy: 'manager',
    createdAt: closing.createdAt,
    closedAt: DateTime.utc(2026, 10, 1, 11),
    includeServiceFee: false,
    discountAmount: 0,
    advanceAmount: 0,
    subtotalAmount: 14,
    manualAdjustmentAmount: 0,
    isFiscal: true,
    closureId: menu01Closure,
    closedById: 'manager',
    grossSaleAmount: 14,
    advanceApplied: 0,
    collectedNow: 14,
    businessDate: '2026-10-01',
  );
  if (saleKey == null) throw StateError('Fixture Sale failed');
  await ClosureJournalRepository.write(
    ClosureJournalEntry(
      closureId: menu01Closure,
      orderId: 41,
      phase: ClosurePhase.started,
      businessDate: '2026-10-01',
      isFiscal: true,
      grossSaleAmount: 14,
      advanceApplied: 0,
      collectedNow: 14,
      paymentMethod: 'cash',
      paymentBreakdown: {'cash': 14},
      actorId: 'manager',
      actorName: 'manager',
      startedAt: DateTime.utc(2026, 10, 1, 11),
      saleRecordKey: saleKey,
    ),
  );
  for (var i = 1; i < salesCount; i++) {
    await DatabaseCore.salesBox!.put('history-$i', {
      'posSaleId': 'historical-sale-$i',
      'ledgerRevision': 1,
      'ledgerUpdatedAt': '2026-10-01T10:00:00Z',
      'recordType': 'sale',
      'orderId': 100 + i,
      'date': '2026-09-30',
      'items': [
        {
          'itemName': 'Captured',
          'unitPrice': 7.0,
          'quantity': 2,
          'total': 14.0,
          'menuItemId': menu01Item,
        },
      ],
      'totalAmount': 14.0,
      'grossSaleAmount': 14.0,
      'collectedNow': 14.0,
      'paymentMethod': 'cash',
      'isFiscal': true,
    });
  }
  await SaleLedgerSyncState.ensureSaleIdentities();
  await EdgeCommandJournal.open();
  await EdgeCommandJournal.beginExecution(menu01Command('already-done'));
  await EdgeCommandJournal.completeExecution('already-done', succeeded: true);
  await EdgeCommandJournal.beginExecution(
    menu01Command('uncertain-print', type: EdgeCommandTypes.orderCheckPrint),
  );
}

Future<Map<String, dynamic>> verifyMenu01Recovery() async {
  await EdgeCommandJournal.open();
  final before = DatabaseCore.salesBox!.length;
  final outcomes = await ClosureRecoveryService.recoverPending();
  final again = await ClosureRecoveryService.recoverPending();
  final rows = MenuLocalStore.forBox(DatabaseCore.menuBox!).journal.all();
  final command = await EdgeCommandJournal.beginExecution(
    menu01Command('already-done'),
  );
  if (DatabaseCore.salesBox!.length != before ||
      again.isNotEmpty ||
      command?.status != EdgeExecutionStatus.succeeded ||
      rows.where((e) => e.sendable).length != 1 ||
      rows.where((e) => e.status == MenuMutationStatus.conflict).length != 1)
    throw StateError(
      'Recovery mismatch sales=${DatabaseCore.salesBox!.length}/$before, again=${again.length}, command=${command?.status}, rows=${rows.map((e) => e.status.name).toList()}',
    );
  final uncertainBefore = EdgeCommandJournal.entryFor(
    'uncertain-print',
  )!.status.name;
  var executions = 0;
  final client = EdgeTransportClient(
    baseUrl: () => 'http://synthetic-menu01.test',
    credential: () => 'synthetic-transport-only',
    httpClient: MockClient(
      (request) async => http.Response(
        request.url.path.endsWith('/claim')
            ? jsonEncode({
                'contractVersion': edgeCommandContractVersion,
                'commands': [
                  for (final cmd in [
                    menu01Command('already-done'),
                    menu01Command(
                      'uncertain-print',
                      type: EdgeCommandTypes.orderCheckPrint,
                    ),
                  ])
                    {
                      'contractVersion': cmd.contractVersion,
                      'commandId': cmd.commandId,
                      'type': cmd.type,
                      'payload': null,
                      'idempotencyKey': cmd.idempotencyKey,
                      'attempt': 2,
                      'issuedAt': cmd.issuedAt.toIso8601String(),
                      'leaseExpiresAt': cmd.leaseExpiresAt.toIso8601String(),
                    },
                ],
              })
            : '{}',
        200,
      ),
    ),
  );
  final transport = EdgeTransportService(
    client: client,
    registry: EdgeCommandRegistry([
      _Menu01CountingHandler(EdgeCommandTypes.noop, () => executions++),
      _Menu01CountingHandler(
        EdgeCommandTypes.orderCheckPrint,
        () => executions++,
      ),
    ]),
  );
  final delivery = await transport.pollOnce();
  client.close();
  if (executions != 0 ||
      delivery.skippedAlreadyDone != 2 ||
      delivery.acknowledged != 2 ||
      EdgeCommandJournal.entryFor('uncertain-print')!.code !=
          'interrupted_not_repeated')
    throw StateError('Restored command was executed again');
  return {
    'sales': before,
    'recoveryActions': outcomes.map((e) => e.action.name).toList(),
    'closurePhase': ClosureJournalRepository.find(menu01Closure)!.phase.name,
    'capturedOrderPrice': DatabaseCore.orderBox!.get(9)!.items.single.unitPrice,
    'salePrice':
        (DatabaseCore.salesBox!.values.first as Map)['items'][0]['unitPrice'],
    'menuPrice': DatabaseCore.menuBox!.values.first.items!.first.price,
    'conflictPrice': DatabaseCore.menuBox!.values.first.items![1].price,
    'menuMutationIds': rows.map((e) => e.mutationId).toList(),
    'menuStatuses': rows.map((e) => e.status.name).toList(),
    'cursor': MenuLocalStore.forBox(DatabaseCore.menuBox!).state!.sequence,
    'generation': MenuLocalStore.forBox(DatabaseCore.menuBox!).generation,
    'orderUuid': DatabaseCore.orderBox!.get(9)!.orderUuid,
    'saleKey': ClosureJournalRepository.find(menu01Closure)!.saleRecordKey,
    'duplicateCommand': executions != 0,
    'commandHandlersExecuted': executions,
    'commandsSkippedAlreadyDone': delivery.skippedAlreadyDone,
    'commandAcknowledgements': delivery.acknowledged,
    'uncertainCommand': uncertainBefore,
    'uncertainCommandResult': EdgeCommandJournal.entryFor(
      'uncertain-print',
    )!.code,
    'hasCredential': EdgeDeviceCredentialStore.hasCredential,
    'installationId': EdgeDeviceCredentialStore.installationId,
    'identityBinding': DatabaseCore.settingsBox!.get('restoreVenueBinding'),
    'staffPinPresent':
        DatabaseCore.userBox!.get('staff-1')!.pinCode == '852963',
    'pendingSales': SaleLedgerSyncState.buildBatch(
      DatabaseCore.salesBox!.values.whereType<Map>().map(
        (m) => Map<String, dynamic>.from(m),
      ),
    ).length,
  };
}

class _Menu01CountingHandler extends EdgeCommandHandler {
  _Menu01CountingHandler(this.type, this.count);
  @override
  final String type;
  final void Function() count;
  @override
  Future<EdgeCommandResult> execute(EdgeCommandEnvelope command) async {
    count();
    return EdgeCommandResult.succeeded(command.commandId);
  }
}
