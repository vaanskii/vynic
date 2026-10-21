import 'package:flutter/material.dart' hide Badge;
import 'design.dart';
import 'forms.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final small = c.maxWidth < 850;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            padding: small ? 20 : 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (small) ...[
                  Row(
                    children: [
                      Expanded(
                        child: txt('დღის გაყიდვები', size: 12, color: D.muted),
                      ),
                      const Badge('დღეს'),
                    ],
                  ),
                  gap(10),
                  txt('8,450.00 ₾', size: 36, weight: FontWeight.w600),
                  gap(5),
                  Row(
                    children: [
                      txt(
                        '+12.8%',
                        size: 12,
                        color: D.green,
                        weight: FontWeight.w600,
                      ),
                      hgap(7),
                      txt('წინა საქმიან დღესთან', size: 10, color: D.muted),
                    ],
                  ),
                  gap(24),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            txt('დღის გაყიდვები', size: 12, color: D.muted),
                            gap(8),
                            txt(
                              '8,450.00 ₾',
                              size: 38,
                              weight: FontWeight.w600,
                            ),
                            gap(8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.trending_up,
                                  size: 15,
                                  color: D.green,
                                ),
                                hgap(6),
                                txt(
                                  '+12.8%',
                                  size: 12,
                                  color: D.green,
                                  weight: FontWeight.w600,
                                ),
                                hgap(6),
                                txt(
                                  'წინა საქმიან დღესთან',
                                  size: 11,
                                  color: D.muted,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      for (final m in [
                        ('გასავლები', '2,180.00 ₾', 'უკვე გადახდილი'),
                        ('ნაშთი', '6,270.00 ₾', 'გაყიდვები − გასავლები'),
                        ('შეკვეთები', '42', 'დღეს დასრულებული'),
                      ])
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.only(left: 24),
                            decoration: const BoxDecoration(
                              border: Border(left: BorderSide(color: D.line)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                txt(m.$1, size: 12, color: D.muted),
                                gap(12),
                                txt(m.$2, size: 24, weight: FontWeight.w500),
                                gap(12),
                                txt(m.$3, size: 10, color: D.muted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                if (!small) ...[gap(28), const Divider(height: 1), gap(24)],
                Row(
                  children: [
                    Expanded(
                      child: txt(
                        'გაყიდვების დინამიკა',
                        size: 12,
                        weight: FontWeight.w500,
                      ),
                    ),
                    txt('ბოლო 7 საქმიანი დღე', size: 10, color: D.muted),
                  ],
                ),
                gap(12),
                RevenueBars(compact: small),
                if (small) ...[
                  gap(18),
                  const Divider(height: 1),
                  gap(16),
                  Row(
                    children: [
                      Expanded(child: metric('გასავლები', '2,180.00 ₾')),
                      Container(height: 43, width: 1, color: D.line),
                      hgap(20),
                      Expanded(child: metric('ნაშთი', '6,270.00 ₾')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          gap(22),
          if (c.maxWidth > 850)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: operations(context)),
                hgap(22),
                Expanded(flex: 6, child: bookings(context)),
              ],
            )
          else ...[
            operations(context),
            gap(20),
            bookings(context),
          ],
          gap(22),
          if (c.maxWidth > 850)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: planning(context)),
                hgap(22),
                Expanded(flex: 6, child: products()),
              ],
            )
          else ...[
            planning(context),
            gap(20),
            products(),
          ],
          gap(20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ActionButton(
                'მენიუს დათვლა',
                icon: Icons.calculate_outlined,
                onTap: () => openPreviewDialog(context, 'menu'),
              ),
              ActionButton(
                'შენახული მენიუები',
                icon: Icons.bookmark_border,
                onTap: () => openPreviewDialog(context, 'saved-menu'),
              ),
            ],
          ),
        ],
      );
    },
  );
  Widget metric(String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      txt(title, size: 11, color: D.muted),
      gap(5),
      txt(value, size: 19, weight: FontWeight.w600),
    ],
  );
  Widget operations(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(
          'რესტორანი ახლა',
          action: 'მაგიდები',
          onTap: () => onNavigate(1),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            txt('8', size: 34, weight: FontWeight.w600),
            Padding(
              padding: const EdgeInsets.only(bottom: 7, left: 6),
              child: txt('/ 18 მაგიდა დაკავებულია', size: 12, color: D.muted),
            ),
            const Spacer(),
            txt('44%', size: 15, color: D.purple, weight: FontWeight.w600),
          ],
        ),
        gap(15),
        Row(
          children: List.generate(
            18,
            (i) => Expanded(
              child: Container(
                height: 24,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: i < 8 ? D.purple : const Color(0xFFEDE9F2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        gap(17),
        const Divider(height: 1),
        gap(8),
        const KV('ღია შეკვეთების თანხა', '2,300.00 ₾'),
        const KV('წაღების შეკვეთები', '3 მიმდინარე'),
      ],
    ),
  );
  Widget bookings(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      children: [
        SectionHead(
          'მომდევნო რეზერვაციები',
          action: 'ყველა',
          onTap: () => onNavigate(2),
        ),
        for (final r in reservations.take(3))
          bookingRow(context, r, compact: true),
      ],
    ),
  );
  Widget planning(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead(
          'ფინანსური დაგეგმვა',
          sub: 'ოქტომბერი · დაგეგმილი თანხები',
        ),
        planRow(
          context,
          Icons.people_outline,
          'ხელფასები',
          '3,240.00 ₾',
          'დარჩენილი გადასახდელი',
          'payroll',
        ),
        gap(18),
        planRow(
          context,
          Icons.event_repeat_outlined,
          'ვალდებულებები',
          '1,800.00 ₾',
          'დარჩენილი გადასახდელი',
          'obligations',
        ),
        gap(16),
        txt('რეზერვი გასავლად არ ითვლება.', size: 10, color: D.muted),
      ],
    ),
  );
  Widget planRow(
    BuildContext c,
    IconData icon,
    String title,
    String value,
    String sub,
    String target,
  ) => InkWell(
    onTap: () => openPreviewDialog(c, target),
    borderRadius: BorderRadius.circular(8),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: D.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: D.muted),
        ),
        hgap(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt(title, size: 13, weight: FontWeight.w500),
              txt(sub, size: 10, color: D.muted),
            ],
          ),
        ),
        hgap(6),
        txt(value, size: 13, weight: FontWeight.w600),
        hgap(8),
        const Icon(Icons.chevron_right, size: 17, color: D.muted),
      ],
    ),
  );
  Widget products() => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead(
          'პოპულარული პროდუქტები',
          sub: 'დღეს გაყიდული რაოდენობა',
        ),
        for (final r in [
          ('ხინკალი ქალაქური', '120', '240.00 ₾'),
          ('იმერული ხაჭაპური', '24', '432.00 ₾'),
          ('ქათმის მწვადი', '18', '396.00 ₾'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(child: txt(r.$1, size: 12)),
                txt('${r.$2} ც', size: 11, color: D.muted),
                hgap(28),
                SizedBox(
                  width: 80,
                  child: txt(
                    r.$3,
                    size: 12,
                    weight: FontWeight.w500,
                    align: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class RevenueBars extends StatelessWidget {
  const RevenueBars({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    const vals = [.48, .69, .58, .82, .66, .75, .845];
    return SizedBox(
      height: compact ? 112 : 180,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                for (final f in [.0, .5, 1.0])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: f * (compact ? 78 : 146),
                    child: Container(height: 1, color: D.line),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    7,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 20,
                        ),
                        child: FractionallySizedBox(
                          heightFactor: vals[i],
                          alignment: Alignment.bottomCenter,
                          child: Tooltip(
                            message:
                                '${[4800, 6900, 5800, 8200, 6600, 7491, 8450][i]} ₾',
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == 6
                                    ? D.purple
                                    : const Color(0xFFE8E0F4),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          gap(10),
          Row(
            children: List.generate(
              7,
              (i) => Expanded(
                child: txt(
                  i == 6 ? 'დღეს' : '${10 + i} ოქტ',
                  size: 9,
                  color: i == 6 ? D.purple : D.muted,
                  align: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const reservations = [
  ('18:30', 'მარიამ გელაშვილი', '6 სტუმარი', '04, 05', 'დადასტურებული'),
  ('19:00', 'გიორგი ბერიძე', '4 სტუმარი', '08', 'მოლოდინში'),
  ('19:30', 'ანა ქავთარაძე', '8 სტუმარი', '12, 13', 'დადასტურებული'),
  ('20:00', 'დავით აბაშიძე', '2 სტუმარი', '02', 'დადასტურებული'),
  ('20:30', 'თამარ ჯაფარიძე', '10 სტუმარი', '15, 16', 'მოლოდინში'),
  ('21:00', 'ნიკა მაჭავარიანი', '4 სტუმარი', '06', 'დადასტურებული'),
  ('21:30', 'სალომე წერეთელი', '6 სტუმარი', '10, 11', 'დადასტურებული'),
  ('22:00', 'ირაკლი ჯაფარიძე', '2 სტუმარი', '03', 'დადასტურებული'),
];
Widget bookingRow(
  BuildContext context,
  (String, String, String, String, String) r, {
  bool compact = false,
}) => InkWell(
  onTap: () => openPreviewDialog(context, 'reservation-detail'),
  borderRadius: BorderRadius.circular(8),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: D.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: txt(
            r.$1,
            size: 12,
            weight: FontWeight.w500,
            align: TextAlign.center,
          ),
        ),
        hgap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt(r.$2, size: 12, weight: FontWeight.w500),
              gap(3),
              txt('${r.$3} · მაგიდა ${r.$4}', size: 10, color: D.muted),
            ],
          ),
        ),
        if (!compact)
          Badge(
            r.$5,
            color: r.$5 == 'მოლოდინში' ? D.amber : D.green,
            bg: r.$5 == 'მოლოდინში' ? D.amberLight : D.greenLight,
          ),
        hgap(8),
        const Icon(Icons.chevron_right, size: 17, color: D.muted),
      ],
    ),
  ),
);

class TablesView extends StatefulWidget {
  const TablesView({super.key});
  @override
  State<TablesView> createState() => _TablesViewState();
}

class _TablesViewState extends State<TablesView> {
  int section = 0, zone = 0, selected = 4;
  String filter = 'ყველა';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Segments(
              const ['მაგიდები', 'წაღება'],
              selected: section,
              onSelect: (v) => setState(() => section = v),
            ),
            const Spacer(),
            if (c.maxWidth > 600) const Badge('POS · 18:42'),
          ],
        ),
        gap(24),
        if (section == 1)
          takeaway(context)
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < 3; i++)
                TextButton(
                  onPressed: () => setState(() => zone = i),
                  style: TextButton.styleFrom(
                    backgroundColor: zone == i
                        ? Colors.white
                        : Colors.transparent,
                    side: zone == i ? const BorderSide(color: D.line) : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    ['მთავარი დარბაზი', 'ტერასა', 'მეორე სართული'][i],
                    style: ts(
                      12,
                      color: zone == i ? D.ink : D.muted,
                      weight: zone == i ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
          gap(20),
          Row(
            children: [
              txt('8 დაკავებული', size: 11, color: D.purple),
              hgap(20),
              txt('10 თავისუფალი', size: 11, color: D.muted),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'გაფილტვრა',
                initialValue: filter,
                onSelected: (v) => setState(() => filter = v),
                itemBuilder: (context) => [
                  'ყველა',
                  'დაკავებული',
                  'თავისუფალი',
                ].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      txt(filter, size: 11, color: D.muted),
                      hgap(5),
                      const Icon(Icons.filter_list, size: 16, color: D.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
          gap(12),
          if (c.maxWidth > 1000)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tableGrid(4)),
                hgap(24),
                SizedBox(
                  width: 340,
                  child: selected % 3 == 0
                      ? Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              txt(
                                'მაგიდა $selected',
                                size: 22,
                                weight: FontWeight.w600,
                              ),
                              gap(14),
                              const Badge('თავისუფალი'),
                              gap(22),
                              ActionButton(
                                'ახალი შეკვეთა',
                                primary: true,
                                onTap: () =>
                                    openPreviewDialog(context, 'walkin'),
                              ),
                            ],
                          ),
                        )
                      : OrderPanel(table: selected),
                ),
              ],
            )
          else
            tableGrid(c.maxWidth < 480 ? 2 : 3),
          gap(20),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 15, color: D.muted),
              hgap(8),
              Expanded(
                child: txt(
                  'მდგომარეობა ეფუძნება POS-ის ბოლო სინქრონიზაციას.',
                  size: 11,
                  color: D.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Widget tableGrid(int columns) {
    final ids = List.generate(12, (i) => i + 1)
        .where(
          (i) =>
              filter == 'ყველა' ||
              (filter == 'დაკავებული' ? i % 3 != 0 : i % 3 == 0),
        )
        .toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ids.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 158,
      ),
      itemBuilder: (context, index) {
        final i = ids[index];
        final busy = i % 3 != 0;
        return Material(
          color: busy ? const Color(0xFFFAF8FD) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected == i
                  ? D.purple
                  : busy
                  ? const Color(0xFFDFD5EE)
                  : D.line,
              width: selected == i ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('table-$i'),
            onTap: () {
              setState(() => selected = i);
              if (MediaQuery.sizeOf(context).width < 1280) {
                openPreviewDialog(context, busy ? 'order' : 'walkin');
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      txt(
                        i.toString().padLeft(2, '0'),
                        size: 23,
                        weight: FontWeight.w500,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.table_restaurant_outlined,
                        size: 21,
                        color: busy ? D.purple : const Color(0xFFC4BECF),
                      ),
                    ],
                  ),
                  const Spacer(),
                  txt(
                    busy
                        ? '${[185, 240, 0, 286, 180, 0, 412, 260, 0, 395, 342, 0][i - 1]}.00 ₾'
                        : 'თავისუფალი',
                    size: busy ? 17 : 12,
                    color: busy ? D.ink : D.muted,
                    weight: busy ? FontWeight.w600 : FontWeight.w400,
                  ),
                  gap(6),
                  txt(
                    busy ? 'ნინო · ${35 + i * 4} წთ' : '4 ადგილი',
                    size: 10,
                    color: D.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget takeaway(BuildContext context) => Panel(
    child: Column(
      children: [
        SectionHead(
          'მიმდინარე წაღება',
          action: 'დამატება',
          onTap: () => openPreviewDialog(context, 'takeaway'),
        ),
        for (final r in [
          ('18:50', 'შეკვეთა #1042', '3 პოზიცია', 'მზადდება'),
          ('19:10', 'შეკვეთა #1045', '5 პოზიცია', 'მოლოდინში'),
          ('19:20', 'შეკვეთა #1048', '2 პოზიცია', 'მზადდება'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shopping_bag_outlined, color: D.purple),
            title: txt(r.$2, weight: FontWeight.w500),
            subtitle: txt('${r.$1} · ${r.$3}', size: 11, color: D.muted),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPreviewDialog(context, 'order'),
          ),
      ],
    ),
  );
}

class OrderPanel extends StatelessWidget {
  const OrderPanel({super.key, this.table = 4});
  final int table;
  @override
  Widget build(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: txt(
                'მაგიდა ${table.toString().padLeft(2, '0')}',
                size: 22,
                weight: FontWeight.w600,
              ),
            ),
            const Badge('აქტიური'),
          ],
        ),
        gap(6),
        txt('შეკვეთა #1046 · მთავარი დარბაზი', size: 11, color: D.muted),
        gap(18),
        const KV('ოფიციანტი', 'ნინო'),
        const KV('გახსნილია', '17:51 · 51 წთ'),
        gap(12),
        const Divider(height: 1),
        gap(18),
        for (final r in [
          ('ხინკალი ქალაქური', '20 × 2.00 ₾', '40.00 ₾'),
          ('იმერული ხაჭაპური', '2 × 18.00 ₾', '36.00 ₾'),
          ('ქათმის მწვადი', '4 × 22.00 ₾', '88.00 ₾'),
          ('საფერავი · ბოთლი', '2 × 48.00 ₾', '96.00 ₾'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      txt(r.$1, size: 12, weight: FontWeight.w500),
                      gap(4),
                      txt(r.$2, size: 10, color: D.muted),
                    ],
                  ),
                ),
                hgap(8),
                txt(r.$3, size: 12, weight: FontWeight.w500),
              ],
            ),
          ),
        const Divider(height: 1),
        gap(10),
        const KV('პროდუქტების ჯამი', '260.00 ₾'),
        const KV('მომსახურება · 10%', '26.00 ₾'),
        const KV('გადასახდელი', '286.00 ₾', emphasis: true),
        gap(18),
        ActionButton(
          'შეკვეთის რედაქტირება',
          icon: Icons.edit_outlined,
          primary: true,
          onTap: () => openPreviewDialog(context, 'order-edit'),
        ),
        gap(10),
        ActionButton(
          'ჩეკის ბეჭდვა',
          icon: Icons.print_outlined,
          onTap: () => openPreviewDialog(context, 'operation'),
        ),
        gap(8),
        TextButton(
          onPressed: () => openPreviewDialog(context, 'cancel-order'),
          child: Text('შეკვეთის გაუქმება', style: ts(11, color: D.red)),
        ),
      ],
    ),
  );
}

class ReservationsView extends StatefulWidget {
  const ReservationsView({super.key});
  @override
  State<ReservationsView> createState() => _ReservationsViewState();
}

class _ReservationsViewState extends State<ReservationsView> {
  int day = 4, status = 0;
  String search = '';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final small = c.maxWidth < 600;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            padding: small ? 16 : 24,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: txt(
                        'ოქტომბერი 2026',
                        size: 15,
                        weight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      tooltip: 'წინა კვირა',
                      onPressed: () => setState(() => day = 0),
                      icon: const Icon(Icons.chevron_left, size: 20),
                    ),
                    IconButton(
                      tooltip: 'შემდეგი კვირა',
                      onPressed: () => setState(() => day = 6),
                      icon: const Icon(Icons.chevron_right, size: 20),
                    ),
                  ],
                ),
                gap(14),
                Row(
                  children: List.generate(
                    7,
                    (i) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: i == day
                                ? D.purple
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => setState(() => day = i),
                          child: Column(
                            children: [
                              txt(
                                [
                                  'ორშ',
                                  'სამ',
                                  'ოთხ',
                                  'ხუთ',
                                  'პარ',
                                  'შაბ',
                                  'კვი',
                                ][i],
                                size: small ? 9 : 11,
                                color: i == day ? Colors.white : D.muted,
                              ),
                              gap(9),
                              txt(
                                '${12 + i}',
                                size: small ? 19 : 24,
                                color: i == day ? Colors.white : D.ink,
                                weight: FontWeight.w500,
                              ),
                              gap(9),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i == day
                                      ? Colors.white
                                      : i > 1
                                      ? D.purple
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          gap(22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Badge(
                '8 რეზერვაცია',
                color: D.purple,
                bg: D.purpleLight,
                dot: false,
              ),
              const Badge(
                '42 სტუმარი',
                color: D.muted,
                bg: Color(0xFFEEECF1),
                dot: false,
              ),
              const Badge('2 მოლოდინში', color: D.amber, bg: D.amberLight),
            ],
          ),
          gap(20),
          Segments(
            const ['ყველა', 'დადასტურებული', 'მოლოდინში', 'გაუქმებული'],
            selected: status,
            onSelect: (v) => setState(() => status = v),
          ),
          gap(20),
          Panel(
            padding: small ? 16 : 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: txt(
                        '${12 + day} ოქტომბრის სტუმრები',
                        size: 16,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (!small)
                      SizedBox(
                        width: 230,
                        child: TextField(
                          onChanged: (v) => setState(() => search = v),
                          decoration: const InputDecoration(
                            hintText: 'სახელი ან ტელეფონი',
                            prefixIcon: Icon(Icons.search, size: 18),
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                ),
                gap(16),
                if (!small)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: txt('დრო', size: 10, color: D.muted),
                        ),
                        Expanded(
                          flex: 3,
                          child: txt('სტუმარი', size: 10, color: D.muted),
                        ),
                        Expanded(
                          child: txt('რაოდენობა', size: 10, color: D.muted),
                        ),
                        Expanded(
                          child: txt('მაგიდა', size: 10, color: D.muted),
                        ),
                        SizedBox(
                          width: 158,
                          child: txt('სტატუსი', size: 10, color: D.muted),
                        ),
                      ],
                    ),
                  ),
                if (status == 3)
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: txt(
                      'ამ დღეს გაუქმებული რეზერვაციები არ არის.',
                      size: 13,
                      color: D.muted,
                      align: TextAlign.center,
                    ),
                  )
                else
                  for (final r in reservations.where(
                    (r) =>
                        r.$2.contains(search) &&
                        (status == 0 ||
                            r.$5 ==
                                (status == 1 ? 'დადასტურებული' : 'მოლოდინში')),
                  )) ...[
                    const Divider(height: 1),
                    if (small)
                      bookingRow(context, r, compact: true)
                    else
                      InkWell(
                        onTap: () =>
                            openPreviewDialog(context, 'reservation-detail'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: txt(
                                  r.$1,
                                  size: 15,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    txt(
                                      r.$2,
                                      size: 13,
                                      weight: FontWeight.w500,
                                    ),
                                    gap(5),
                                    txt(
                                      'სატესტო ჩანაწერი',
                                      size: 10,
                                      color: D.muted,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: txt(r.$3, size: 12, color: D.muted),
                              ),
                              Expanded(child: txt(r.$4, size: 12)),
                              SizedBox(
                                width: 138,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Badge(
                                    r.$5,
                                    color: r.$5 == 'მოლოდინში'
                                        ? D.amber
                                        : D.green,
                                    bg: r.$5 == 'მოლოდინში'
                                        ? D.amberLight
                                        : D.greenLight,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: D.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          ),
          gap(20),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionButton(
              'სტუმარი რეზერვაციის გარეშე',
              icon: Icons.person_add_alt_outlined,
              onTap: () => openPreviewDialog(context, 'walkin'),
            ),
          ),
        ],
      );
    },
  );
}

class FinancesView extends StatefulWidget {
  const FinancesView({super.key});
  @override
  State<FinancesView> createState() => _FinancesViewState();
}

class _FinancesViewState extends State<FinancesView> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final small = c.maxWidth < 650;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Segments(
                const ['დღეს', 'კვირა', 'თვე', 'პერიოდი'],
                selected: tab,
                onSelect: (v) => setState(() => tab = v),
              ),
              ActionButton(
                '16 ოქტომბერი',
                icon: Icons.calendar_today_outlined,
                onTap: () => openPreviewDialog(context, 'date'),
              ),
            ],
          ),
          gap(24),
          Panel(
            padding: small ? 20 : 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                txt('აღრიცხული ნაშთი', size: 12, color: D.muted),
                gap(9),
                txt(
                  '6,270.00 ₾',
                  size: small ? 34 : 42,
                  weight: FontWeight.w600,
                ),
                gap(8),
                txt(
                  'გაყიდვები − აღრიცხული გასავლები',
                  size: 11,
                  color: D.muted,
                ),
                gap(25),
                Row(
                  children: [
                    Expanded(
                      child: financialMetric(
                        'გაყიდვები',
                        '8,450.00 ₾',
                        D.purple,
                      ),
                    ),
                    Container(width: 1, height: 50, color: D.line),
                    hgap(24),
                    Expanded(
                      child: financialMetric(
                        'გასავლები',
                        '2,180.00 ₾',
                        D.amber,
                      ),
                    ),
                  ],
                ),
                gap(24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 74,
                        child: Container(height: 9, color: D.purple),
                      ),
                      Expanded(
                        flex: 26,
                        child: Container(
                          height: 9,
                          color: const Color(0xFFE5D7BF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          gap(22),
          if (c.maxWidth > 850)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: paymentMethods()),
                hgap(22),
                Expanded(child: expenseTypes(context)),
              ],
            )
          else ...[
            paymentMethods(),
            gap(20),
            expenseTypes(context),
          ],
          gap(22),
          Panel(
            padding: small ? 18 : 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHead(
                  'გაყიდვების ისტორია',
                  sub: 'დადასტურებული გაყიდვები · სრული სინქრონიზაცია',
                ),
                if (!small)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: txt('შეკვეთა / დრო', size: 10, color: D.muted),
                        ),
                        Expanded(
                          child: txt('გადახდა', size: 10, color: D.muted),
                        ),
                        Expanded(
                          child: txt('სტატუსი', size: 10, color: D.muted),
                        ),
                        Expanded(
                          child: txt(
                            'თანხა',
                            size: 10,
                            color: D.muted,
                            align: TextAlign.right,
                          ),
                        ),
                        hgap(24),
                      ],
                    ),
                  ),
                for (final r in [
                  ('#1041', '18:36', 'ბარათი · TBC', '186.00 ₾'),
                  ('#1039', '18:22', 'ნაღდი', '94.00 ₾'),
                  ('#1038', '18:04', 'ბარათი · BOG', '245.00 ₾'),
                  ('#1036', '17:48', 'შერეული', '128.00 ₾'),
                ]) ...[
                  const Divider(height: 1),
                  InkWell(
                    onTap: () => openPreviewDialog(context, 'sale'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                txt(r.$1, size: 13, weight: FontWeight.w600),
                                gap(4),
                                txt(
                                  small ? '${r.$2} · ${r.$3}' : r.$2,
                                  size: 10,
                                  color: D.muted,
                                ),
                              ],
                            ),
                          ),
                          if (!small) ...[
                            Expanded(child: txt(r.$3, size: 12)),
                            const Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Badge('ფისკალური', dot: false),
                              ),
                            ),
                          ],
                          Expanded(
                            child: txt(
                              r.$4,
                              size: 13,
                              weight: FontWeight.w500,
                              align: TextAlign.right,
                            ),
                          ),
                          hgap(12),
                          const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: D.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          gap(22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'ხელფასები',
                icon: Icons.people_outline,
                onTap: () => openPreviewDialog(context, 'payroll'),
              ),
              ActionButton(
                'ვალდებულებები',
                icon: Icons.event_repeat_outlined,
                onTap: () => openPreviewDialog(context, 'obligations'),
              ),
              ActionButton(
                'მომწოდებლების ანგარიშები',
                icon: Icons.local_shipping_outlined,
                onTap: () => openPreviewDialog(context, 'payables'),
              ),
            ],
          ),
          gap(20),
          Panel(
            padding: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHead('ანალიტიკა და ისტორია'),
                for (final (title, key) in [
                  ('პროდუქტების შედეგები', 'products'),
                  ('თანამშრომლების შედეგები', 'staff-results'),
                  ('გაუქმება და აღდგენა', 'lifecycle'),
                  ('დღის ხარჯების ისტორია', 'expenses'),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: txt(title, size: 13),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => openPreviewDialog(context, key),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget financialMetric(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          hgap(6),
          txt(label, size: 11, color: D.muted),
        ],
      ),
      gap(7),
      txt(value, size: 20, weight: FontWeight.w500),
    ],
  );
  Widget paymentMethods() => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('დახურვებზე მიღებული თანხა'),
        for (final r in [
          ('ნაღდი', '2,680.00 ₾'),
          ('ბარათი · TBC', '3,920.00 ₾'),
          ('ბარათი · BOG', '1,350.00 ₾'),
          ('გამოყენებული ავანსი', '500.00 ₾'),
        ])
          KV(r.$1, r.$2),
        gap(8),
        txt(
          'ავანსი ცალკეა ნაჩვენები; ხელახლა მიღება არ არის.',
          size: 10,
          color: D.muted,
        ),
      ],
    ),
  );
  Widget expenseTypes(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(
          'გასავლების კატეგორიები',
          action: 'ისტორია',
          onTap: () => openPreviewDialog(context, 'expenses'),
        ),
        for (final r in [
          ('მომწოდებლები', '1,250.00 ₾'),
          ('ხელფასის გადახდები', '600.00 ₾'),
          ('ვალდებულებები', '200.00 ₾'),
          ('სხვა ხარჯი', '130.00 ₾'),
        ])
          KV(r.$1, r.$2),
        gap(8),
        txt('მხოლოდ შესრულებული გადახდები.', size: 10, color: D.muted),
      ],
    ),
  );
}

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});
  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  int section = 0;
  String query = '';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final small = c.maxWidth < 650;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segments(
            const [
              'მიმოხილვა',
              'მიღებები',
              'ნაშთები',
              'მომწოდებლები',
              'შემადგენლობა',
            ],
            selected: section,
            onSelect: (v) => setState(() => section = v),
          ),
          gap(22),
          if (section == 0) ...[
            Panel(
              padding: small ? 20 : 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHead(
                    'დღიური მარაგები',
                    sub: 'რა მივიღეთ და რას სჭირდება ყურადღება',
                  ),
                  Wrap(
                    spacing: small ? 28 : 80,
                    runSpacing: 20,
                    children: [
                      invMetric('დღეს მიღებული', '1,460.00 ₾', '3 დოკუმენტი'),
                      invMetric(
                        'დაბალი ნაშთი',
                        '3 პროდუქტი',
                        'მინიმალურ ზღვარზე ქვემოთ',
                      ),
                      invMetric(
                        'მომწოდებლების ვალი',
                        '2,850.00 ₾',
                        'შეუსრულებელი გადახდები',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            gap(22),
            Panel(
              padding: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHead(
                    'დაბალი ნაშთი',
                    action: 'ყველა ნაშთი',
                    onTap: () => setState(() => section = 2),
                  ),
                  for (final r in [
                    ('სულგუნი', '2.4 კგ', 'მინ. 5 კგ'),
                    ('პომიდორი', '3.2 კგ', 'მინ. 6 კგ'),
                    ('ლიმონი', '1.1 კგ', 'მინ. 2 კგ'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 37,
                        height: 37,
                        decoration: BoxDecoration(
                          color: D.amberLight,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: D.amber,
                        ),
                      ),
                      title: txt(r.$1, size: 13, weight: FontWeight.w500),
                      subtitle: txt(r.$3, size: 10, color: D.muted),
                      trailing: txt(
                        r.$2,
                        size: 14,
                        color: D.amber,
                        weight: FontWeight.w600,
                      ),
                      onTap: () => openPreviewDialog(context, 'stock'),
                    ),
                ],
              ),
            ),
            gap(22),
            recentReceipts(context),
            gap(20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'გადახდები და დავალიანება',
                  onTap: () => openPreviewDialog(context, 'payables'),
                  icon: Icons.account_balance_wallet_outlined,
                ),
                ActionButton(
                  'მოძრაობების ისტორია',
                  onTap: () => openPreviewDialog(context, 'movements'),
                  icon: Icons.history,
                ),
                ActionButton(
                  'ჩამოწერის ისტორია',
                  onTap: () => openPreviewDialog(context, 'consumption'),
                  icon: Icons.receipt_long_outlined,
                ),
              ],
            ),
          ] else if (section == 1)
            recentReceipts(context)
          else if (section == 2) ...[
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: 'პროდუქტის ძებნა',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            gap(16),
            Panel(
              child: Column(
                children: [
                  const SectionHead(
                    'აქტიური მარაგები',
                    sub: 'ნაშთი · საშუალო მიმდინარე ფასი',
                  ),
                  for (final r in [
                    ('სულგუნი', '2.4 კგ · 18.50 ₾ / კგ'),
                    ('პომიდორი', '3.2 კგ · 4.00 ₾ / კგ'),
                    ('ფქვილი', '28.0 კგ · 2.10 ₾ / კგ'),
                    ('საფერავი · ბოთლი', '24 ც · 22.00 ₾ / ც'),
                  ].where((r) => r.$1.contains(query)))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: txt(r.$1, size: 13, weight: FontWeight.w500),
                      subtitle: txt(r.$2, size: 11, color: D.muted),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => openPreviewDialog(context, 'stock'),
                    ),
                  gap(14),
                  ActionButton(
                    'ახალი პროდუქტი',
                    onTap: () => openPreviewDialog(context, 'stock-form'),
                    icon: Icons.add,
                  ),
                ],
              ),
            ),
          ] else if (section == 3)
            Panel(
              child: Column(
                children: [
                  SectionHead(
                    'მომწოდებლები',
                    action: 'დამატება',
                    onTap: () => openPreviewDialog(context, 'supplier-form'),
                  ),
                  for (final r in [
                    ('აგრო სახლი', '12 პროდუქტი · 1,250.00 ₾ ვალი'),
                    ('ღვინის მარანი', '8 პროდუქტი · 980.00 ₾ ვალი'),
                    ('სასურსათო ბაზარი', '23 პროდუქტი · 620.00 ₾ ვალი'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.local_shipping_outlined,
                        color: D.purple,
                      ),
                      title: txt(r.$1, size: 14, weight: FontWeight.w500),
                      subtitle: txt(r.$2, size: 11, color: D.muted),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => openPreviewDialog(context, 'supplier'),
                    ),
                ],
              ),
            )
          else
            Panel(
              child: Column(
                children: [
                  const SectionHead(
                    'მენიუს შემადგენლობა',
                    sub: 'კერძები, სასმელები და ვარიანტები',
                  ),
                  for (final r in [
                    ('იმერული ხაჭაპური', '5 ინგრედიენტი · 6.40 ₾'),
                    ('საფერავი · ჭიქა', '1 კომპონენტი · 3.30 ₾'),
                    ('ხინკალი ქალაქური', 'შემადგენლობა დასასრულებელია'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: txt(r.$1, size: 14, weight: FontWeight.w500),
                      subtitle: txt(r.$2, size: 11, color: D.muted),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => openPreviewDialog(context, 'recipe'),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
  Widget invMetric(String label, String value, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      txt(label, size: 11, color: D.muted),
      gap(8),
      txt(value, size: 23, weight: FontWeight.w600),
      gap(6),
      txt(sub, size: 10, color: D.muted),
    ],
  );
  Widget recentReceipts(BuildContext context) => Panel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(
          'ბოლო მიღებები',
          action: 'ყველა',
          onTap: () => setState(() => section = 1),
        ),
        for (final r in [
          ('მიღება #028', 'აგრო სახლი · 16 ოქტ, 14:30', '620.00 ₾'),
          ('მიღება #027', 'თვითშესყიდვა · 16 ოქტ, 12:15', '340.00 ₾'),
          ('მიღება #026', 'ღვინის მარანი · 16 ოქტ, 10:40', '500.00 ₾'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: txt(r.$1, size: 13, weight: FontWeight.w500),
            subtitle: txt(r.$2, size: 10, color: D.muted),
            trailing: txt(r.$3, size: 13, weight: FontWeight.w600),
            onTap: () => openPreviewDialog(context, 'receipt'),
          ),
      ],
    ),
  );
}

class ManagementView extends StatefulWidget {
  const ManagementView({super.key});
  @override
  State<ManagementView> createState() => _ManagementViewState();
}

class _ManagementViewState extends State<ManagementView> {
  int section = 0;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Segments(
        const ['გუნდი', 'ანგარიშები', 'აუდიტი', 'პარამეტრები'],
        selected: section,
        onSelect: (v) => setState(() => section = v),
      ),
      gap(24),
      if (section == 0)
        Panel(
          child: Column(
            children: [
              SectionHead(
                'გუნდი',
                action: 'თანამშრომლის დამატება',
                onTap: () => openPreviewDialog(context, 'staff-form'),
              ),
              for (final r in [
                ('ნინო მაისურაძე', 'მენეჯერი', 'ნმ'),
                ('გიორგი ლომიძე', 'ზედამხედველი', 'გლ'),
                ('ანა კობახიძე', 'ოფიციანტი', 'აკ'),
                ('დავით ბერიძე', 'ოფიციანტი', 'დბ'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: D.purpleLight,
                    child: txt(r.$3, size: 12, color: D.purple),
                  ),
                  title: txt(r.$1, size: 14, weight: FontWeight.w500),
                  subtitle: txt(r.$2, size: 11, color: D.muted),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => openPreviewDialog(context, 'staff'),
                ),
            ],
          ),
        )
      else if (section == 1)
        Panel(
          child: Column(
            children: [
              const SectionHead('ანგარიშები და გაყიდვები'),
              for (final (title, key) in [
                ('დღის ანგარიში', 'report'),
                ('თვიური გაყიდვები', 'monthly-sales'),
                ('პროდუქტების შედეგები', 'products'),
                ('თანამშრომლების შედეგები', 'staff-results'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: txt(title, size: 14),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPreviewDialog(context, key),
                ),
            ],
          ),
        )
      else if (section == 2)
        Panel(
          child: Column(
            children: [
              SectionHead(
                'აქტივობის ჟურნალი',
                action: 'ფილტრები',
                onTap: () => openPreviewDialog(context, 'audit-filter'),
              ),
              for (final r in [
                ('18:36', 'გაყიდვა დაფიქსირდა', 'შეკვეთა #1041 · POS'),
                ('18:24', 'რეზერვაცია დადასტურდა', 'მარიამ გელაშვილი · ნინო'),
                ('18:12', 'ჩეკი დაიბეჭდა', 'შეკვეთა #1039 · POS'),
                ('17:52', 'ხელფასის გადახდა ჩაიწერა', '600.00 ₾ · მენეჯერი'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: txt(r.$1, size: 11, color: D.muted),
                  title: txt(r.$2, size: 13),
                  subtitle: txt(r.$3, size: 11, color: D.muted),
                  onTap: () => openPreviewDialog(context, 'audit'),
                ),
            ],
          ),
        )
      else
        Panel(
          child: Column(
            children: [
              const SectionHead('რესტორნის პარამეტრები'),
              for (final (title, sub, key) in [
                (
                  'რესტორნის პროფილი',
                  'მთვარე · სატესტო სივრცე',
                  'venue-profile',
                ),
                ('საქმიანი დღე', '16 ოქტომბერი · ღია', 'business-day'),
                ('მომსახურება', '10% · GEL', 'service'),
                (
                  'მოთხოვნების მდგომარეობა',
                  'POS-თან მიწოდების ისტორია',
                  'operation',
                ),
                ('გარეგნობა', 'ღია / მუქი / სისტემური', 'appearance'),
                ('სესია და რესტორნის შეცვლა', 'ნინო · მენეჯერი', 'profile'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: txt(title, size: 13, weight: FontWeight.w500),
                  subtitle: txt(sub, size: 11, color: D.muted),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => openPreviewDialog(context, key),
                ),
            ],
          ),
        ),
    ],
  );
}
