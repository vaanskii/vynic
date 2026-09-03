import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

/// The POS's transient messages.
///
/// They used to be saturated blocks in a palette nothing else on the product
/// used, and two of them in quick succession landed on exactly the same spot.

Future<void> _loadRealFont() async {
  final data = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
}

late BuildContext _host;

Future<void> _pumpHost(WidgetTester tester, {Size? size}) async {
  final window = size ?? const Size(1200, 720);
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: window),
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: VynicFloorTokens.page,
          body: Builder(
            builder: (context) {
              _host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
}

/// Lets every toast finish and remove itself.
///
/// A toast owns an `AnimationController` driven by the overlay's ticker, so a
/// test that ends mid-flight tears the overlay down with a live ticker still on
/// it. Draining is the test's job, not a defect in the toast.
Future<void> _drain(WidgetTester tester) async {
  // In slices: the toast awaits its entrance, then a delay, then its exit, so
  // one long pump satisfies only the first of the three.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
  await tester.pumpAndSettle();
  // `OverlayEntry.remove()` only marks the overlay dirty; one more frame is
  // what actually takes the card off the tree.
  await tester.pump();
}

/// The card itself: the outermost `Container` that carries the panel fill.
Container _card(WidgetTester tester, {int at = 0}) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.color == VynicFloorTokens.panel &&
            decoration.boxShadow != null;
      })
      .elementAt(at);
}

void main() {
  setUpAll(_loadRealFont);

  testWidgets('a toast is a panel in the venue palette, not a coloured block', (
    tester,
  ) async {
    await _pumpHost(tester);
    unawaited(showSuccessToast(_host, 'შეკვეთა განახლდა'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('შეკვეთა განახლდა'), findsOneWidget);

    final decoration = _card(tester).decoration as BoxDecoration;
    expect(decoration.color, VynicFloorTokens.panel);
    expect(
      (decoration.border as Border).top.color,
      VynicFloorTokens.panelBorder,
    );

    await _drain(tester);
  });

  testWidgets('the message is readable, not tone-coloured on a tinted card', (
    tester,
  ) async {
    // The tone belongs on the icon. A whole card in danger red makes the
    // sentence harder to read at exactly the moment it matters most.
    await _pumpHost(tester);
    unawaited(showErrorToast(_host, 'მაგიდა დაკავებულია'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final text = tester.widget<Text>(find.text('მაგიდა დაკავებულია'));
    expect(text.style?.color, VynicFloorTokens.text);

    await _drain(tester);
  });

  testWidgets('each style carries its own tone on the icon', (tester) async {
    await _pumpHost(tester);

    unawaited(showSuccessToast(_host, 'ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
      VynicFloorTokens.successText,
    );

    await _drain(tester);
  });

  testWidgets('a second toast stacks below the first, not on top of it', (
    tester,
  ) async {
    // A POS produces these in bursts — „order updated", then „printed". Both
    // used to be inserted at the same offset, so the first was unreadable and
    // the second looked like a rendering fault.
    await _pumpHost(tester);

    unawaited(showSuccessToast(_host, 'პირველი'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    unawaited(
      showPosToast(context: _host, message: 'მეორე', style: PosToastStyle.info),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final first = tester.getRect(find.text('პირველი'));
    final second = tester.getRect(find.text('მეორე'));

    expect(find.text('პირველი'), findsOneWidget);
    expect(find.text('მეორე'), findsOneWidget);
    expect(
      second.top,
      greaterThan(first.bottom),
      reason: 'the second toast overlaps the first',
    );

    await _drain(tester);
  });

  testWidgets('a toast never intercepts a tap meant for the screen', (
    tester,
  ) async {
    // It appears over a live floor screen unannounced. Blocking a button
    // underneath it — for two seconds, in the middle of service — is worse
    // than anything it could be telling anyone.
    await _pumpHost(tester);
    unawaited(showSuccessToast(_host, 'ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final ignorePointer = tester.widget<IgnorePointer>(
      find
          .ancestor(of: find.text('ok'), matching: find.byType(IgnorePointer))
          .first,
    );
    expect(ignorePointer.ignoring, isTrue);

    await _drain(tester);
  });

  testWidgets('it fits on the smallest supported terminal', (tester) async {
    await _pumpHost(tester, size: const Size(1200, 720));
    unawaited(
      showPosToast(
        context: _host,
        message:
            'შეკვეთა #1756 გადავიდა მაგიდაზე „ფანჯარასთან" — '
            'მაგიდა 7 გათავისუფლდა და დახურულია',
        style: PosToastStyle.info,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(_card(tester).constraints, isNull);

    await _drain(tester);
  });

  testWidgets('it goes away on its own and takes its overlay with it', (
    tester,
  ) async {
    await _pumpHost(tester);
    unawaited(showSuccessToast(_host, 'ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ok'), findsOneWidget);

    await _drain(tester);
    expect(find.text('ok'), findsNothing);
  });
}
