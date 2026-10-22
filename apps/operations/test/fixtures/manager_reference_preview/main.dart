import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'design.dart';
import 'screens.dart';
import 'forms.dart';

void main() => runApp(const ManagerPreview());

class ManagerPreview extends StatelessWidget {
  const ManagerPreview({
    super.key,
    this.initialPage = 0,
    this.stale = false,
    this.initialDialog,
    this.textScale,
  });
  final int initialPage;
  final bool stale;
  final String? initialDialog;
  final double? textScale;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vynic Manager — design preview',
    debugShowCheckedModeBanner: false,
    theme: previewTheme(),
    builder: (context, child) => textScale == null
        ? child!
        : MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale!)),
            child: child!,
          ),
    home: PreviewShell(
      initialPage: initialPage,
      stale: stale,
      initialDialog: initialDialog,
    ),
  );
}

const navNames = [
  'მიმოხილვა',
  'მაგიდები',
  'რეზერვაციები',
  'ფინანსები',
  'მარაგები',
  'მართვა',
];
const navIcons = [
  Icons.space_dashboard_outlined,
  Icons.table_restaurant_outlined,
  Icons.calendar_month_outlined,
  Icons.account_balance_wallet_outlined,
  Icons.inventory_2_outlined,
  Icons.tune_rounded,
];

class PreviewShell extends StatefulWidget {
  const PreviewShell({
    super.key,
    required this.initialPage,
    required this.stale,
    this.initialDialog,
  });
  final int initialPage;
  final bool stale;
  final String? initialDialog;
  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  late int page;
  late bool stale;
  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
    stale = widget.stale;
    if (widget.initialDialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openPreviewDialog(context, widget.initialDialog!);
      });
    }
  }

  void navigate(int value) {
    setState(() => page = value);
  }

  void notice(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: 440,
    ),
  );
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
          navigate(0),
      const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
          navigate(1),
      const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
          navigate(2),
      const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () =>
          navigate(3),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
          openPreviewDialog(context, 'reservation'),
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final mobile = c.maxWidth < 700;
          final full = c.maxWidth >= 1100;
          return Scaffold(
            body: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  if (!mobile) sidebar(full),
                  Expanded(
                    child: Column(
                      children: [
                        topbar(mobile),
                        Expanded(
                          child: SingleChildScrollView(
                            key: ValueKey('page-$page'),
                            padding: EdgeInsets.fromLTRB(
                              mobile ? 20 : 32,
                              mobile ? 20 : 28,
                              mobile ? 20 : 32,
                              32,
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1360,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    heading(mobile),
                                    gap(mobile ? 20 : 24),
                                    if (stale) ...[staleBanner(), gap()],
                                    switch (page) {
                                      0 => DashboardView(onNavigate: navigate),
                                      1 => const TablesView(),
                                      2 => const ReservationsView(),
                                      3 => const FinancesView(),
                                      4 => const InventoryView(),
                                      _ => const ManagementView(),
                                    },
                                    gap(24),
                                    const Center(child: PreviewNote()),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: mobile ? bottomNav() : null,
          );
        },
      ),
    ),
  );
  Widget sidebar(bool full) => Container(
    width: full ? 224 : 82,
    decoration: const BoxDecoration(
      color: Color(0xFFFCFBFD),
      border: Border(right: BorderSide(color: D.line)),
    ),
    child: Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(full ? 24 : 18, 30, 18, 32),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: D.purple,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Center(
                  child: Text(
                    'v',
                    style: TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
              if (full) ...[
                hgap(10),
                Text('vynic', style: ts(27, weight: FontWeight.w600)),
                hgap(7),
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: txt('manager', size: 10, color: D.muted),
                ),
              ],
            ],
          ),
        ),
        if (full)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: txt(
                'სამუშაო სივრცე',
                size: 10,
                color: D.muted,
                weight: FontWeight.w500,
              ),
            ),
          ),
        for (int i = 0; i < navNames.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: full ? 12 : 10,
              vertical: 3,
            ),
            child: Tooltip(
              message: navNames[i],
              child: TextButton(
                key: ValueKey('nav-$i'),
                style: TextButton.styleFrom(
                  backgroundColor: page == i
                      ? D.purpleLight
                      : Colors.transparent,
                  foregroundColor: page == i ? D.purple : D.muted,
                  padding: EdgeInsets.symmetric(
                    horizontal: full ? 14 : 12,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => navigate(i),
                child: Row(
                  mainAxisAlignment: full
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(navIcons[i], size: 21),
                    if (full) ...[
                      hgap(13),
                      txt(
                        navNames[i],
                        size: 13,
                        color: page == i ? D.purple : D.muted,
                        weight: page == i ? FontWeight.w600 : FontWeight.w400,
                      ),
                      if (i == 2) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: txt('8', size: 10, color: D.muted),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        const Spacer(),
        if (full) ...[
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: D.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    hgap(7),
                    txt('POS სინქრონიზებულია', size: 11, color: D.muted),
                  ],
                ),
                gap(6),
                txt('ბოლო განახლება 18:42', size: 10, color: D.muted),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: InkWell(
            onTap: () => openPreviewDialog(context, 'profile'),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisAlignment: full
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: D.purpleLight,
                  child: Text(
                    'ნ',
                    style: TextStyle(color: D.purple, fontSize: 15),
                  ),
                ),
                if (full) ...[
                  hgap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        txt('ნინო', size: 12, weight: FontWeight.w600),
                        txt('მენეჯერი', size: 10, color: D.muted),
                      ],
                    ),
                  ),
                  const Icon(Icons.unfold_more, size: 16, color: D.muted),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget topbar(bool mobile) => Container(
    height: mobile ? 62 : 70,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 20 : 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: D.line)),
    ),
    child: Row(
      children: [
        if (mobile) ...[
          Text('vynic', style: ts(22, weight: FontWeight.w600)),
          hgap(14),
          Container(height: 20, width: 1, color: D.line),
          hgap(14),
        ],
        const Icon(Icons.storefront_outlined, size: 17, color: D.muted),
        hgap(8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt('მთვარე', size: 13, weight: FontWeight.w600, lines: 1),
              txt(
                'სინთეტიკური მონაცემები',
                size: mobile ? 8 : 10,
                color: D.muted,
                lines: 1,
              ),
            ],
          ),
        ),
        if (!mobile) ...[
          const Icon(Icons.circle, size: 5, color: D.green),
          hgap(7),
          txt('საქმიანი დღე ღიაა', size: 11, color: D.muted),
          hgap(22),
        ],
        IconButton(
          tooltip: 'შეტყობინებები',
          onPressed: () => openPreviewDialog(context, 'notifications'),
          icon: const BadgeIcon(),
        ),
        if (mobile)
          IconButton(
            tooltip: 'პროფილი',
            onPressed: () => openPreviewDialog(context, 'profile'),
            icon: const CircleAvatar(
              radius: 15,
              backgroundColor: D.purpleLight,
              child: Text('ნ', style: TextStyle(color: D.purple, fontSize: 13)),
            ),
          ),
      ],
    ),
  );
  Widget heading(bool mobile) {
    final subtitles = [
      'პარასკევი, 16 ოქტომბერი · საქმიანი დღე',
      'რესტორნის მიმდინარე მდგომარეობა',
      'სტუმრები, დრო და მომზადება ერთ სივრცეში',
      'გაყიდვები და აღრიცხული გასავლები',
      'მიღება, ნაშთები და მომწოდებლები',
      'გუნდი, ანგარიშები და პარამეტრები',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (page == 0 && !mobile) ...[
                    txt(
                      'საღამო მშვიდობისა, ნინო',
                      size: mobile ? 12 : 13,
                      color: D.muted,
                    ),
                    gap(5),
                  ],
                  txt(
                    page == 0 ? 'დღის მიმოხილვა' : navNames[page],
                    size: mobile ? 25 : 30,
                    weight: FontWeight.w600,
                  ),
                ],
              ),
            ),
            if (!mobile) headingAction(),
          ],
        ),
        gap(7),
        txt(subtitles[page], size: mobile ? 11 : 12, color: D.muted),
        if (mobile && page > 1 && page < 5) ...[gap(16), headingAction()],
      ],
    );
  }

  Widget headingAction() => switch (page) {
    0 => ActionButton(
      '16 ოქტომბერი, 2026',
      icon: Icons.calendar_today_outlined,
      onTap: () => openPreviewDialog(context, 'date'),
    ),
    1 => ActionButton(
      'ახალი შეკვეთა',
      icon: Icons.add,
      primary: true,
      onTap: () => openPreviewDialog(context, 'walkin'),
    ),
    2 => ActionButton(
      'ახალი რეზერვაცია',
      icon: Icons.add,
      primary: true,
      onTap: () => openPreviewDialog(context, 'reservation'),
    ),
    3 => ActionButton(
      'ხარჯის დამატება',
      icon: Icons.add,
      primary: true,
      onTap: () => openPreviewDialog(context, 'expense'),
    ),
    4 => ActionButton(
      'ახალი მიღება',
      icon: Icons.add,
      primary: true,
      onTap: () => openPreviewDialog(context, 'receiving'),
    ),
    _ => const SizedBox.shrink(),
  };
  Widget bottomNav() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: D.line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            for (final i in [0, 1, 2, 3, 5])
              Expanded(
                child: TextButton(
                  key: ValueKey('nav-$i'),
                  onPressed: () => i == 5 ? openMore() : navigate(i),
                  style: TextButton.styleFrom(
                    foregroundColor: page == i || (page == 4 && i == 5)
                        ? D.purple
                        : D.muted,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        i == 5 ? Icons.grid_view_rounded : navIcons[i],
                        size: 22,
                      ),
                      gap(5),
                      Text(
                        [
                          'მთავარი',
                          'მაგიდები',
                          'ჯავშნები',
                          'ფინანსები',
                          'მარაგები',
                          'მეტი',
                        ][i],
                        style: ts(
                          9,
                          color: page == i || (page == 4 && i == 5)
                              ? D.purple
                              : D.muted,
                          weight: page == i ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  void openMore() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            txt('სამუშაო სივრცე', size: 20, weight: FontWeight.w600),
            gap(16),
            for (final i in [4, 5])
              ListTile(
                leading: Icon(navIcons[i], color: D.purple),
                title: txt(navNames[i], weight: FontWeight.w500),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(c);
                  navigate(i);
                },
              ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined, color: D.purple),
              title: txt('მენიუს დათვლა'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(c);
                openPreviewDialog(context, 'menu');
              },
            ),
          ],
        ),
      ),
    ),
  );
  Widget staleBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: D.amberLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: D.amber, size: 20),
        hgap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt(
                'ნაჩვენებია შენახული მონაცემები',
                size: 13,
                color: D.amber,
                weight: FontWeight.w600,
              ),
              txt(
                'ბოლო სინქრონიზაცია: 18:12 · ახალი ცვლილებები ჯერ არ ჩანს.',
                size: 11,
                color: D.amber,
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() => stale = false),
          child: const Text('განახლება'),
        ),
      ],
    ),
  );
}

class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key});
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Icon(Icons.notifications_none_rounded, size: 22),
      Positioned(
        right: 1,
        top: 0,
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: D.purple,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ],
  );
}
