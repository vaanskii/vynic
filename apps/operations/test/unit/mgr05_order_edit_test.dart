import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/order_edit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import '../support/pos03_fixture.dart';

const mgr05Id = 'c5000000-0000-4000-8000-000000000001';
Future<Map<String, dynamic>> seedMgr05(Pos03Fixture fixture) async {
  await fixture.seed(rich: true);
  final before = DatabaseCore.orderBox!.get('source')!;
  before.items.single.lineUuid = 'c5000000-0000-4000-8000-000000000003';
  await DatabaseCore.orderBox!.put('source', before);
  await DatabaseCore.orderBox!.flush();
  final projection = OrderEditProjection.build(before);
  final item = before.items.single.toJson()
    ..['quantity'] = 5
    ..['total'] = 12.5;
  return {
    '_mutationRequestId': mgr05Id,
    'baseline': projection,
    'businessDate': '2026-10-01',
    'actorStaffId': 'c5000000-0000-4000-8000-000000000002',
    'actorUsername': 'Synthetic manager',
    'request': {
      'posOrderId': 1,
      'expectedFingerprint': projection['fingerprint'],
      'items': [item],
      'includeServiceFee': false,
      'customServiceFeePercentage': 3.0,
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  late Map<String, dynamic> payload;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr05-unit-');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    payload = await seedMgr05(fixture);
    fixture.trace.clear();
  });
  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    LocalDataAdmission.failure = null;
    await dir.delete(recursive: true);
  });
  test(
    'edit preserves all frozen package/advance/discount/ownership fields and one audit receipt',
    () async {
      final before = jsonDecode(payload['baseline']['image']) as Map;
      final outcome = await OrderEditRepository.apply(payload);
      expect(outcome.ok, isTrue);
      final fixturePath = Platform.environment['MGR05_FIXTURE_OUTPUT'];
      if (fixturePath != null) {
        if (!fixturePath.startsWith('/tmp/vynic-mgr05-'))
          throw StateError('Owned fixture output required');
        await File(fixturePath).writeAsString(
          jsonEncode({'payload': payload, 'result': outcome.data}),
          flush: true,
        );
      }
      final after = BackupRepository.serializeOrder(
        DatabaseCore.orderBox!.get('source')!,
      );
      for (final k in before.keys.where(
        (k) => !['items', 'updatedAt', 'totalAmount'].contains(k),
      ))
        expect(after[k], before[k], reason: k);
      expect(after['totalAmount'], 18.34);
      expect(after['items'][0]['comment'], ' keep ');
      final audit = DatabaseCore.auditLogBox!.toMap();
      expect(audit[mgr05Id], isNotNull);
      expect(OrderTableMutationRepository.records(), isEmpty);
      final receipt = OrderEditRepository.records().single;
      expect(receipt['phase'], 'completed');
      expect((await OrderEditRepository.apply(payload)).data, outcome.data);
      expect(DatabaseCore.auditLogBox!.toMap(), audit);
    },
  );
  for (final invalid in [
    'missing_items',
    'fractional_quantity',
    'negative_price',
    'nan_price',
    'duplicate_line',
    'invalid_total',
    'bad_actor',
    'bad_baseline',
    'bad_fee',
  ]) {
    test('whole DTO rejects $invalid before any intent/effect', () async {
      final p = orderTransferIntentClone(payload);
      final r = p['request'];
      final item = r['items'][0];
      if (invalid == 'missing_items') r.remove('items');
      if (invalid == 'fractional_quantity') item['quantity'] = 1.5;
      if (invalid == 'invalid_total') item['total'] = 1;
      if (invalid == 'negative_price') item['unitPrice'] = -1;
      if (invalid == 'nan_price') item['unitPrice'] = double.nan;
      if (invalid.startsWith('duplicate'))
        r['items'].add(Map<String, dynamic>.from(item));
      if (invalid == 'bad_actor') p['actorStaffId'] = 'spoof';
      if (invalid == 'bad_baseline') p['baseline']['fingerprint'] = 'bad';
      if (invalid == 'bad_fee') r['customServiceFeePercentage'] = 101;
      final before = BackupRepository.serializeOrder(
        DatabaseCore.orderBox!.get('source')!,
      );
      expect(
        (await OrderEditRepository.apply(p)).code,
        'invalid_order_edit_request',
      );
      expect(
        BackupRepository.serializeOrder(DatabaseCore.orderBox!.get('source')!),
        before,
      );
      expect(OrderEditRepository.records(), isEmpty);
    });
  }
  for (final changed in ['closed', 'date', 'uuid', 'baseline', 'missing']) {
    test('$changed state refuses edit with zero durable effects', () async {
      final row = DatabaseCore.orderBox!.get('source')!;
      if (changed == 'closed') row.status = 'closed';
      if (changed == 'uuid')
        row.orderUuid = 'c5000000-0000-4000-8000-000000000099';
      if (changed == 'baseline') row.items.single.comment = 'changed';
      if (changed == 'missing')
        await DatabaseCore.orderBox!.delete('source');
      else
        await DatabaseCore.orderBox!.put('source', row);
      if (changed == 'date') payload['businessDate'] = '2026-10-02';
      try {
        expect((await OrderEditRepository.apply(payload)).ok, isFalse);
      } on OrderMutationConflict catch (e) {
        expect(e.code, 'stale_order');
      }
      expect(OrderEditRepository.records(), isEmpty);
      expect(
        fixture.trace.where((v) => v.startsWith('meta.put:transfer')),
        isEmpty,
      );
    });
  }
  test(
    'completed business receipt retains result after later edits and transport pruning',
    () async {
      final first = await OrderEditRepository.apply(payload);
      final order = DatabaseCore.orderBox!.get('source')!;
      order.items.single.comment = 'later';
      await DatabaseCore.orderBox!.put('source', order);
      expect((await OrderEditRepository.apply(payload)).data, first.data);
      expect(
        DatabaseCore.orderBox!.get('source')!.items.single.comment,
        'later',
      );
      final changed = orderTransferIntentClone(payload);
      changed['actorUsername'] = 'different';
      expect(
        (await OrderEditRepository.apply(changed)).code,
        'request_conflict',
      );
    },
  );
  for (final point in [
    for (final phase in ['intent', 'order', 'report', 'audit', 'completed'])
      for (final side in ['before', 'after']) 'meta.put:transfer:$phase:$side',
    for (final store in ['meta', 'orders', 'audit'])
      for (final side in ['before', 'after']) '$store.flush:$side',
    for (final side in ['before', 'after']) 'orders.put:source:$side',
    for (final side in ['before', 'after'])
      'audit.put:audit_report_order_1:$side',
    for (final side in ['before', 'after']) 'audit.put:reservation-event:$side',
  ]) {
    test('IO interruption $point recovers exact edit/audits once', () async {
      var hit = false;
      fixture.fault = (p, _) async {
        if (!hit && p == point) {
          hit = true;
          throw StateError('Synthetic interruption');
        }
      };
      await expectLater(OrderEditRepository.apply(payload), throwsStateError);
      expect(hit, isTrue);
      fixture.fault = null;
      await fixture.close();
      await fixture.open(dir.path);
      await OrderEditRepository.recoverPending();
      expect((await OrderEditRepository.apply(payload)).ok, isTrue);
      expect(DatabaseCore.orderBox!.get('source')!.items.single.quantity, 5);
      expect(OrderEditRepository.records().single['phase'], 'completed');
      final audit = DatabaseCore.auditLogBox!.toMap();
      await OrderEditRepository.apply(payload);
      expect(DatabaseCore.auditLogBox!.toMap(), audit);
    });
  }
  test(
    'pending public portable restore completes edit without manual recovery',
    () async {
      fixture.fault = (p, _) async {
        if (p == 'orders.flush:after')
          throw StateError('Synthetic interruption');
      };
      await expectLater(OrderEditRepository.apply(payload), throwsStateError);
      fixture.fault = null;
      LocalDataAdmission.failure = null;
      final file = await BackupRepository.createDataBackup(
        targetFilePath: '${dir.path}/pending.json',
        password: 'Synthetic password only',
      );
      await fixture.close();
      await fixture.open((await Directory('${dir.path}/fresh').create()).path);
      await BackupRepository.restoreDataBackupFromFile(
        file,
        password: 'Synthetic password only',
        backupBeforeRestore: false,
      );
      expect(OrderEditRepository.records().single['phase'], 'completed');
      expect(
        DatabaseCore.orderBox!.values
            .singleWhere((o) => o.orderId == 1)
            .items
            .single
            .quantity,
        5,
      );
      expect((await OrderEditRepository.apply(payload)).ok, isTrue);
    },
  );
  test(
    'same dish with different comments preserves both stable lines and audits',
    () async {
      final before = DatabaseCore.orderBox!.get('source')!;
      final second = before.items.single.clone()
        ..lineUuid = 'c5000000-0000-4000-8000-000000000004'
        ..comment = 'second note';
      before.items.add(second);
      await DatabaseCore.orderBox!.put('source', before);
      final projection = OrderEditProjection.build(before);
      payload['baseline'] = projection;
      payload['request']['expectedFingerprint'] = projection['fingerprint'];
      payload['request']['items'] = [
        for (final i in before.items)
          i.toJson()
            ..['quantity'] = 5
            ..['total'] = 12.5,
      ];
      final outcome = await OrderEditRepository.apply(payload);
      expect(outcome.ok, isTrue);
      await exportMgr05Fixture(payload, outcome.data, '.two-line');
      final after = DatabaseCore.orderBox!.get('source')!;
      expect(after.items.length, 2);
      expect(after.items.map((i) => i.comment), [' keep ', 'second note']);
      final events =
          OrderEditRepository.records().single['afterReport']['events'] as List;
      expect(events.where((e) => e['type'] == 'ADD_ITEM').length, 2);
    },
  );
  for (final hostile in [
    'missing_business_receipt',
    'altered_result',
    'wrong_code',
    'unresolved_business_receipt',
  ])
    test(
      'hostile restored transport $hostile fails before replacement',
      () async {
        final outcome = await OrderEditRepository.apply(payload);
        final stores = <String, Map<dynamic, dynamic>>{
          'meta': DatabaseCore.metaBox!.toMap(),
          'orders': DatabaseCore.orderBox!.toMap(),
          'auditLog': DatabaseCore.auditLogBox!.toMap(),
          'settings': DatabaseCore.settingsBox!.toMap(),
          'edge_command_journal': {
            'command': {
              'commandId': mgr05Id,
              'type': 'ORDER_EDIT',
              'status': 'succeeded',
              'code': 'order_edited',
              'resultProjection': outcome.data,
            },
          },
        };
        expect(OrderEditRepository.validateBackup(stores), 0);
        if (hostile == 'missing_business_receipt') stores['meta']!.clear();
        if (hostile == 'altered_result')
          stores['edge_command_journal']!['command']['resultProjection'] = {
            'altered': 'fake',
          };
        if (hostile == 'wrong_code')
          stores['edge_command_journal']!['command']['code'] =
              'already_executed';
        if (hostile == 'unresolved_business_receipt') {
          final v = Map<String, dynamic>.from(
            stores['meta']![OrderEditRepository.key(mgr05Id)],
          )..remove('digest');
          v['phase'] = 'audit';
          stores['meta']![OrderEditRepository.key(mgr05Id)] = {
            ...v,
            'digest': PosBackupFormat.digest(v),
          };
        }
        expect(
          () => OrderEditRepository.validateBackup(stores),
          throwsFormatException,
        );
      },
    );
  test(
    'default 12 percent fee is frozen in result and survives later default change',
    () async {
      await DatabaseCore.settingsBox!.putAll({
        'serviceFeePercent': 12.0,
        'serviceFeeEnabled': true,
      });
      payload['request']['customServiceFeePercentage'] = null;
      payload['request']['includeServiceFee'] = true;
      final first = await OrderEditRepository.apply(payload);
      await exportMgr05Fixture(payload, first.data, '.default-fee');
      expect(first.data['effectiveServiceFeePercent'], 12);
      expect(DatabaseCore.orderBox!.get('source')!.totalAmount, 19.84);
      await DatabaseCore.settingsBox!.put('serviceFeePercent', 15.0);
      expect((await OrderEditRepository.apply(payload)).data, first.data);
    },
  );
  test(
    'tampered completed receipt fails closed even with recomputed outer digest',
    () async {
      await OrderEditRepository.apply(payload);
      final v = Map<String, dynamic>.from(
        DatabaseCore.metaBox!.get(OrderEditRepository.key(mgr05Id)) as Map,
      )..remove('digest');
      v['after']['discountAmount'] = 999;
      await DatabaseCore.metaBox!.put(OrderEditRepository.key(mgr05Id), {
        ...v,
        'digest': PosBackupFormat.digest(v),
      });
      expect(() => OrderEditRepository.records(), throwsFormatException);
    },
  );
}

Map<String, dynamic> orderTransferIntentClone(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

Future<void> exportMgr05Fixture(
  Map<String, dynamic> payload,
  Map<String, dynamic> result,
  String suffix,
) async {
  final path = Platform.environment['MGR05_FIXTURE_OUTPUT'];
  if (path == null) return;
  if (!path.startsWith('/tmp/vynic-mgr05-'))
    throw StateError('Owned fixture output required');
  await File('$path$suffix.json').writeAsString(
    jsonEncode({'payload': payload, 'result': result}),
    flush: true,
  );
}
