import 'dart:math' as math;
import 'package:flutter/material.dart' hide Badge;
import 'design.dart';
import 'screens.dart' show OrderPanel;

Future<void> openPreviewDialog(BuildContext context, String kind) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xFF272131).withValues(alpha: .25),
      builder: (c) => PreviewDialog(kind: kind),
    );

class PreviewDialog extends StatefulWidget {
  const PreviewDialog({super.key, required this.kind});
  final String kind;
  @override
  State<PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<PreviewDialog> {
  final form = GlobalKey<FormState>();
  int step = 0, tab = 0;
  bool submitted = false, worked = true;
  String selectedTable = '04';
  final Map<String, TextEditingController> controllers = {};
  TextEditingController controller(String name, String value) =>
      controllers.putIfAbsent(name, () => TextEditingController(text: value));
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get kind => widget.kind;
  String get title => switch (kind) {
    'reservation' => 'ახალი რეზერვაცია',
    'reservation-detail' => 'რეზერვაციის დეტალი',
    'order' => 'შეკვეთის დეტალი',
    'order-edit' => 'შეკვეთის რედაქტირება',
    'walkin' => 'ახალი შეკვეთა',
    'takeaway' => 'წაღების შეკვეთა',
    'expense' => 'ხარჯის დამატება',
    'receiving' => 'ახალი მიღება',
    'receipt' => 'მიღება #028',
    'stock' => 'სულგუნი',
    'stock-form' => 'ახალი პროდუქტი',
    'supplier' => 'აგრო სახლი',
    'supplier-form' => 'ახალი მომწოდებელი',
    'recipe' => 'იმერული ხაჭაპური',
    'payroll' => 'ხელფასები',
    'payroll-staff' => 'ანა კობახიძე',
    'obligations' => 'ვალდებულებები',
    'payables' => 'მომწოდებლების ანგარიშები',
    'payment' => 'გადახდის აღრიცხვა',
    'reserve' => 'თანხის გადადება',
    'compensation' => 'ხელფასის წესი',
    'obligation-form' => 'ახალი ვალდებულება',
    'correction' => 'ჩანაწერის შესწორება',
    'notifications' => 'შეტყობინებები',
    'profile' => 'სესია',
    'venue-profile' => 'რესტორნის პროფილი',
    'staff' => 'თანამშრომლის დეტალი',
    'staff-form' => 'ახალი თანამშრომელი',
    'service' => 'მომსახურების წესი',
    'menu' => 'მენიუს დათვლა',
    'saved-menu' => 'შენახული მენიუები',
    'operation' => 'მოთხოვნის მდგომარეობა',
    'cancel-order' => 'შეკვეთის გაუქმება',
    'sale' => 'გაყიდვა #1041',
    'date' => 'პერიოდის არჩევა',
    'appearance' => 'გარეგნობა',
    'business-day' => 'საქმიანი დღე',
    'movements' => 'მარაგის მოძრაობები',
    'consumption' => 'გაყიდვის ჩამოწერა',
    'products' => 'პროდუქტების შედეგები',
    'staff-results' => 'თანამშრომლების შედეგები',
    'expenses' => 'ხარჯების ისტორია',
    'lifecycle' => 'გაუქმება და აღდგენა',
    'monthly-sales' => 'თვიური გაყიდვები',
    'report' => 'დღის ანგარიში',
    'audit' => 'შეკვეთის აუდიტი',
    'audit-filter' => 'აუდიტის ფილტრები',
    _ => 'დეტალები',
  };
  bool get isForm => [
    'reservation',
    'order-edit',
    'walkin',
    'takeaway',
    'expense',
    'receiving',
    'stock-form',
    'supplier-form',
    'payment',
    'reserve',
    'compensation',
    'obligation-form',
    'correction',
    'venue-profile',
    'staff-form',
    'cancel-order',
    'recipe',
  ].contains(kind);
  String get primaryLabel => kind == 'reservation' && step == 0
      ? 'მაგიდის არჩევა'
      : kind == 'receiving' && step == 0
      ? 'გადახდა და შემოწმება'
      : kind == 'cancel-order'
      ? 'გაუქმების მოთხოვნა'
      : isForm
      ? 'პრევიუს შენახვა'
      : 'დახურვა';
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final small = mq.size.width < 700;
    return Dialog(
      insetPadding: EdgeInsets.all(small ? 12 : 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kind == 'order'
              ? 410
              : kind == 'payroll' || kind == 'obligations'
              ? 880
              : 700,
          maxHeight: math.min(
            840,
            mq.size.height - mq.viewInsets.bottom - (small ? 24 : 64),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(small ? 20 : 28, 18, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        txt(
                          title,
                          size: small ? 20 : 24,
                          weight: FontWeight.w600,
                        ),
                        gap(4),
                        txt(
                          submitted
                              ? 'სინთეტიკური სცენარი · რეალური ცვლილება არ შესრულებულა'
                              : 'დიზაინის პრევიუ · სინთეტიკური მონაცემები',
                          size: 10,
                          color: D.muted,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'დახურვა · Esc',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('dialog-scroll'),
                padding: EdgeInsets.all(small ? 20 : 28),
                child: Form(
                  key: form,
                  child: submitted ? success() : content(),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                small ? 20 : 28,
                14,
                small ? 20 : 28,
                18,
              ),
              child: Row(
                children: [
                  if (isForm && !submitted)
                    Expanded(
                      child: TextButton(
                        onPressed: step > 0
                            ? () => setState(() => step = 0)
                            : () => Navigator.pop(context),
                        child: Text(step > 0 ? 'უკან' : 'გაუქმება'),
                      ),
                    ),
                  if (!isForm || submitted) const Spacer(),
                  hgap(12),
                  Flexible(
                    child: ActionButton(
                      submitted ? 'დახურვა' : primaryLabel,
                      key: const ValueKey('dialog-primary'),
                      primary: true,
                      onTap: submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void submit() {
    if (submitted || !isForm) {
      Navigator.pop(context);
      return;
    }
    if (!(form.currentState?.validate() ?? true)) return;
    if ((kind == 'reservation' || kind == 'receiving') && step == 0) {
      setState(() => step = 1);
      return;
    }
    setState(() => submitted = true);
  }

  Widget success() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Badge('პრევიუ შენახულია'),
      gap(20),
      txt(
        'ეს არის მხოლოდ დიზაინის სცენარი.',
        size: 20,
        weight: FontWeight.w600,
      ),
      gap(10),
      txt(
        'მონაცემები არ გაიგზავნა სერვერზე ან POS-ში. აპის რეალური ბიზნესლოგიკა უცვლელია.',
        size: 13,
        color: D.muted,
      ),
      gap(24),
      if ([
        'reservation',
        'order-edit',
        'walkin',
        'takeaway',
        'cancel-order',
      ].contains(kind)) ...[
        const Divider(),
        gap(16),
        const Badge(
          'POS-ის დადასტურების მოლოდინში',
          color: D.amber,
          bg: D.amberLight,
        ),
        gap(12),
        txt(
          'რეალურ აპში დასრულება გამოჩნდება მხოლოდ POS-ის პასუხის შემდეგ.',
          size: 12,
          color: D.muted,
        ),
        gap(16),
        ActionButton(
          'მოთხოვნის დეტალი',
          onTap: () => openPreviewDialog(context, 'operation'),
        ),
      ],
    ],
  );
  Widget field(
    String label,
    String value, {
    String? hint,
    bool required = true,
    bool number = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        txt(label, size: 12, weight: FontWeight.w500),
        gap(7),
        TextFormField(
          key: ValueKey('field-$label'),
          controller: controller(label, value),
          style: ts(14),
          maxLines: lines,
          obscureText: label == 'PIN',
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : lines > 1
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: lines > 1
              ? TextInputAction.newline
              : TextInputAction.next,
          scrollPadding: const EdgeInsets.all(28),
          decoration: InputDecoration(hintText: hint),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? 'შეავსეთ ეს ველი'
              : number && double.tryParse(v ?? '') == null
              ? 'შეიყვანეთ რიცხვი'
              : null,
        ),
      ],
    ),
  );
  Widget pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, c) => c.maxWidth > 480
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              hgap(18),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, b]),
  );
  Widget help(String s, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? D.amberLight : D.bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline : Icons.lightbulb_outline,
          size: 17,
          color: warning ? D.amber : D.muted,
        ),
        hgap(10),
        Expanded(child: txt(s, size: 11, color: warning ? D.amber : D.muted)),
      ],
    ),
  );
  Widget link(
    String title,
    String target, {
    String? subtitle,
    IconData icon = Icons.chevron_right,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: txt(title, size: 13, weight: FontWeight.w500),
    subtitle: subtitle == null ? null : txt(subtitle, size: 11, color: D.muted),
    trailing: Icon(icon, size: 18, color: D.muted),
    onTap: () => openPreviewDialog(context, target),
  );
  Widget content() => switch (kind) {
    'reservation' => reservationForm(),
    'reservation-detail' => reservationDetail(),
    'order' => const OrderPanel(),
    'order-edit' || 'walkin' || 'takeaway' || 'menu' => menuEditor(),
    'expense' => Column(
      children: [
        pair(
          field('კატეგორია', 'სხვა ხარჯი'),
          field('თანხა (₾)', '130.00', number: true),
        ),
        field('აღწერა', 'დარბაზის დეკორი'),
        field('საქმიანი თარიღი', '2026-10-16'),
        help(
          'ხელფასები და მომწოდებლის გადახდები შესაბამის განყოფილებებში აღირიცხება.',
        ),
      ],
    ),
    'receiving' => receivingForm(),
    'receipt' => receiptDetail(),
    'stock' => stockDetail(),
    'stock-form' => Column(
      children: [
        field('დასახელება', ''),
        pair(
          field('საბაზო ერთეული', 'კგ'),
          field('მინიმალური ნაშთი', '5', number: true),
        ),
        field('SKU', '', required: false),
        help(
          'მინიმალური ნაშთი მხოლოდ გაფრთხილების ზღვარია. რაოდენობა მიღებებითა და მოძრაობებით იცვლება.',
        ),
      ],
    ),
    'supplier-form' => Column(
      children: [
        field('დასახელება', ''),
        field('ტელეფონი', '', required: false),
        field('შენიშვნა', '', required: false, lines: 2),
      ],
    ),
    'supplier' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Badge('აქტიური'),
        gap(16),
        const KV('დავალიანება', '1,250.00 ₾', emphasis: true),
        gap(20),
        const SectionHead(
          'ასორტიმენტი',
          sub: 'ამ მომწოდებელთან დაკავშირებული პროდუქტები',
        ),
        for (final s in ['სულგუნი', 'იმერული ყველი', 'მაწონი'])
          link(s, 'stock'),
        gap(16),
        ActionButton(
          'პროდუქტის დაკავშირება',
          icon: Icons.add,
          onTap: () => openPreviewDialog(context, 'stock-form'),
        ),
        gap(12),
        link('მიღებების ისტორია', 'receipt'),
        link('გადახდების ისტორია', 'payables'),
      ],
    ),
    'recipe' => recipeForm(),
    'payroll' => payroll(),
    'payroll-staff' => payrollStaff(),
    'obligations' => obligations(),
    'payables' => payables(),
    'payment' || 'reserve' => Column(
      children: [
        help(
          kind == 'reserve'
              ? 'გადადებული თანხა ჯერ ხარჯი არ არის.'
              : 'ჩაწერეთ უკვე შესრულებული გადახდა. თანხა ავტომატურად არ გადაირიცხება.',
        ),
        gap(20),
        field('თანხა (₾)', '150.00', number: true),
        pair(
          field('საქმიანი თარიღი', '2026-10-16'),
          kind == 'payment'
              ? field('გადახდის თარიღი', '2026-10-16')
              : const SizedBox.shrink(),
        ),
        field('შენიშვნა', '', required: false, lines: 2),
      ],
    ),
    'compensation' => Column(
      children: [
        Segments(
          const ['თვიური', 'დღიური', 'ხელით'],
          selected: tab,
          onSelect: (v) => setState(() => tab = v),
        ),
        gap(24),
        if (tab < 2)
          field(
            tab == 0 ? 'თვიური თანხა (₾)' : 'დღიური ტარიფი (₾)',
            tab == 0 ? '1200.00' : '60.00',
            number: true,
          ),
        field('მოქმედებს თვის პირველი რიცხვიდან', '2026-11-01'),
        help(
          'გახსნილი თვის პირობები უცვლელი რჩება. დღიური ხელფასი მხოლოდ მონიშნული დღეებით ითვლება.',
        ),
      ],
    ),
    'obligation-form' => Column(
      children: [
        field('დასახელება', ''),
        field('ტიპი', 'ქირა'),
        pair(
          field('თვეში (₾)', '1800.00', number: true),
          field('გადახდის რიცხვი', '25', number: true),
        ),
        pair(
          field('დაწყების თარიღი', '2026-11-01'),
          field('დასრულების თარიღი', '', required: false),
        ),
        help('უკვე გახსნილი პერიოდების თანხები უცვლელია.'),
      ],
    ),
    'correction' => Column(
      children: [
        help(
          'ორიგინალი ჩანაწერი რჩება. შესწორება ცალკე, დაკავშირებულ ჩანაწერად აისახება.',
          warning: true,
        ),
        gap(20),
        field('შესწორების თანხა (₾)', '-20.00', number: true),
        field('მიზეზი', 'თანხის დაზუსტება', lines: 2),
      ],
    ),
    'operation' => operation(),
    'cancel-order' => Column(
      children: [
        help(
          'გაუქმება არის POS-ისთვის გაგზავნილი მოთხოვნა. თანხის მიღებას ან ფისკალურ დახურვას არ ნიშნავს.',
          warning: true,
        ),
        gap(20),
        field('გაუქმების მიზეზი', '', lines: 3),
      ],
    ),
    'sale' => sale(),
    'notifications' => Column(
      children: [
        for (final r in [
          ('18:36', 'მაგიდა 04 დაიხურა', 'გაყიდვა ჩაიწერა · 186.00 ₾', 'sale'),
          (
            '18:24',
            'ახალი რეზერვაცია',
            'მარიამ გელაშვილი · 18:30',
            'reservation-detail',
          ),
          ('18:12', 'მოთხოვნა შესრულდა', 'ჩეკი დაბეჭდილია POS-ში', 'operation'),
        ])
          link('${r.$1} · ${r.$2}', r.$4, subtitle: r.$3),
      ],
    ),
    'profile' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KV('რესტორანი', 'მთვარე · დემო'),
        const KV('მომხმარებელი', 'ნინო მაისურაძე'),
        const KV('როლი', 'მენეჯერი'),
        gap(24),
        help('ეს იზოლირებული პრევიუ არ არის დაკავშირებული რეალურ სესიასთან.'),
        gap(16),
        ActionButton(
          'რესტორნის შეცვლის პრევიუ',
          onTap: () => openPreviewDialog(context, 'venue-profile'),
        ),
      ],
    ),
    'venue-profile' => Column(
      children: [
        field('რესტორნის სახელი', 'მთვარე'),
        field('მისამართი', 'სატესტო მისამართი'),
        field('ტელეფონი', '555 000 000'),
        field('ელფოსტა', 'demo@example.com', required: false),
      ],
    ),
    'staff' => Column(
      children: [
        const KV('სახელი', 'ანა კობახიძე'),
        const KV('როლი', 'ოფიციანტი'),
        link('სახელი და როლი', 'staff-form'),
        link('PIN-ის შეცვლა', 'staff-form'),
        link('ხელფასი და ისტორია', 'payroll-staff'),
      ],
    ),
    'staff-form' => Column(
      children: [
        field('სახელი', 'ანა კობახიძე'),
        field('როლი', 'ოფიციანტი'),
        field('PIN', '', hint: 'ახალი PIN'),
        help('რეალურ აპში PIN-ის უნიკალურობასა და უფლებებს სერვერი ამოწმებს.'),
      ],
    ),
    'service' => const Column(
      children: [KV('მომსახურების პროცენტი', '10%'), KV('ვალუტა', 'GEL')],
    ),
    'saved-menu' => Column(
      children: [
        link('საღამოს მენიუ', 'menu', subtitle: '12 პოზიცია · 1,280.00 ₾'),
        link('შეხვედრა · 8 სტუმარი', 'menu', subtitle: '8 პოზიცია · 640.00 ₾'),
        gap(16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            ActionButton(
              'დათვლა',
              onTap: () => openPreviewDialog(context, 'menu'),
            ),
            ActionButton(
              'ჩეკი / PDF',
              onTap: () => openPreviewDialog(context, 'operation'),
            ),
            ActionButton(
              'დადასტურება',
              onTap: () => openPreviewDialog(context, 'walkin'),
            ),
          ],
        ),
      ],
    ),
    'appearance' => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Segments(
          const ['ღია', 'მუქი', 'სისტემური'],
          selected: tab,
          onSelect: (v) => setState(() => tab = v),
        ),
        gap(22),
        help(
          'ამ ფაზაში დამუშავებულია ღია ვიზუალური მიმართულება. მუქი და სისტემური რეჟიმები არსებული შესაძლებლობებია და განხორციელებისას უნდა შენარჩუნდეს.',
        ),
      ],
    ),
    'business-day' => const Column(
      children: [
        KV('საქმიანი თარიღი', '16 ოქტომბერი, 2026'),
        KV('სტატუსი', 'ღია'),
        KV('ცვლის დაწყება', '10:00'),
        KV('დაკავებული მაგიდები', '8 / 18'),
        KV('დასრულებული შეკვეთები', '42'),
      ],
    ),
    'date' => CalendarDatePicker(
      initialDate: DateTime(2026, 10, 16),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2027, 12, 31),
      onDateChanged: (_) => setState(() => submitted = true),
    ),
    _ => historyContent(),
  };
  Widget reservationForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Badge(
            '1  სტუმარი',
            color: step == 0 ? D.purple : D.muted,
            bg: step == 0 ? D.purpleLight : D.bg,
            dot: false,
          ),
          hgap(8),
          const Icon(Icons.chevron_right, size: 16, color: D.muted),
          hgap(8),
          Badge(
            '2  მაგიდა',
            color: step == 1 ? D.purple : D.muted,
            bg: step == 1 ? D.purpleLight : D.bg,
            dot: false,
          ),
        ],
      ),
      gap(24),
      if (step == 0) ...[
        pair(
          field('სტუმრის სახელი', 'მარიამ გელაშვილი'),
          field('ტელეფონი', '555 000 000'),
        ),
        pair(field('თარიღი', '2026-10-16'), field('დრო', '18:30')),
        field('სტუმრების რაოდენობა', '6', number: true),
        field(
          'შენიშვნა',
          'ფანჯარასთან, თუ შესაძლებელია',
          required: false,
          lines: 2,
        ),
        const Divider(),
        gap(12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  txt('წინასწარი მენიუ', size: 14, weight: FontWeight.w600),
                  gap(4),
                  txt(
                    'სურვილისამებრ დაამატეთ კერძები',
                    size: 11,
                    color: D.muted,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => openPreviewDialog(context, 'menu'),
              child: const Text('არჩევა'),
            ),
          ],
        ),
      ] else ...[
        txt('მაგიდის არჩევა', size: 18, weight: FontWeight.w600),
        gap(5),
        txt('16 ოქტომბერი · 18:30 · 6 სტუმარი', size: 12, color: D.muted),
        gap(22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final n in ['04', '05', '08', '12', '13'])
              ChoiceChip(
                label: Text('მაგიდა $n'),
                selected: selectedTable == n,
                selectedColor: D.purpleLight,
                onSelected: (_) => setState(() => selectedTable = n),
              ),
          ],
        ),
        gap(24),
        help(
          'რეალურ აპში ხელმისაწვდომობა ხელახლა მოწმდება არჩეული თარიღისა და დროისთვის.',
        ),
        gap(20),
        KV('არჩეული მაგიდა', selectedTable),
      ],
    ],
  );
  Widget reservationDetail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge('დადასტურებული'),
      gap(18),
      txt('მარიამ გელაშვილი', size: 25, weight: FontWeight.w600),
      gap(7),
      txt('სატესტო სტუმარი · 555 000 000', size: 12, color: D.muted),
      gap(24),
      const KV('თარიღი და დრო', '16 ოქტომბერი · 18:30'),
      const KV('სტუმრები', '6'),
      const KV('მაგიდები', '04, 05'),
      const KV('წყარო', 'Manager'),
      gap(20),
      help('ფანჯარასთან, თუ შესაძლებელია'),
      gap(24),
      const SectionHead('წინასწარი მენიუ'),
      const KV('იმერული ხაჭაპური × 2', '36.00 ₾'),
      const KV('ქათმის მწვადი × 4', '88.00 ₾'),
      const KV('ჯამი', '124.00 ₾', emphasis: true),
      gap(20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ActionButton(
            'დადასტურება',
            primary: true,
            onTap: () => openPreviewDialog(context, 'operation'),
          ),
          ActionButton(
            'ბეჭდვა',
            icon: Icons.print_outlined,
            onTap: () => openPreviewDialog(context, 'operation'),
          ),
          ActionButton(
            'გაუქმება',
            onTap: () => openPreviewDialog(context, 'cancel-order'),
          ),
        ],
      ),
    ],
  );
  Widget menuEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (kind == 'takeaway') ...[
        pair(field('სახელი', 'მარიამი'), field('გატანის დრო', '19:10')),
        field('ტელეფონი', '555 000 000'),
      ],
      if (kind == 'walkin') ...[field('მაგიდა', '04'), gap(4)],
      TextField(
        decoration: const InputDecoration(
          hintText: 'მენიუში ძებნა',
          prefixIcon: Icon(Icons.search, size: 20),
        ),
      ),
      gap(16),
      Segments(
        const ['კერძები', 'სასმელები', 'არჩეული'],
        selected: tab,
        onSelect: (v) => setState(() => tab = v),
      ),
      gap(20),
      for (final r
          in tab == 1
              ? [
                  ('საფერავი · ბოთლი', '48.00 ₾'),
                  ('საფერავი · ჭიქა', '9.00 ₾'),
                  ('ლიმონათი', '4.00 ₾'),
                ]
              : [
                  ('ხინკალი ქალაქური', '2.00 ₾'),
                  ('იმერული ხაჭაპური', '18.00 ₾'),
                  ('ქათმის მწვადი', '22.00 ₾'),
                ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: txt(r.$1, size: 13, weight: FontWeight.w500),
          subtitle: txt(r.$2, size: 11, color: D.muted),
          trailing: IconButton(
            tooltip: 'დამატება',
            onPressed: () => setState(() => step++),
            icon: const Icon(Icons.add_circle_outline, color: D.purple),
          ),
        ),
      gap(18),
      const Divider(),
      KV('არჩეული პოზიციები', '${3 + step}'),
      KV('პრევიუს ჯამი', '${124 + step * 18}.00 ₾', emphasis: true),
      gap(14),
      help(
        'შეკვეთის ცვლილება ინარჩუნებს მოთხოვნის იდენტობას და POS-ის პასუხამდე მოლოდინში რჩება.',
      ),
    ],
  );
  Widget receivingForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Segments(
        const ['1  პროდუქტები', '2  გადახდა'],
        selected: step,
        onSelect: (v) => setState(() => step = v),
      ),
      gap(22),
      if (step == 0) ...[
        pair(
          field('მომწოდებელი', 'აგრო სახლი'),
          field('მიღების თარიღი', '2026-10-16'),
        ),
        field('ზედნადების ნომერი', 'INV-028', required: false),
        const SectionHead('პროდუქტები'),
        pair(
          field('პროდუქტი', 'სულგუნი'),
          field('რაოდენობა (კგ)', '20', number: true),
        ),
        field('ერთეულის ფასი (₾)', '18.50', number: true),
        ActionButton(
          'პროდუქტის დამატება',
          icon: Icons.add,
          onTap: () => openPreviewDialog(context, 'stock-form'),
        ),
        gap(18),
        help(
          'შემდეგ ნაბიჯზე გადასვლა მარაგს არ ცვლის. მიღება საბოლოო დადასტურებას საჭიროებს.',
        ),
      ] else ...[
        const KV('სულგუნი · 20 კგ', '370.00 ₾'),
        const KV('იმერული ყველი · 10 კგ', '250.00 ₾'),
        const KV('მიღების ჯამი', '620.00 ₾', emphasis: true),
        gap(24),
        field('უკვე გადახდილი (₾)', '300.00', number: true),
        field('გადახდის თარიღი', '2026-10-16'),
        const KV('დარჩენილი ვალი', '320.00 ₾'),
        help(
          'გატარებული მიღება ზრდის მარაგს. გაუქმება ტოვებს ისტორიას და ამატებს უკუმოძრაობას.',
          warning: true,
        ),
      ],
    ],
  );
  Widget receiptDetail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge('გატარებული'),
      gap(18),
      const KV('მომწოდებელი', 'აგრო სახლი'),
      const KV('მიღების თარიღი', '16 ოქტომბერი, 2026'),
      const KV('ზედნადები', 'INV-028'),
      gap(18),
      const Divider(),
      const KV('სულგუნი · 20 კგ', '370.00 ₾'),
      const KV('იმერული ყველი · 10 კგ', '250.00 ₾'),
      const KV('სულ', '620.00 ₾', emphasis: true),
      gap(18),
      help('გატარებული დოკუმენტი მხოლოდ წასაკითხია. მიღებამ მარაგი გაზარდა.'),
      gap(18),
      link('გადახდა და დავალიანება', 'payables'),
      link('მოძრაობების ისტორია', 'movements'),
    ],
  );
  Widget stockDetail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge('მინიმალურ ზღვარზე ქვემოთ', color: D.amber, bg: D.amberLight),
      gap(22),
      txt('2.4 კგ', size: 38, weight: FontWeight.w600),
      gap(5),
      txt('მიმდინარე ნაშთი · ძირითადი საწყობი', size: 12, color: D.muted),
      gap(24),
      const KV('საშუალო მიმდინარე ფასი', '18.50 ₾ / კგ'),
      const KV('მინიმალური ნაშთი', '5 კგ'),
      const KV('მარაგის ღირებულება', '44.40 ₾'),
      gap(20),
      link('მოძრაობების სრული ისტორია', 'movements'),
      link(
        'გამოყენება მენიუში',
        'recipe',
        subtitle: 'იმერული ხაჭაპური, მეგრული ხაჭაპური',
      ),
      link('პროდუქტის რედაქტირება', 'stock-form'),
      gap(16),
      help(
        'ნაშთი გამომდინარეობს მიღებებიდან, ჩამოწერებიდან და უკუმოძრაობებიდან.',
      ),
    ],
  );
  Widget recipeForm() => Column(
    children: [
      const SectionHead(
        'შემადგენლობა',
        sub: 'მიმდინარე თეორიული თვითღირებულება',
      ),
      for (final r in [
        ('ფქვილი', '0.25 კგ'),
        ('სულგუნი', '0.18 კგ'),
        ('კვერცხი', '1 ც'),
        ('კარაქი', '0.02 კგ'),
      ])
        KV(r.$1, r.$2),
      gap(16),
      field('პორციის გამოსავალი', '1', number: true),
      const KV('მიმდინარე თვითღირებულება', '6.40 ₾', emphasis: true),
      gap(16),
      help(
        'ეს არის მიმდინარე თეორიული ფასი და არა ისტორიული გაყიდვის თვითღირებულება.',
      ),
      gap(16),
      ActionButton(
        'ინგრედიენტის დამატება',
        icon: Icons.add,
        onTap: () => openPreviewDialog(context, 'stock-form'),
      ),
    ],
  );
  Widget payroll() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: txt('ოქტომბერი 2026', size: 17, weight: FontWeight.w600),
          ),
          const Badge('მიმდინარე თვე', dot: false),
        ],
      ),
      gap(22),
      Segments(
        const ['მიმოხილვა', 'დღიური', 'თვიური', 'გადახდები'],
        selected: tab,
        onSelect: (v) => setState(() => tab = v),
      ),
      gap(22),
      if (tab == 0) ...[
        const KV('დარიცხული', '7,240.00 ₾'),
        const KV('გადახდილი', '4,000.00 ₾'),
        const KV('დარჩენილი', '3,240.00 ₾', emphasis: true),
        gap(20),
        help(
          'დარიცხვა და გადახდა განსხვავდება. ფინანსურ გასავლებში მხოლოდ გადახდა შედის.',
        ),
      ] else if (tab == 1) ...[
        txt('16 ოქტომბერი · დღიური ფურცელი', size: 14, weight: FontWeight.w600),
        gap(16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: worked,
          onChanged: (v) => setState(() => worked = v),
          title: txt('ანა კობახიძე', size: 14, weight: FontWeight.w500),
          subtitle: txt('დღიური ტარიფი · 60.00 ₾', size: 11, color: D.muted),
          activeTrackColor: D.purple,
        ),
        help(
          'დღე მონიშნულია მხოლოდ თქვენი დადასტურებით. დასწრება ავტომატურად არ განისაზღვრება.',
        ),
      ] else if (tab == 3) ...[
        link(
          'ანა კობახიძე · 600.00 ₾',
          'payroll-staff',
          subtitle: '16 ოქტ · შესრულებული გადახდა',
        ),
        link(
          'გიორგი ლომიძე · 1,200.00 ₾',
          'payroll-staff',
          subtitle: '10 ოქტ · შესრულებული გადახდა',
        ),
      ] else
        const KV('გიორგი ლომიძე · თვიური', '1,200.00 ₾'),
      gap(18),
      const Divider(),
      link(
        'ანა კობახიძე',
        'payroll-staff',
        subtitle: 'დღიური · დარჩენილი 360.00 ₾',
      ),
      link(
        'გიორგი ლომიძე',
        'payroll-staff',
        subtitle: 'თვიური · დარჩენილი 1,200.00 ₾',
      ),
    ],
  );
  Widget payrollStaff() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge(
        'დღიური · 60.00 ₾',
        color: D.purple,
        bg: D.purpleLight,
        dot: false,
      ),
      gap(20),
      const KV('დარიცხული', '960.00 ₾'),
      const KV('გადახდილი', '600.00 ₾'),
      const KV('დარჩენილი', '360.00 ₾', emphasis: true),
      gap(18),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ActionButton(
            'გადახდის აღრიცხვა',
            primary: true,
            onTap: () => openPreviewDialog(context, 'payment'),
          ),
          ActionButton(
            'ხელფასის წესი',
            onTap: () => openPreviewDialog(context, 'compensation'),
          ),
        ],
      ),
      gap(24),
      const SectionHead('ისტორია'),
      link(
        'გადახდა · 600.00 ₾',
        'correction',
        subtitle: '16 ოქტომბერი · ჩანაწერის შესწორება',
      ),
      link(
        'სამუშაო დღე · +60.00 ₾',
        'audit',
        subtitle: '16 ოქტომბერი · დარიცხვა',
      ),
    ],
  );
  Widget obligations() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHead(
        'ოქტომბერი 2026',
        sub: 'პერიოდის გეგმა და უკვე შესრულებული გადახდები',
      ),
      const KV('დარჩენილი გადასახდელი', '1,800.00 ₾', emphasis: true),
      const KV('გადადებული რეზერვი', '900.00 ₾'),
      gap(18),
      Panel(
        padding: 18,
        color: D.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: txt('ქირა', size: 17, weight: FontWeight.w600)),
                const Badge(
                  '25 ოქტომბერი',
                  color: D.amber,
                  bg: D.amberLight,
                  dot: false,
                ),
              ],
            ),
            gap(12),
            const KV('თვიური თანხა', '1,800.00 ₾'),
            const KV('რეზერვი', '900.00 ₾'),
            const KV('რეკომენდებული დღიური', '90.00 ₾'),
            gap(14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ActionButton(
                  'გადადება',
                  onTap: () => openPreviewDialog(context, 'reserve'),
                ),
                ActionButton(
                  'გადახდა',
                  primary: true,
                  onTap: () => openPreviewDialog(context, 'payment'),
                ),
              ],
            ),
          ],
        ),
      ),
      gap(16),
      help(
        'რეზერვი დაგეგმვის თანხაა. გასავალი ჩნდება მხოლოდ გადახდის აღრიცხვისას.',
      ),
      gap(16),
      ActionButton(
        'ვალდებულების დამატება',
        icon: Icons.add,
        onTap: () => openPreviewDialog(context, 'obligation-form'),
      ),
    ],
  );
  Widget payables() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const KV('მომწოდებლების ვალი', '2,850.00 ₾', emphasis: true),
      gap(18),
      Segments(
        const ['დავალიანება', 'გადახდები'],
        selected: tab,
        onSelect: (v) => setState(() => tab = v),
      ),
      gap(16),
      for (final r in [
        ('აგრო სახლი', '1,250.00 ₾'),
        ('ღვინის მარანი', '980.00 ₾'),
        ('სასურსათო ბაზარი', '620.00 ₾'),
      ])
        link(
          '${r.$1} · ${r.$2}',
          tab == 0 ? 'payment' : 'correction',
          subtitle: tab == 0 ? 'გადახდის აღრიცხვა' : 'ისტორია და შესწორება',
        ),
      gap(18),
      help(
        'გადახდის თარიღი და მიღების თარიღი ცალკე ინახება. გაუქმებული მიღების ისტორია რჩება.',
      ),
    ],
  );
  Widget operation() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge('POS-ის პასუხის მოლოდინში', color: D.amber, bg: D.amberLight),
      gap(20),
      txt('მოთხოვნა მიღებულია', size: 23, weight: FontWeight.w600),
      gap(8),
      txt(
        'მიწოდება ჯერ არ ნიშნავს შესრულებას. შედეგი გამოჩნდება POS-ის დადასტურების შემდეგ.',
        size: 13,
        color: D.muted,
      ),
      gap(24),
      for (final r in [
        ('18:42:01', 'Cloud-მა მიიღო', 'დასრულებული'),
        ('18:42:02', 'მიწოდება არჩეულ POS-ს', 'მოლოდინში'),
        ('—', 'POS-ის დადასტურება', 'მოლოდინში'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              Icon(
                r.$3 == 'დასრულებული'
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 19,
                color: r.$3 == 'დასრულებული' ? D.green : D.muted,
              ),
              hgap(12),
              Expanded(child: txt(r.$2, size: 13)),
              txt(r.$1, size: 11, color: D.muted),
            ],
          ),
        ),
      help(
        'დაკარგული პასუხის შემთხვევაში მოწმდება იგივე მოთხოვნა. ხელახლა გაგზავნა ახალ ოპერაციას არ ქმნის.',
      ),
      gap(18),
      ActionButton(
        'მდგომარეობის შემოწმება',
        onTap: () => setState(() => submitted = true),
      ),
    ],
  );
  Widget sale() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Badge('ფისკალური'),
      gap(18),
      const KV('დახურვა', '16 ოქტომბერი · 18:36'),
      const KV('მაგიდა', '04 · მთავარი დარბაზი'),
      const KV('გადახდა', 'ბარათი · TBC'),
      gap(20),
      const Divider(),
      const KV('პროდუქტები', '169.09 ₾'),
      const KV('მომსახურება', '16.91 ₾'),
      const KV('სულ', '186.00 ₾', emphasis: true),
      const KV('გამოყენებული ავანსი', '0.00 ₾'),
      const KV('დახურვაზე მიღებული', '186.00 ₾'),
      gap(22),
      link('დაკავშირებული აუდიტი', 'audit'),
      help(
        'ისტორიული გაყიდვის დეტალი ინარჩუნებს გადახდებსა და დახურვის იდენტობას.',
      ),
    ],
  );
  Widget historyContent() {
    final rows = switch (kind) {
      'movements' => [
        ('მიღება #028', '+20.00 კგ · 14:30'),
        ('გაყიდვა #1041', '−0.36 კგ · 18:36'),
        ('გაყიდვა #1039', '−0.18 კგ · 18:22'),
      ],
      'consumption' => [
        ('გაყიდვა #1041', '2 პროდუქტი · ჩამოწერილი'),
        ('გაყიდვა #1039', '1 პროდუქტი · აღდგენილი'),
      ],
      'products' => [
        ('ხინკალი ქალაქური', '120 ც · 240.00 ₾'),
        ('იმერული ხაჭაპური', '24 ც · 432.00 ₾'),
      ],
      'staff-results' => [
        ('ანა კობახიძე', '18 გაყიდვა · 3,240.00 ₾'),
        ('დავით ბერიძე', '14 გაყიდვა · 2,760.00 ₾'),
      ],
      'expenses' => [
        ('სხვა ხარჯი', '130.00 ₾ · დეკორი'),
        ('ხელფასი', '600.00 ₾ · ანა'),
      ],
      'lifecycle' => [
        ('შეკვეთა #1021', 'გაუქმებული · თანხა არ მიღებულა'),
        ('შეკვეთა #1012', 'აღდგენილი შეკვეთად'),
      ],
      _ => [
        ('დღის გაყიდვები', '8,450.00 ₾'),
        ('შეკვეთები', '42'),
        ('ნაღდი', '2,680.00 ₾'),
        ('ბარათი', '5,270.00 ₾'),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        txt('16 ოქტომბერი, 2026', size: 12, color: D.muted),
        gap(18),
        for (final r in rows)
          link(
            r.$1,
            kind == 'expenses' ? 'correction' : 'audit',
            subtitle: r.$2,
          ),
        gap(18),
        help(
          'პრევიუში ნაჩვენებია სინთეტიკური ჩანაწერები. რეალურ აპში ფილტრები, გვერდებად ჩატვირთვა და შესაბამისი ექსპორტი შენარჩუნდება.',
        ),
      ],
    );
  }
}
