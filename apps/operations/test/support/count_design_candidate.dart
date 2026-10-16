import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// Isolated review candidate. It is not wired into POS routes or persistence.
@Preview(
  name: 'Count composition — 1024',
  group: 'POS design review',
  size: Size(1024, 768),
)
Widget countDesignCandidatePreview({
  bool empty = false,
  bool longContent = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansGeorgian',
    colorScheme: ColorScheme.fromSeed(
      seedColor: VynicFloorTokens.accentStrong,
      surface: Colors.white,
    ),
  ),
  home: CountDesignCandidate(empty: empty, longContent: longContent),
);

class CountDesignCandidate extends StatefulWidget {
  const CountDesignCandidate({
    super.key,
    this.empty = false,
    this.longContent = false,
  });
  final bool empty;
  final bool longContent;
  @override
  State<CountDesignCandidate> createState() => _CountDesignCandidateState();
}

class _CountDesignCandidateState extends State<CountDesignCandidate> {
  static const ink = VynicFloorTokens.text;
  static const muted = VynicFloorTokens.textMuted;
  static const accent = VynicFloorTokens.accentStrong;
  static const line = VynicFloorTokens.panelBorder;
  final quantities = [2, 1, 2];
  final names = ['იმერული ხაჭაპური', 'ცეზარის სალათი', 'ლიმონათი'];
  final prices = [16.0, 18.0, 5.0];
  bool service = false;
  int selected = 0;
  double get subtotal => List.generate(
    3,
    (i) => quantities[i] * prices[i],
  ).fold(0.0, (a, b) => a + b);
  double get total => subtotal * (service ? 1.1 : 1);
  TextStyle type(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = ink,
  }) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.35);
  Widget label(
    String value,
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = ink,
  }) => Text(
    value,
    style: type(size, weight: weight, color: color),
  );
  ButtonStyle button({bool primary = false}) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    textStyle: WidgetStatePropertyAll(
      Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    backgroundColor: primary ? const WidgetStatePropertyAll(accent) : null,
    foregroundColor: WidgetStatePropertyAll(primary ? Colors.white : accent),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: VynicFloorTokens.page,
    body: Column(
      children: [
        _shell(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    label('დათვლა', 26, weight: FontWeight.w800),
                    const SizedBox(width: 14),
                    label('მენიუს შეფასებები', 14, color: muted),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      style: button(),
                      onPressed: () {},
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('ახალი დათვლა'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 260, child: _browser()),
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: line,
                        ),
                        Expanded(
                          child: widget.empty ? _emptyDetail() : _detail(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _shell() => Container(
    color: Colors.white,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                label('vynic', 23, weight: FontWeight.w800, color: accent),
                const SizedBox(width: 10),
                label('POS', 11, weight: FontWeight.w700, color: muted),
                const Spacer(),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 8),
                label('16 ოქტომბერი, 2026', 12, color: muted),
                const SizedBox(width: 20),
                const Icon(Icons.lock_outline, size: 19, color: muted),
                const SizedBox(width: 20),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: VynicFloorTokens.accentSoft,
                  child: Text(
                    'ნ',
                    style: type(13, weight: FontWeight.w700, color: accent),
                  ),
                ),
                const SizedBox(width: 8),
                label('ნინო', 13, weight: FontWeight.w600),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: line),
        SizedBox(
          height: 51,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _nav('მაგიდები', Icons.grid_view_outlined),
                _nav('რეზერვაციები', Icons.event_outlined),
                _nav('დათვლა', Icons.calculate_outlined, active: true),
                _nav('გატანები', Icons.shopping_bag_outlined),
                const Spacer(),
                IconButton(
                  tooltip: 'პარამეტრები',
                  onPressed: () {},
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: line),
      ],
    ),
  );

  Widget _nav(String text, IconData icon, {bool active = false}) => Container(
    height: 51,
    margin: const EdgeInsets.only(right: 28),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: active ? accent : Colors.transparent,
          width: 3,
        ),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: active ? accent : muted),
        const SizedBox(width: 8),
        label(
          text,
          13,
          weight: active ? FontWeight.w800 : FontWeight.w500,
          color: active ? accent : muted,
        ),
      ],
    ),
  );

  Widget _browser() => ColoredBox(
    color: VynicFloorTokens.canvas,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: TextField(
            style: type(13),
            decoration: InputDecoration(
              hintText: 'მომხმარებლის ძებნა',
              hintStyle: type(13, color: muted),
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderSide: const BorderSide(color: line),
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: line),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              label('შენახული', 12, weight: FontWeight.w700, color: muted),
              const Spacer(),
              label(
                widget.empty ? '0' : '3',
                12,
                weight: FontWeight.w700,
                color: muted,
              ),
            ],
          ),
        ),
        if (!widget.empty) ...[
          _estimate(0, 'ნინო საცდელი', '555 000 000', '18:02', '60.00'),
          _estimate(1, 'გიორგი აბაშიძე', '555 000 001', '17:24', '124.50'),
          _estimate(2, 'მარიამ გიორგაძე', '555 000 002', '16:40', '42.00'),
        ],
        const Spacer(),
        const Divider(height: 1, color: line),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              label(
                widget.empty ? '0 შეფასება' : '3 შეფასება',
                12,
                color: muted,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'ყველას წაშლა',
                onPressed: () {},
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _estimate(
    int index,
    String name,
    String phone,
    String time,
    String amount,
  ) => Material(
    color: selected == index ? VynicFloorTokens.accentSoft : Colors.transparent,
    child: InkWell(
      onTap: () => setState(() => selected = index),
      child: Container(
        padding: const EdgeInsets.fromLTRB(17, 18, 20, 18),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected == index ? accent : Colors.transparent,
            ),
            bottom: const BorderSide(color: line, width: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(name, 14, weight: FontWeight.w700),
            const SizedBox(height: 4),
            label(phone, 12, color: muted),
            const SizedBox(height: 12),
            Row(
              children: [
                label('დღეს · $time', 11, color: muted),
                const Spacer(),
                label(
                  '$amount ₾',
                  14,
                  weight: FontWeight.w700,
                  color: selected == index ? accent : ink,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _emptyDetail() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calculate_outlined, size: 36, color: muted),
          const SizedBox(height: 20),
          label('შექმენით პირველი შეფასება', 21, weight: FontWeight.w800),
          const SizedBox(height: 8),
          label(
            'აირჩიეთ კერძები და შეინახეთ მენიუს ღირებულება.',
            14,
            color: muted,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: button(primary: true),
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('ახალი დათვლა'),
          ),
        ],
      ),
    ),
  );

  Widget _detail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(
                    'შეფასება · დღეს, 18:02',
                    11,
                    weight: FontWeight.w600,
                    color: muted,
                  ),
                  const SizedBox(height: 6),
                  label(
                    [
                      'ნინო საცდელი',
                      'გიორგი აბაშიძე',
                      'მარიამ გიორგაძე',
                    ][selected],
                    21,
                    weight: FontWeight.w800,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 15, color: muted),
                      const SizedBox(width: 7),
                      label('555 000 00$selected', 13, color: muted),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'სახელის შეცვლა',
              onPressed: () {},
              icon: const Icon(Icons.edit_outlined, size: 20, color: muted),
            ),
            IconButton(
              tooltip: 'მეტი',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz, size: 22, color: muted),
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: line),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: label(
                'პროდუქტი',
                11,
                weight: FontWeight.w600,
                color: muted,
              ),
            ),
            SizedBox(
              width: 136,
              child: Center(
                child: label(
                  'რაოდენობა',
                  11,
                  weight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Align(
                alignment: Alignment.centerRight,
                child: label(
                  'თანხა',
                  11,
                  weight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: names.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: line),
          itemBuilder: (_, i) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 77),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label(
                          widget.longContent && i == 0
                              ? 'იმერული ხაჭაპური — დამატებითი ყველით და მწვანილით'
                              : names[i],
                          14,
                          weight: FontWeight.w600,
                        ),
                        const SizedBox(height: 5),
                        label(
                          '${prices[i].toStringAsFixed(2)} ₾ / ცალი',
                          12,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 136,
                    height: 48,
                    decoration: BoxDecoration(
                      color: VynicFloorTokens.canvas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: IconButton(
                            tooltip: 'რაოდენობის შემცირება',
                            onPressed: quantities[i] > 0
                                ? () => setState(() => quantities[i]--)
                                : null,
                            icon: const Icon(
                              Icons.remove,
                              size: 18,
                              color: muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: label(
                              '${quantities[i]}',
                              14,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: IconButton(
                            tooltip: 'რაოდენობის გაზრდა',
                            onPressed: () => setState(() => quantities[i]++),
                            icon: const Icon(
                              Icons.add,
                              size: 18,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 104,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: label(
                        '${(prices[i] * quantities[i]).toStringAsFixed(2)} ₾',
                        15,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        decoration: const BoxDecoration(
          color: VynicFloorTokens.canvas,
          border: Border(top: BorderSide(color: line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(
                    'ქვეჯამი  ${subtotal.toStringAsFixed(2)} ₾',
                    12,
                    color: muted,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        height: 32,
                        child: FittedBox(
                          child: Switch(
                            value: service,
                            onChanged: (v) => setState(() => service = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      label('სერვისი 10%', 12, weight: FontWeight.w600),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more, size: 18, color: muted),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                label('სულ', 12, color: muted),
                const SizedBox(height: 3),
                label(
                  '${total.toStringAsFixed(2)} ₾',
                  27,
                  weight: FontWeight.w800,
                ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Row(
          children: [
            TextButton.icon(
              style: button(),
              onPressed: () {},
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: const Text('ნახვა'),
            ),
            TextButton.icon(
              style: button(),
              onPressed: () {},
              icon: const Icon(Icons.print_outlined, size: 20),
              label: const Text('ბეჭდვა'),
            ),
            const Spacer(),
            OutlinedButton(
              style: button(),
              onPressed: () {},
              child: const Text('მენიუს შეცვლა'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: button(primary: true),
              onPressed: () {},
              child: const Text('რეზერვაცია'),
            ),
          ],
        ),
      ),
    ],
  );
}
