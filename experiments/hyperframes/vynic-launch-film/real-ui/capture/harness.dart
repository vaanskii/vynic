import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const capOut = '/private/tmp/claude-501/-Users-vaanskii-Developer-vynic/45c00cc0-bb0b-4c1e-9daf-b54e3b6de383/scratchpad/captures-final';

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('$capOut/$name.png'));
}

Widget app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('ka'),
  supportedLocales: const [Locale('ka'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData(fontFamily: 'NotoSansGeorgian', fontFamilyFallback: const ['Roboto']),
  home: home,
);

void dumpTexts(WidgetTester t, [String tag = '']) {
  final seen = <String>{};
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.trim().isNotEmpty) seen.add(s.replaceAll('\n', ' '));
  }
  // ignore: avoid_print
  print('TEXTS[$tag]: ${seen.join(' | ')}');
}

Future<bool> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) { print('MISSING: $text'); return false; }
  final target = last ? f.last : f.first;
  try { await t.ensureVisible(target); await t.pump(const Duration(milliseconds: 200)); } catch (_) {}
  await t.tap(target, warnIfMissed: true);
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  return true;
}

Future<void> tapPlus(WidgetTester t, int index) async {
  final f = find.byIcon(Icons.add);
  if (f.evaluate().length <= index) { print('MISSING plus $index'); return; }
  await t.tap(f.at(index), warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

/// Real POS flow: tile → quantity pad → 1 → დამატება.
Future<void> addItem(WidgetTester t, int index, {String? padShot}) async {
  await tapPlus(t, index);
  if (find.text('დამატება').evaluate().isNotEmpty) {
    await tapText(t, '1', last: true);
    if (padShot != null) await shot(t, padShot);
    await tapText(t, 'დამატება', last: true);
  }
}

/// Let real async work (Hive writes, navigation futures) complete.
Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 3)));
    await t.pump(const Duration(milliseconds: 300));
  }
}

void dumpFamilies(WidgetTester t) {
  final fams = <String>{};
  for (final e in find.byType(RichText).evaluate()) {
    final rt = e.widget as RichText;
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        fams.add('${s.style?.fontFamily}|${s.style?.fontFamilyFallback}');
        s.children?.forEach(walk);
      }
    }
    walk(rt.text);
  }
  print('FAMILIES: $fams');
}

final rects = <String, List<double>>{};
/// Record the on-screen rect (logical px) of a text (or finder) under [key].
void rectOf(WidgetTester t, String key, Finder f, {bool last = false}) {
  if (f.evaluate().isEmpty) { print('NORECT $key'); return; }
  final r = t.getRect(last ? f.last : f.first);
  rects[key] = [r.left, r.top, r.width, r.height].map((v) => double.parse(v.toStringAsFixed(1))).toList();
}
Rect? textRect(WidgetTester t, String s) { final f = find.text(s); return f.evaluate().isEmpty ? null : t.getRect(f.first); }
