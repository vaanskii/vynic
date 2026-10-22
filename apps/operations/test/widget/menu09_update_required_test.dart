import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/widgets/menu_update_required.dart';
import 'package:vynic/core/services/menu/menu_client_compatibility.dart';

void main() {
  tearDown(() => MenuClientCompatibility.updateRequired.value = null);
  for (final width in [600.0, 1024.0]) {
    testWidgets(
      'explicit update state is visible at width $width; recovery UI remains accessible',
      (tester) async {
        tester.view.physicalSize = Size(width, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MenuUpdateRequired(child: child!),
            home: const Scaffold(body: Text('Local data retained')),
          ),
        );
        expect(find.text(MenuClientCompatibility.updateMessage), findsNothing);
        MenuClientCompatibility.observe(426, {'code': 'MENU_UPDATE_REQUIRED'});
        await tester.pump();
        expect(
          find.text(MenuClientCompatibility.updateMessage),
          findsOneWidget,
        );
        expect(find.text('Local data retained'), findsOneWidget);
        expect(tester.takeException(), isNull);
        MenuClientCompatibility.observe(200, {});
        await tester.pump();
        expect(find.text(MenuClientCompatibility.updateMessage), findsNothing);
      },
    );
  }
}
