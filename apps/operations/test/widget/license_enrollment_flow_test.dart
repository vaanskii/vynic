import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vynic/apps/windows_pos/screens/pos_first_run.dart';
import 'package:vynic/apps/windows_pos/screens/pos_manager_registration_screen.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:vynic/core/services/licensing/license_host.dart';
import 'package:vynic/core/services/licensing/subscription_license.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';

class ControlledEnrollment extends PosEnrollmentService {
  int calls = 0;
  String? code;
  Completer<PosEnrollmentResult>? pending;
  @override
  Future<PosEnrollmentResult> enroll({
    required String serverAddress,
    required String code,
  }) {
    calls++;
    this.code = code;
    pending = Completer<PosEnrollmentResult>();
    return pending!.future;
  }
}

class ControlledVerification extends SubscriptionLicense {
  int calls = 0;
  Completer<String>? pending;
  @override
  Future<void> verify() async {
    calls++;
    busy = true;
    notifyListeners();
    pending = Completer<String>();
    final result = await pending!.future;
    lease.reason = result;
    lease.remainingMs = result == 'VALID' ? 86400000 : 0;
    busy = false;
    notifyListeners();
  }
}

void main() {
  late Directory directory;
  late ControlledEnrollment enrollment;
  late ControlledVerification license;
  late GlobalKey<NavigatorState> navigator;
  const credential =
      'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-secret-00000000000000000000';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('license-enrollment-ui-');
    Hive.init(directory.path);
    DatabaseCore.settingsBox = await Hive.openBox('license-enrollment');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    await EdgeDeviceCredentialStore.load();
    enrollment = ControlledEnrollment();
    license = ControlledVerification()..enabled = true;
    navigator = GlobalKey<NavigatorState>();
  });
  tearDown(() async {
    license.dispose();
    await Hive.close();
    DatabaseCore.settingsBox = null;
    EdgeDeviceCredentialStore.resetForTest();
    await directory.delete(recursive: true);
  });
  Future<void> saveIdentity(WidgetTester tester) async {
    await tester.runAsync(
      () => EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: credential,
        venueId: 'fixture-venue',
        venueName: 'Fixture venue',
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    String language = 'en',
    bool established = false,
  }) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final activation = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'state': 'READY',
          'setupId': '00000000-0000-4000-8000-000000000099',
        }),
        200,
      ),
    );
    Widget setup(bool only) => PosFirstRun(
      enrollmentOnly: only,
      service: enrollment,
      activationClient: activation,
    );
    await tester.pumpWidget(
      PosLocale(
        language: language,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => LicenseHost(
            navigatorKey: navigator,
            license: license,
            setupBuilder: setup,
            child: child!,
          ),
          home: established
              ? const Scaffold(
                  body: TextField(key: Key('existingDraft'), controller: null),
                )
              : setup(false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSetup(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('licenseSetup')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'მოწყობილობის კოდი'), findsOneWidget);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'მოწყობილობის კოდი'),
      'ABCD-EFGH-IJKL',
    );
    await tester.tap(find.text('მოწყობილობის დაკავშირება'));
    await tester.pump();
  }

  for (final language in ['en', 'ka']) {
    testWidgets(
      '$language clean install exposes explicit setup and Back keeps sales blocked',
      (tester) async {
        await pump(tester, language: language);
        expect(
          find.text(
            language == 'en' ? 'Set up this POS' : 'POS-ის დაკავშირება',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'en'
                ? 'Online verification required'
                : 'საჭიროა ონლაინ შემოწმება',
          ),
          findsNothing,
        );
        expect(
          find.text(
            language == 'en' ? 'Purchase / renew' : 'შეძენა / განახლება',
          ),
          findsNothing,
        );
        await openSetup(tester);
        await expectLater(
          license.operation('createOrder', () async => 1),
          throwsStateError,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('licenseSetup')), findsOneWidget);
        expect(enrollment.calls, 0);
        expect(license.calls, 0);
        expect(EdgeDeviceCredentialStore.hasCredential, false);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'successful first enrollment immediately verifies and continues Manager setup',
    (tester) async {
      await pump(tester);
      await openSetup(tester);
      await submit(tester);
      expect(enrollment.calls, 1);
      await tester.tap(find.text('უკავშირდება…'));
      await tester.pump();
      expect(enrollment.calls, 1);
      await saveIdentity(tester);
      enrollment.pending!.complete(
        const PosEnrollmentResult(PosEnrollmentStatus.connected),
      );
      await tester.pumpAndSettle();
      expect(license.calls, 1);
      expect(license.busy, true);
      await expectLater(
        license.operation('createOrder', () async => 1),
        throwsStateError,
      );
      license.pending!.complete('VALID');
      await tester.pumpAndSettle();
      expect(find.text('Manager-ის შექმნა'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'მოწყობილობის კოდი'), findsNothing);
      await tester.tap(find.text('Manager-ის შექმნა'));
      await tester.pumpAndSettle();
      expect(find.byType(PosManagerRegistrationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed enrollment retains code and retry; pending enrollment cannot dismiss or double-submit',
    (tester) async {
      await pump(tester);
      await openSetup(tester);
      await submit(tester);
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'მოწყობილობის კოდი'),
        findsOneWidget,
      );
      enrollment.pending!.complete(
        const PosEnrollmentResult(
          PosEnrollmentStatus.rejected,
          message: 'Synthetic expired code',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic expired code'), findsOneWidget);
      expect(find.text('ABCD-EFGH-IJKL'), findsOneWidget);
      expect(license.calls, 0);
      expect(EdgeDeviceCredentialStore.hasCredential, false);
      await expectLater(license.requireSale(), throwsStateError);
      await tester.tap(find.text('მოწყობილობის დაკავშირება'));
      await tester.pump();
      expect(enrollment.calls, 2);
      enrollment.pending!.complete(
        const PosEnrollmentResult(
          PosEnrollmentStatus.unreachable,
          message: 'Synthetic network outage',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic network outage'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('licenseSetup')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed explicit reconnect and cancel preserve enrollment and business records',
    (tester) async {
      await saveIdentity(tester);
      await tester.runAsync(() async {
        await DatabaseCore.settingsBox!.put('setupComplete', true);
        await DatabaseCore.settingsBox!.put(
          'businessSentinel',
          'existing bill',
        );
      });
      final before = File(
        '${directory.path}/edge_device.json',
      ).readAsStringSync();
      await pump(tester, established: true);
      await openSetup(tester);
      await submit(tester);
      enrollment.pending!.complete(
        const PosEnrollmentResult(
          PosEnrollmentStatus.conflict,
          message: 'Synthetic foreign-venue refusal',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic foreign-venue refusal'), findsOneWidget);
      expect(license.calls, 0);
      expect(
        File('${directory.path}/edge_device.json').readAsStringSync(),
        before,
      );
      expect(
        DatabaseCore.settingsBox!.get('businessSentinel'),
        'existing bill',
      );
      await expectLater(
        license.operation('addItem', () async => 1),
        throwsStateError,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Reconnect this POS'), findsOneWidget);
      expect(license.lease.allowed, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final result in ['VALID', 'REVOKED']) {
    testWidgets(
      'established restaurant reconnect keeps drafts/data and obeys $result verification',
      (tester) async {
        await saveIdentity(tester);
        await tester.runAsync(() async {
          await DatabaseCore.settingsBox!.put('setupComplete', true);
          await DatabaseCore.settingsBox!.put('businessSentinel', {
            'gross': 1000,
            'advance': 100,
            'collection': 900,
          });
        });
        await pump(tester, established: true);
        await tester.tap(find.text('Records and existing bills'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('existingDraft')),
          'retained draft',
        );
        expect(find.text('Reconnect this POS'), findsOneWidget);
        await openSetup(tester);
        await submit(tester);
        await saveIdentity(tester);
        enrollment.pending!.complete(
          const PosEnrollmentResult(PosEnrollmentStatus.connected),
        );
        await tester.pumpAndSettle();
        expect(license.calls, 1);
        await expectLater(license.requireSale(), throwsStateError);
        license.pending!.complete(result);
        await tester.pumpAndSettle();
        if (result == 'REVOKED') {
          await expectLater(
            license.operation('createOrder', () async => 1),
            throwsStateError,
          );
          await tester.tap(find.text('Records and existing bills'));
          await tester.pumpAndSettle();
        }
        expect(find.text('retained draft'), findsOneWidget);
        expect(
          DatabaseCore.settingsBox!.get('businessSentinel')['collection'],
          900,
        );
        expect(EdgeDeviceCredentialStore.venueId, 'fixture-venue');
        expect(find.byType(PosFirstRun), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
