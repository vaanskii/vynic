import 'package:vynic/core/ui/pos_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/licensing/license_host.dart';
import 'package:vynic/core/services/licensing/subscription_license.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';

class FakeLicense extends SubscriptionLicense {
  int opens = 0;
  int retries = 0;
  Completer<void>? pending;
  @override
  Future<void> openPurchase() async {
    opens++;
    await pending?.future;
  }

  @override
  Future<void> verify() async {
    retries++;
  }

  void refresh() => notifyListeners();
}

void main() {
  for (final language in ['ka', 'en']) {
    testWidgets(
      '$language restricted screen preserves workspace and never automatically opens website',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final license = FakeLicense()..enabled = true;
        await tester.pumpWidget(
          PosLocale(
            language: language,
            child: MaterialApp(
              home: LicenseHost(
                license: license,
                child: const Scaffold(body: TextField(key: Key('savedDraft'))),
              ),
            ),
          ),
        );
        expect(
          find.text(
            language == 'ka'
                ? 'საჭიროა ონლაინ შემოწმება'
                : 'Online verification required',
          ),
          findsOneWidget,
        );
        expect(license.opens, 0);
        final records = find.text(
          language == 'ka'
              ? 'ისტორია და არსებული ანგარიშები'
              : 'Records and existing bills',
        );
        await tester.tap(records);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('savedDraft')), 'retained');
        license.lease.restrict('EXPIRED');
        license.refresh();
        await tester.pump();
        expect(find.byKey(const Key('savedDraft')), findsNothing);
        await tester.tap(records);
        await tester.pump();
        expect(find.text('retained'), findsOneWidget);
        final purchase = find.text(
          language == 'ka' ? 'შეძენა / განახლება' : 'Purchase / renew',
        );
        license.pending = Completer();
        await tester.tap(purchase);
        await tester.pump();
        await tester.tap(purchase);
        await tester.pump();
        expect(license.opens, 1);
        license.pending!.complete();
        await tester.pump();
        license.refresh();
        await tester.pump();
        expect(license.opens, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'offline countdown and trial warning remain visible without redirect',
    (tester) async {
      final license = FakeLicense()
        ..enabled = true
        ..offline = true;
      license.lease.reason = 'VALID';
      license.lease.remainingMs = 3599000;
      await tester.pumpWidget(
        MaterialApp(
          home: LicenseHost(
            license: license,
            child: const Scaffold(body: Text('history')),
          ),
        ),
      );
      expect(find.textContaining('0:59:59'), findsOneWidget);
      expect(find.text('history'), findsOneWidget);
      expect(license.opens, 0);
    },
  );
  testWidgets(
    'Georgian restricted surface fits compact desktop and captures synthetic proof',
    (tester) async {
      final font = FontLoader('NotoSansGeorgian')
        ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
      await font.load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final license = FakeLicense()..enabled = true;
      license.lease.kind = 'TRIAL';
      license.lease.restrict('EXPIRED');
      final capture = GlobalKey();
      for (final size in [
        const Size(1024, 768),
        const Size(800, 600),
        const Size(480, 480),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: PosTheme.light,
            home: RepaintBoundary(
              key: capture,
              child: LicenseHost(
                license: license,
                child: const Scaffold(body: Text('Synthetic records')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('საცდელი პერიოდი დასრულდა'), findsOneWidget);
        if (Platform.environment['VYNIC_LICENSE_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../docs/proofs/OFFLINE_LICENSE/expired-ka-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    },
  );
}
