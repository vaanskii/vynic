import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/screens/venue_setup_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/venue_identity_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';

class _SettingsBox extends Fake implements Box<dynamic> {
  final _stored = <dynamic, dynamic>{};
  bool failInputSave = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _stored[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (failInputSave && key == 'posOnScreenInputEnabled')
      throw StateError('Synthetic storage failure');
    _stored[key] = value;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> delete(dynamic key) async {
    _stored.remove(key);
  }
}

void main() {
  setUp(() {
    DatabaseCore.settingsBox = _SettingsBox();
  });
  tearDown(() {
    DatabaseCore.settingsBox = null;
    PosInputSettings.active = false;
    PosInputSettings.enabled.value = true;
  });
  for (final width in [375.0, 1024.0]) {
    testWidgets(
      'input choice persists and interrupted setup stays retryable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var completed = false;
        final box = DatabaseCore.settingsBox as _SettingsBox;
        await tester.pumpWidget(
          MaterialApp(
            home: VenueSetupScreen(onCompleted: () => completed = true),
          ),
        );
        final draft = tester
            .widget<VenueIdentityPanel>(find.byType(VenueIdentityPanel))
            .draft;
        draft.name = 'ახალი რესტორანი';
        await tester.pump();
        await tester.ensureVisible(find.text('კლავიატურა'));
        await tester.tap(find.text('კლავიატურა'));
        box.failInputSave = true;
        await tester.ensureVisible(find.text('დაწყება'));
        await tester.tap(find.text('დაწყება'));
        await tester.pumpAndSettle();
        expect(completed, isFalse);
        expect(DatabaseService.isSetupComplete(), isFalse);
        expect(
          find.text('შენახვა ვერ მოხერხდა. სცადეთ ხელახლა.'),
          findsOneWidget,
        );
        box.failInputSave = false;
        await tester.ensureVisible(find.text('დაწყება'));
        await tester.tap(find.text('დაწყება'));
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(SettingsRepository.getPosOnScreenInputEnabled(), isFalse);
        PosInputSettings.load();
        expect(PosInputSettings.enabled.value, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(home: VenueSetupScreen(onCompleted: () {})),
        );
        expect(
          tester
              .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
              .selected,
          {false},
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('first run completes with only a name and no logo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: VenueSetupScreen(onCompleted: () => completed.complete()),
      ),
    );
    expect(
      tester.widget<PosPrimaryButton>(find.byType(PosPrimaryButton)).onTap,
      isNull,
    );
    final panel = tester.widget<VenueIdentityPanel>(
      find.byType(VenueIdentityPanel),
    );
    expect(panel.showLogo, isFalse);
    panel.draft.name = 'ახალი რესტორანი';
    await tester.pump();
    await tester.ensureVisible(find.text('დაწყება'));
    await tester.tap(find.text('დაწყება'));
    await tester.pumpAndSettle();
    expect(completed.isCompleted, isTrue);
    expect(DatabaseService.isSetupComplete(), isTrue);
    expect(DatabaseService.getVenueName(), 'ახალი რესტორანი');
    expect(DatabaseService.getVenueLogoPng(), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
