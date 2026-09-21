import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/screens/venue_setup_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/venue_identity_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';

class _SettingsBox extends Fake implements Box<dynamic> {
  final _stored = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _stored[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _stored[key] = value;
  }

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
  });
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
