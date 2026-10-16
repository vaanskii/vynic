import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';

void main() {
  test(
    'TCP identity has deterministic spelling and detached immutable values',
    () {
      final a = PrinterDestination.tcp(host: '10.0.0.4', port: 9100);
      final b = PrinterDestination.decode({
        'port': 9100,
        'host': '10.0.0.4',
        'kind': 'tcp',
      });
      expect(a.identity, b.identity);
      a.toMap()['host'] = '10.0.0.9';
      expect(a.host, '10.0.0.4');
    },
  );
  test('spooler identity includes owner, exact driver and exact port', () {
    final a = PrinterDestination.windowsSpooler(
      ownerDeviceId: 'device-a',
      queueName: 'POS 80',
      driverName: 'Vendor ESC/POS',
      portName: 'USB001',
    );
    for (final field in [
      'ownerDeviceId',
      'queueName',
      'driverName',
      'portName',
    ]) {
      final changed = a.toMap()..[field] = '${a.toMap()[field]} changed';
      expect(PrinterDestination.decode(changed).identity, isNot(a.identity));
    }
  });
  test('unknown fields, incomplete variants and controls fail closed', () {
    final valid = PrinterDestination.tcp(host: '10.0.0.4', port: 9100).toMap();
    for (final raw in [
      null,
      {...valid, 'queueName': 'Other'},
      {...valid, 'port': 0},
      {...valid, 'host': 'x\n'},
      {'kind': 'usb', 'device': 'arbitrary'},
      {'kind': 'windowsSpooler', 'queueName': 'POS'},
    ]) {
      expect(() => PrinterDestination.decode(raw), throwsFormatException);
    }
  });
  test(
    'route freezes identity and revision independently of later configuration',
    () {
      final raw = {
        'protocol': 1,
        'id': 'bar-printer',
        'name': 'Bar',
        'role': 'bar',
        'revision': 1,
        'destination': PrinterDestination.tcp(
          host: '10.0.0.5',
          port: 9100,
        ).toMap(),
      };
      final route = PrinterRoute.decode(raw);
      (raw['destination'] as Map)['host'] = '10.0.0.8';
      raw['revision'] = 2;
      expect(route.destination.host, '10.0.0.5');
      expect(route.revision, 1);
      expect(route.role, PrinterRole.bar);
    },
  );
}
