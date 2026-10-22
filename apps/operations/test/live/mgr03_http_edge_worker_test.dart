import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_transport_client.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/models/table.dart';
import '../support/pos03_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['MGR03_NATIVE_RUN'];
  test(
    'owned real HTTP/PG claim executes through native Edge and survives lost ACK',
    () async {
      if (root == null) return;
      final path = Directory(root).absolute.path;
      if (!RegExp(r'^/(?:private/)?tmp/vynic-mgr03-[^/]+/').hasMatch(path))
        throw StateError('Owned synthetic MGR03 directory required');
      await Directory('$path/hive').create(recursive: true);
      final fixture = Pos03Fixture();
      await fixture.open('$path/hive');
      await fixture.seed();
      await DatabaseCore.tableBox!.put(
        'free',
        TableModel(tableNumber: '19', floor: 'first'),
      );
      if (Platform.environment['MGR03_NATIVE_STAGE'] == 'baseline') {
        await File('$path/native-http-fixture.json').writeAsString(
          jsonEncode({
            'projection': OrderEditProjection.build(
              OrderRepository.getOrder(1)!,
              effectiveServiceFeePercent: 0,
            ),
          }),
          flush: true,
        );
      } else {
        final command = Map<String, dynamic>.from(
          jsonDecode(await File('$path/claim.json').readAsString()),
        );
        const credential =
            'vynic-device-v1.11111111-1111-4111-8111-111111111111.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        EdgeDeviceCredentialStore.directoryOverride = path;
        EdgeDeviceCredentialStore.resetForTest();
        await EdgeDeviceCredentialStore.load();
        await EdgeDeviceCredentialStore.save(credential);
        final acks = <Map<String, dynamic>>[];
        EdgeTransportService transport() => EdgeTransportService(
          client: EdgeTransportClient(
            baseUrl: () => 'http://synthetic.invalid',
            credential: () => credential,
            httpClient: MockClient((r) async {
              if (r.url.path.endsWith('/claim'))
                return http.Response(
                  jsonEncode({
                    'contractVersion': 2,
                    'commands': [command],
                  }),
                  200,
                );
              acks.add(Map<String, dynamic>.from(jsonDecode(r.body)));
              return http.Response('{}', acks.length == 1 ? 503 : 200);
            }),
          ),
        );
        final first = transport();
        await first.start();
        await first.pollOnce();
        expect(acks.single['status'], 'SUCCEEDED');
        await first.shutdown();
        final audit = DatabaseCore.auditLogBox!.toMap();
        final kind = command['payload']['managerOperation']['kind'];
        if (kind == 'reservation_status') {
          final r = DatabaseCore.reservationBox!.get('booking')!
            ..status = 'cancelled';
          await r.save();
        }
        if (kind == 'takeaway_create' || kind == 'dine_in_create') {
          final order = OrderRepository.getOrder(
            command['payload']['posOrderId'],
          )!..customerName = 'Later local edit';
          await order.save();
        }
        await fixture.close();
        await fixture.open('$path/hive');
        final second = transport();
        await second.start();
        await second.pollOnce();
        await second.shutdown();
        expect(acks.last['status'], 'SUCCEEDED');
        expect(DatabaseCore.auditLogBox!.toMap(), audit);
        if (kind == 'reservation_status')
          expect(
            DatabaseCore.reservationBox!.get('booking')!.status,
            'cancelled',
          );
        if (kind == 'takeaway_create' || kind == 'dine_in_create')
          expect(
            OrderRepository.getOrder(
              command['payload']['posOrderId'],
            )!.customerName,
            'Later local edit',
          );
        await File('$path/native-result.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'acks': acks,
            'pid': pid,
            'kind': kind,
            'lostAckPreservedLaterWork': true,
          }),
          flush: true,
        );
        EdgeDeviceCredentialStore.directoryOverride = null;
        EdgeDeviceCredentialStore.resetForTest();
      }
      await fixture.close();
    },
  );
}
