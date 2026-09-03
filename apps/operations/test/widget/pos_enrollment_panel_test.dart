import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_pos_enrollment_panel.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';

/// The screen a brand-new terminal is set up from.
///
/// Two things are worth holding: that an unenrolled POS says so plainly and
/// offers the one action that fixes it, and that a refusal is reported as a
/// refusal rather than quietly leaving the operator to guess.
class _FakeEnrollment extends PosEnrollmentService {
  _FakeEnrollment(this.result);

  final PosEnrollmentResult result;
  String? serverAddress;
  String? code;

  @override
  Future<PosEnrollmentResult> enroll({
    required String serverAddress,
    required String code,
  }) async {
    this.serverAddress = serverAddress;
    this.code = code;
    return result;
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('enrollment-panel-');
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    EdgeDeviceCredentialStore.resetForTest();
  });

  tearDown(() async {
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  /// The credential store touches the filesystem, and `testWidgets` runs in a
  /// fake-async zone where real I/O never completes. Every store call therefore
  /// goes through `runAsync`.
  Future<void> loadStore(WidgetTester tester) async {
    await tester.runAsync(EdgeDeviceCredentialStore.load);
  }

  Future<void> pump(WidgetTester tester, PosEnrollmentService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 700,
              child: AdminPosEnrollmentPanel(service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an unenrolled terminal says so and offers the fix', (
    tester,
  ) async {
    await loadStore(tester);
    final service = _FakeEnrollment(
      const PosEnrollmentResult(PosEnrollmentStatus.connected),
    );

    await pump(tester, service);

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect this POS to Vynic'), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Enrollment code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connecting reports the venue the code turned out to be for', (
    tester,
  ) async {
    await loadStore(tester);
    final service = _FakeEnrollment(
      const PosEnrollmentResult(
        PosEnrollmentStatus.connected,
        venueName: 'Vankisi',
        backendUrl: 'http://10.0.0.3:3000',
      ),
    );
    await pump(tester, service);

    await tester.enterText(find.byType(TextField).at(0), '10.0.0.3');
    await tester.enterText(find.byType(TextField).at(1), '7k2q-m4xb-9tfr');
    await tester.tap(find.text('Connect this POS to Vynic'));
    await tester.pumpAndSettle();

    expect(service.serverAddress, '10.0.0.3');
    // Typed lowercase, sent as printed.
    expect(service.code, '7K2Q-M4XB-9TFR');
    expect(
      find.text('Connected. This POS is enrolled with Vankisi.'),
      findsOneWidget,
    );
  });

  testWidgets('a refusal is shown, and nothing claims to be connected', (
    tester,
  ) async {
    await loadStore(tester);
    final service = _FakeEnrollment(
      const PosEnrollmentResult(
        PosEnrollmentStatus.rejected,
        message: 'This enrollment code has expired. Ask for a new one.',
      ),
    );
    await pump(tester, service);

    await tester.enterText(find.byType(TextField).at(0), '10.0.0.3');
    await tester.enterText(find.byType(TextField).at(1), 'ZZZZZZZZZZZZ');
    await tester.tap(find.text('Connect this POS to Vynic'));
    await tester.pumpAndSettle();

    expect(
      find.text('This enrollment code has expired. Ask for a new one.'),
      findsOneWidget,
    );
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('an enrolled terminal states what it is, and can re-enrol', (
    tester,
  ) async {
    await loadStore(tester);
    await tester.runAsync(
      () => EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.11111111-1111-4111-8111-111111111111.${'a' * 43}',
        venueId: '22222222-2222-4222-8222-222222222222',
        venueName: 'Vankisi',
      ),
    );
    final service = _FakeEnrollment(
      const PosEnrollmentResult(PosEnrollmentStatus.connected),
    );

    await pump(tester, service);

    expect(find.text('Enrolled'), findsOneWidget);
    expect(find.text('Vankisi'), findsOneWidget);
    expect(find.text('11111111-1111-4111-8111-111111111111'), findsOneWidget);
    // The form is out of the way until it is asked for.
    expect(find.text('Enrollment code'), findsNothing);

    await tester.tap(find.text('Re-enrol this POS'));
    await tester.pumpAndSettle();
    expect(find.text('Enrollment code'), findsOneWidget);
  });

  testWidgets('the panel lays out without overflowing a narrow column', (
    tester,
  ) async {
    await loadStore(tester);
    tester.view.physicalSize = const Size(720, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: AdminPosEnrollmentPanel(
                service: _FakeEnrollment(
                  const PosEnrollmentResult(PosEnrollmentStatus.connected),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
