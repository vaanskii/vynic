import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/print_jobs.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import '../support/pos02_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos02Fixture f;
  final repaint = GlobalKey();
  Widget surface(Widget child) => PosLocale(
    language: 'en',
    child: RepaintBoundary(
      key: repaint,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: child),
      ),
    ),
  );
  Future<void> advance(WidgetTester tester) async {
    for (var n = 0; n < 8; n++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.view(font.buffer)))).load();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_widget_');
    f = Pos02Fixture();
    await f.open(root.path);
    await f.seed();
    f.mode = 'flush-error';
    await PrintQueue.enqueue(f.job(target: PrintQueueTarget.receipt));
    await f.dispatch();
    PrintQueue.stop();
  });
  tearDown(() async {
    await f.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'kitchen reprint offers Run/Cancel only and cancel writes nothing',
    (tester) async {
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      await tester.runAsync(() async {
        await PrintQueue.enqueue(
          f.job(id: 'kitchen-simple', target: PrintQueueTarget.kitchen),
        );
        await f.dispatch();
        PrintQueue.stop();
      });
      await tester.pumpWidget(surface(const PrintJobsDialog()));
      await tester.tap(
        find.byKey(const ValueKey('print-reprint-kitchen-simple')),
      );
      await tester.pumpAndSettle();
      expect(find.text('გაშვება'), findsOneWidget);
      expect(find.text('გაუქმება'), findsOneWidget);
      expect(find.byType(PosOnScreenTextField), findsNothing);
      final before = f.transmitted.length;
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(PrintJobRepository.read('kitchen-simple')!.attempts, hasLength(1));
      expect(f.transmitted.length, before);
    },
  );
  testWidgets('kitchen Run double submit creates one labeled audited copy', (
    tester,
  ) async {
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
    await tester.runAsync(() async {
      await PrintQueue.enqueue(
        f.job(id: 'kitchen-run', target: PrintQueueTarget.kitchen),
      );
      await f.dispatch();
      PrintQueue.stop();
    });
    await tester.pumpWidget(surface(const PrintJobsDialog()));
    await tester.tap(find.byKey(const ValueKey('print-reprint-kitchen-run')));
    await tester.pumpAndSettle();
    final submit = tester
        .widget<FilledButton>(find.byKey(const ValueKey('print-action-submit')))
        .onPressed!;
    await tester.runAsync(() async {
      submit();
      submit();
    });
    await advance(tester);
    await tester.pumpAndSettle();
    final job = PrintJobRepository.read('kitchen-run')!;
    expect(job.attempts, hasLength(2));
    expect(job.audit.last['actorId'], 'synthetic-operator');
    expect(job.audit.last['reason'], PrintReconciliation.kitchenCopyReason);
    expect(job.state, PrintJobState.reprint);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unconfigured policy exposes uncertainty but disables paper/reprint actions',
    (tester) async {
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      await tester.pumpWidget(surface(const PrintJobsDialog()));
      expect(find.text('Outcome unknown — check paper'), findsOneWidget);
      expect(
        find.text('Operator reconciliation policy is not configured.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('print-reprint-synthetic-pos02-job')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'blank reason and cancel do not admit a copy; a double submit admits exactly one',
    (tester) async {
      await tester.pumpWidget(surface(const PrintJobsDialog()));
      await tester.tap(
        find.byKey(const ValueKey('print-reprint-synthetic-pos02-job')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-action-submit')));
      await tester.pump();
      expect(find.text('Enter a reason (3–500 characters)'), findsOneWidget);
      expect(PrintJobRepository.all().single.attempts, hasLength(1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(PrintJobRepository.all().single.attempts, hasLength(1));
      await tester.tap(
        find.byKey(const ValueKey('print-reprint-synthetic-pos02-job')),
      );
      await tester.pumpAndSettle();
      tester
              .widget<PosOnScreenTextField>(find.byType(PosOnScreenTextField))
              .controller
              .text =
          'synthetic paper missing';
      final submit = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('print-action-submit')),
          )
          .onPressed!;
      await tester.runAsync(() async {
        submit();
        submit();
      });
      await advance(tester);
      expect(PrintJobRepository.all().single.attempts, hasLength(2));
      expect(
        PrintJobRepository.all().single.audit.where(
          (e) => e['action'] == 'reprint',
        ),
        hasLength(1),
      );
      expect(f.transmitted, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a waiter with printingStaff policy can reach a sent ticket from Home notice',
    (tester) async {
      await tester.runAsync(() async {
        await PrintReconciliation.confirm(
          PrintJobRepository.all().single,
          'synthetic paper checked',
          'synthetic-confirm',
        );
        await PrintQueue.enqueue(f.job(id: 'sent-job'));
        f.mode = 'sent';
        await f.dispatch();
        PrintQueue.stop();
        final waiter = User(
          username: 'synthetic-waiter',
          pinCode: '1234',
          role: 'waiter',
        );
        await DatabaseCore.userBox!.put(waiter.username, waiter);
        PosSession.start(waiter);
        PrintReconciliation.policy = PrintReconciliationPolicy.printingStaff;
      });
      await tester.pumpWidget(
        surface(const PrintJobsNotice(onlyAttention: true)),
      );
      expect(find.byKey(const ValueKey('print-jobs-open')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-jobs-open')));
      await tester.pumpAndSettle();
      expect(find.text('Sent — check paper'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('print-confirm-sent-job')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Receipt printed'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'existing Sale/manual copy prompt records a reason and refuses unconfigured policy',
    (tester) async {
      String? reason;
      await tester.pumpWidget(
        surface(
          TextButton(
            onPressed: () async {
              reason = await requestLabeledPrintCopyReason(
                tester.element(find.byType(TextButton).first),
              );
            },
            child: const Text('Existing copy'),
          ),
        ),
      );
      await tester.tap(find.text('Existing copy'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('avoid preparing the meal twice'),
        findsOneWidget,
      );
      tester
              .widget<PosOnScreenTextField>(find.byType(PosOnScreenTextField))
              .controller
              .text =
          'synthetic copy reason';
      await tester.tap(find.byKey(const ValueKey('print-action-submit')));
      await tester.pumpAndSettle();
      expect(reason, 'synthetic copy reason');
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      await tester.tap(find.text('Existing copy'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('print-action-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(1024, 768),
    const Size(640, 720),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'print list and copy dialog fit $size with long labels and history',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          final body = PrintJobRepository.all().single.toMap();
          body['label'] =
              'Kitchen / ${List.filled(12, 'Synthetic long ticket label').join(' ')}';
          body['label'] = (body['label'] as String).substring(0, 300);
          body['attempts'].last['detail'] = List.filled(
            20,
            'Synthetic diagnostic history; inspect paper before a copy.',
          ).join(' ');
          await DatabaseCore.metaBox!.put(
            PrintJobRepository.key(body['id']),
            body,
          );
        });
        await tester.pumpWidget(surface(const PrintJobsDialog()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('History and details'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['POS02_SCREENSHOT_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final boundary =
                repaint.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$directory/print-list-${size.width.toInt()}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(
          find.byKey(const ValueKey('print-reprint-synthetic-pos02-job')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
