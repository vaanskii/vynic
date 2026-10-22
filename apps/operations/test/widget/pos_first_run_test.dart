import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/pos_first_run.dart';
import 'package:vynic/apps/windows_pos/screens/pos_manager_registration_screen.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';

void main() {
  testWidgets(
    'enrolled POS waits for its Manager instead of an empty PIN login',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('pos-first-run'),
      ))!;
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = directory.path;
      await tester.runAsync(() async {
        expect(
          await EdgeDeviceCredentialStore.saveEnrollment(
            rawCredential:
                'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-secret-00000000000000000000',
            venueId: 'test-venue',
            venueName: 'Test venue',
          ),
          isTrue,
        );
      });
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'state': 'READY',
            'setupId': '00000000-0000-4000-8000-000000000099',
          }),
          200,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: PosFirstRun(activationClient: client)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('შექმენით პირველი Manager'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Manager-ის შექმნა'));
      await tester.pumpAndSettle();
      expect(find.byType(PosManagerRegistrationScreen), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'აქტივაციის კოდი'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      EdgeDeviceCredentialStore.resetForTest();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
  Future<Directory> savedIdentity(WidgetTester tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('pos-reconnect-test-'),
    ))!;
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await tester.runAsync(
      () => EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-secret-00000000000000000000',
        venueId: 'test-venue',
        venueName: 'Test venue',
      ),
    );
    addTearDown(() async {
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = null;
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    return directory;
  }

  testWidgets(
    '401 stale enrollment exposes reconnect and cancel without changing identity or business data',
    (tester) async {
      final directory = await savedIdentity(tester);
      final identity = File('${directory.path}/edge_device.json');
      final before = identity.readAsStringSync();
      final business = File('${directory.path}/synthetic-business.json')
        ..writeAsStringSync('synthetic pending order');
      final service = _FakeEnrollment(
        const PosEnrollmentResult(PosEnrollmentStatus.rejected),
      );
      final client = MockClient((_) async => http.Response('{}', 401));
      await tester.pumpWidget(
        MaterialApp(
          home: PosFirstRun(service: service, activationClient: client),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('შენახული წვდომა სერვერმა უარყო'),
        findsOneWidget,
      );
      await tester.tap(find.text('POS-ის ხელახლა დაკავშირება'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'მოწყობილობის კოდი'),
        'ABCD-EFGH-IJKL',
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(identity.readAsStringSync() == before, isTrue);
      expect(business.readAsStringSync() == 'synthetic pending order', isTrue);
      expect(find.text('POS-ის ხელახლა დაკავშირება'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rejected reconnect retains the form and existing device identity',
    (tester) async {
      final directory = await savedIdentity(tester);
      final identity = File('${directory.path}/edge_device.json');
      final before = identity.readAsStringSync();
      final service = _FakeEnrollment(
        const PosEnrollmentResult(
          PosEnrollmentStatus.rejected,
          message: 'Synthetic setup code expired',
        ),
      );
      final client = MockClient((_) async => http.Response('{}', 401));
      await tester.pumpWidget(
        MaterialApp(
          home: PosFirstRun(service: service, activationClient: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('POS-ის ხელახლა დაკავშირება'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Development API URL'),
        'http://api.vynic.localhost',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'მოწყობილობის კოდი'),
        'ABCD-EFGH-IJKL',
      );
      await tester.ensureVisible(find.text('მოწყობილობის დაკავშირება'));
      await tester.tap(find.text('მოწყობილობის დაკავშირება'));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(service.address, 'http://api.vynic.localhost');
      expect(find.text('Synthetic setup code expired'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'მოწყობილობის კოდი'),
        findsOneWidget,
      );
      expect(identity.readAsStringSync() == before, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final state in ['EXISTING_MANAGER', 'WAITING_PRIMARY']) {
    testWidgets(
      'additional POS waits ($state) without Manager creation or a second code',
      (tester) async {
        await savedIdentity(tester);
        final client = MockClient(
          (_) async =>
              http.Response(jsonEncode({'state': state, 'setupId': null}), 200),
        );
        await tester.pumpWidget(
          MaterialApp(home: PosFirstRun(activationClient: client)),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            state == 'WAITING_PRIMARY'
                ? 'ეს დამატებითი POS'
                : 'მენეჯერის წვდომის მიღების მოლოდინში',
          ),
          findsOneWidget,
        );
        expect(find.text('Manager-ის შექმნა'), findsNothing);
        expect(find.text('პირველი აქტივაცია'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(1024, 768), const Size(1440, 900)]) {
    testWidgets('POS code entry stays usable at $size', (tester) async {
      EdgeDeviceCredentialStore.resetForTest();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: PosFirstRun()));
      expect(find.text('Vynic POS'), findsOneWidget);
      final code = find.widgetWithText(TextField, 'მოწყობილობის კოდი');
      await tester.enterText(code, 'ABCD-EFGH-IJKL');
      await tester.ensureVisible(find.text('მოწყობილობის დაკავშირება'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _FakeEnrollment extends PosEnrollmentService {
  _FakeEnrollment(this.result);
  final PosEnrollmentResult result;
  int calls = 0;
  String? address;
  @override
  Future<PosEnrollmentResult> enroll({
    required String serverAddress,
    required String code,
  }) async {
    calls++;
    address = serverAddress;
    return result;
  }
}
