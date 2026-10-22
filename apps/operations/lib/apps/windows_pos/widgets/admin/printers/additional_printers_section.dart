import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/ui/widgets/vynic_responsive_dialog.dart';

class AdditionalPrintersSection extends StatefulWidget {
  const AdditionalPrintersSection({super.key});
  @override
  State<AdditionalPrintersSection> createState() => _AdditionalPrintersState();
}

class _AdditionalPrintersState extends State<AdditionalPrintersSection> {
  List<Map<String, dynamic>> rows = [];
  List<PrinterRoute> routes = [];
  String? error;
  bool dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _reload();
    DeveloperAccess.unlocked.addListener(_accessChanged);
  }

  @override
  void dispose() {
    DeveloperAccess.unlocked.removeListener(_accessChanged);
    super.dispose();
  }

  void _accessChanged() {
    if (mounted) setState(_reload);
  }

  void _reload() {
    rows = [];
    routes = [];
    if (!DeveloperAccess.can(DeveloperScope.printers)) return;
    try {
      rows = LocalPrinterCatalog.read();
      routes = LocalPrinterCatalog.readRoutesForAdministration();
      error = null;
    } catch (e) {
      error = 'პრინტერების ჩანაწერი შესამოწმებელია: $e';
    }
  }

  Future<void> _add() async {
    if (dialogOpen || !DeveloperAccess.can(DeveloperScope.printers)) return;
    dialogOpen = true;
    try {
      final saved = await showPosModal<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _AddPrinterDialog(),
      );
      if (saved == true && mounted) setState(_reload);
    } finally {
      dialogOpen = false;
    }
  }

  Future<void> _configureRoute([PrinterRoute? route]) async {
    if (dialogOpen || !DeveloperAccess.can(DeveloperScope.printers)) return;
    dialogOpen = true;
    try {
      await showPosModal<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PrinterRouteDialog(route: route),
      );
      // Another admitted writer, or a failed flush, may have changed the
      // accepted revision even when this draft was cancelled after a conflict.
      if (mounted) setState(_reload);
    } finally {
      dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      !DeveloperAccess.can(DeveloperScope.printers)
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              'დამატებითი პრინტერები',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'დაამატეთ სახელი და IP. შეკვეთები დამატებით პრინტერზე ავტომატურად არ იგზავნება.',
            ),
            if (error != null) SelectableText(error!),
            for (final row in rows)
              ListTile(
                key: ValueKey('additional-printer-${row['id'] ?? row['ip']}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print_outlined),
                title: Text(row['name'] as String),
                subtitle: Text('${row['ip']}:9100 · მარშრუტი დასადგენია'),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('add-printer'),
                onPressed:
                    error != null ||
                        !DeveloperAccess.can(DeveloperScope.printers)
                    ? null
                    : _add,
                icon: const Icon(Icons.add),
                label: const Text('პრინტერის დამატება'),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'პრინტერის მარშრუტები',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'აირჩიეთ დანიშნულება და კავშირი. მარშრუტის გარეშე დამატებითი პრინტერები უცვლელად რჩება.',
            ),
            if (LocalPrinterCatalog.cloudOwnsRole(PrinterRole.kitchen) ||
                LocalPrinterCatalog.cloudOwnsRole(PrinterRole.receipt))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'სამზარეულოსა და ჩეკის Cloud პარამეტრებისთვის საჭიროა მარშრუტის ცალკე გადაყვანა.',
                ),
              ),
            for (final route in routes)
              ListTile(
                key: ValueKey('printer-route-${route.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  route.destination.kind == PrinterTransportKind.tcp
                      ? Icons.router_outlined
                      : Icons.print_outlined,
                ),
                title: Text(route.name),
                subtitle: Text(
                  '${_roleLabel(route.role)} · ${route.destination.display} · ვერსია ${route.revision}'
                  '\n${route.capabilityProfile.paperWidthMm} მმ · ${route.capabilityProfile.rasterWidthDots} წერტილი · ${_cutterLabel(route.capabilityProfile.cutter)}'
                  '${_routeHoldLabel(route) == null ? '' : '\n${_routeHoldLabel(route)}'}',
                ),
                trailing: IconButton(
                  key: ValueKey('edit-printer-route-${route.id}'),
                  tooltip: 'მარშრუტის შეცვლა',
                  onPressed:
                      error != null ||
                          !DeveloperAccess.can(DeveloperScope.printers)
                      ? null
                      : () => _configureRoute(route),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('add-printer-route'),
                onPressed:
                    error != null ||
                        !DeveloperAccess.can(DeveloperScope.printers)
                    ? null
                    : _configureRoute,
                icon: const Icon(Icons.add),
                label: const Text('მარშრუტის დამატება'),
              ),
            ),
          ],
        );
}

class _AddPrinterDialog extends StatefulWidget {
  const _AddPrinterDialog();
  @override
  State<_AddPrinterDialog> createState() => _AddPrinterState();
}

class _AddPrinterState extends State<_AddPrinterDialog> {
  final name = TextEditingController();
  final ip = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    ip.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await LocalPrinterCatalog.add(name.text, ip.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => VynicResponsiveDialog(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('პრინტერის დამატება', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 16),
          PosOnScreenTextField(
            key: const ValueKey('additional-printer-name'),
            controller: name,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'სახელი'),
          ),
          const SizedBox(height: 12),
          PosOnScreenTextField(
            key: const ValueKey('additional-printer-ip'),
            controller: ip,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'IP მისამართი'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            children: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('გაუქმება'),
              ),
              FilledButton(
                key: const ValueKey('additional-printer-save'),
                onPressed: busy ? null : _save,
                child: Text(busy ? 'ინახება...' : 'დამატება'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _roleLabel(PrinterRole role) => switch (role) {
  PrinterRole.kitchen => 'სამზარეულოს მარშრუტი',
  PrinterRole.bar => 'ბარის მარშრუტი',
  PrinterRole.receipt => 'ჩეკის მარშრუტი',
  PrinterRole.additional => 'დამატებითი მარშრუტი',
};

String? _routeHoldLabel(PrinterRoute route) {
  if (LocalPrinterCatalog.cloudOwnsRole(route.role)) {
    return 'შეჩერებულია: Cloud პარამეტრის მარშრუტი ცალკე უნდა გადაიყვანოთ.';
  }
  if (route.destination.kind == PrinterTransportKind.windowsSpooler &&
      route.destination.ownerDeviceId != LocalPrinterCatalog.enrolledDeviceId) {
    return 'შეჩერებულია: Windows რიგი სხვა ტერმინალს ეკუთვნის; ხელახლა აირჩიეთ რიგი.';
  }
  if (!route.capabilityProfile.hasImplementedRenderer) {
    return 'შეჩერებულია: Windows დრაივერის რენდერი ჯერ არ არის ხელმისაწვდომი.';
  }
  return null;
}

String _cutterLabel(PrinterCutter cutter) => switch (cutter) {
  PrinterCutter.none => 'ჭრის გარეშე',
  PrinterCutter.full => 'სრული ჭრა',
  PrinterCutter.partial => 'ნაწილობრივი ჭრა',
};

String _languageLabel(PrinterCommandLanguage language) => switch (language) {
  PrinterCommandLanguage.escposRaster => 'RAW ESC/POS (რასტრი)',
  PrinterCommandLanguage.windowsDriverRendered =>
    'Windows დრაივერის რენდერი (შეჩერებული)',
};

String _beepLabel(PrinterBeepCapability capability) => switch (capability) {
  PrinterBeepCapability.unknown => 'უცნობი',
  PrinterBeepCapability.unsupported => 'არ უჭერს მხარს',
  PrinterBeepCapability.epsonEscA97Pattern =>
    'Epson-ის რეგისტრირებული ხმის პატერნი',
};

class _PrinterRouteDialog extends StatefulWidget {
  const _PrinterRouteDialog({this.route});
  final PrinterRoute? route;
  @override
  State<_PrinterRouteDialog> createState() => _PrinterRouteDialogState();
}

class _PrinterRouteDialogState extends State<_PrinterRouteDialog> {
  late final TextEditingController name;
  late final TextEditingController ip;
  late final TextEditingController port;
  late final TextEditingController paperWidth;
  late final TextEditingController rasterWidth;
  late PrinterRole role;
  late PrinterTransportKind transport;
  late PrinterCommandLanguage commandLanguage;
  late PrinterCutter cutter;
  late PrinterBeepCapability beepCapability;
  late bool beepCompatibilityConfirmed;
  late bool beepEnabled;
  List<WindowsPrinterQueue> queues = const [];
  WindowsPrinterQueue? selectedQueue;
  bool inventoryBusy = false;
  bool busy = false;
  String? inventoryError;
  String? error;

  bool get authorized => DeveloperAccess.can(DeveloperScope.printers);

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    name = TextEditingController(text: route?.name ?? '');
    ip = TextEditingController(text: route?.destination.host ?? '');
    port = TextEditingController(text: '${route?.destination.port ?? 9100}');
    role = route?.role ?? PrinterRole.additional;
    transport = route?.destination.kind ?? PrinterTransportKind.tcp;
    final profile =
        route?.capabilityProfile ??
        PrinterCapabilityProfile.genericEscposRaster();
    paperWidth = TextEditingController(text: '${profile.paperWidthMm}');
    rasterWidth = TextEditingController(text: '${profile.rasterWidthDots}');
    commandLanguage = profile.language;
    cutter = profile.cutter;
    beepCapability = profile.beep.capability;
    beepCompatibilityConfirmed =
        beepCapability == PrinterBeepCapability.epsonEscA97Pattern;
    beepEnabled = profile.beep.enabled && beepCompatibilityConfirmed;
    DeveloperAccess.unlocked.addListener(_accessChanged);
    if (transport == PrinterTransportKind.windowsSpooler) _loadQueues();
  }

  @override
  void dispose() {
    DeveloperAccess.unlocked.removeListener(_accessChanged);
    name.dispose();
    ip.dispose();
    port.dispose();
    paperWidth.dispose();
    rasterWidth.dispose();
    super.dispose();
  }

  void _accessChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadQueues() async {
    if (inventoryBusy || busy || !authorized) return;
    setState(() {
      inventoryBusy = true;
      selectedQueue = null;
      queues = const [];
      inventoryError = null;
    });
    try {
      final inventory =
          await LocalPrinterCatalog.listWindowsQueuesForAdministration();
      if (!mounted) return;
      final destination = widget.route?.destination;
      setState(() {
        queues = inventory;
        // Review an edit against this exact installation inventory. A renamed
        // or driver/port-changed queue is never selected by name alone.
        if (destination?.ownerDeviceId ==
            LocalPrinterCatalog.enrolledDeviceId) {
          selectedQueue = inventory
              .where(
                (queue) =>
                    queue.name == destination?.queueName &&
                    queue.driver == destination?.driverName &&
                    queue.port == destination?.portName,
              )
              .firstOrNull;
        }
        inventoryBusy = false;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          inventoryBusy = false;
          inventoryError = 'Windows რიგების მიღება ვერ მოხერხდა: $failure';
        });
      }
    }
  }

  Future<void> _save() async {
    if (busy ||
        inventoryBusy ||
        !authorized ||
        LocalPrinterCatalog.cloudOwnsRole(role))
      return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final paperMm = int.tryParse(paperWidth.text.trim());
      final rasterDots = int.tryParse(rasterWidth.text.trim());
      if (paperMm == null || paperMm < 40 || paperMm > 120) {
        throw ArgumentError('ქაღალდის სიგანე უნდა იყოს 40–120 მმ დიაპაზონში');
      }
      if (rasterDots == null ||
          rasterDots < 64 ||
          rasterDots > 2048 ||
          rasterDots % 8 != 0) {
        throw ArgumentError(
          'რასტრის სიგანე უნდა იყოს 64–2048 წერტილი და 8-ის ჯერადი',
        );
      }
      if (beepCapability == PrinterBeepCapability.epsonEscA97Pattern &&
          !beepCompatibilityConfirmed) {
        throw StateError(
          'Epson-ის ხმის პატერნთან თავსებადობა ცალკე დაადასტურეთ',
        );
      }
      final profile = PrinterCapabilityProfile(
        paperWidthMm: paperMm,
        rasterWidthDots: rasterDots,
        language: commandLanguage,
        cutter: cutter,
        beep: PrinterBeepSettings(
          capability: beepCapability,
          enabled: beepCompatibilityConfirmed && beepEnabled,
        ),
      );
      late final PrinterDestination destination;
      if (transport == PrinterTransportKind.tcp) {
        final parsedPort = int.tryParse(port.text.trim());
        if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
          throw ArgumentError('პორტი უნდა იყოს 1–65535 დიაპაზონში');
        }
        destination = PrinterDestination.tcp(
          host: ip.text.trim(),
          port: parsedPort,
        );
      } else {
        final queue = selectedQueue;
        final owner = LocalPrinterCatalog.enrolledDeviceId;
        if (queue == null || owner == null) {
          throw StateError('აირჩიეთ ამ ტერმინალის Windows რიგი');
        }
        destination = PrinterDestination.windowsSpooler(
          ownerDeviceId: owner,
          queueName: queue.name,
          driverName: queue.driver,
          portName: queue.port,
        );
      }
      await LocalPrinterCatalog.saveRoute(
        id: widget.route?.id,
        name: name.text,
        role: role,
        destination: destination,
        expectedRevision: widget.route?.revision ?? 0,
        capabilityProfile: profile,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = failure is PrinterRouteRevisionConflict
              ? 'მარშრუტი შეიცვალა. დახურეთ ფანჯარა და ხელახლა გახსენით.'
              : 'მარშრუტის შენახვა ვერ მოხერხდა: $failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => VynicResponsiveDialog(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.route == null ? 'მარშრუტის დამატება' : 'მარშრუტის შეცვლა',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 16),
          if (!authorized)
            const Text('პრინტერების დეველოპერის წვდომა დასრულებულია.'),
          PosOnScreenTextField(
            key: const ValueKey('printer-route-name'),
            controller: name,
            enabled: authorized && !busy,
            decoration: const InputDecoration(labelText: 'სახელი'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PrinterRole>(
            key: const ValueKey('printer-route-role'),
            initialValue: role,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'დანიშნულება'),
            items: [
              for (final option in PrinterRole.values)
                DropdownMenuItem(
                  value: option,
                  enabled: !LocalPrinterCatalog.cloudOwnsRole(option),
                  child: Text(
                    _roleLabel(option),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: authorized && !busy
                ? (value) {
                    if (value != null) setState(() => role = value);
                  }
                : null,
          ),
          if (LocalPrinterCatalog.cloudOwnsRole(role))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'შეჩერებულია: Cloud პარამეტრის მარშრუტი ცალკე უნდა გადაიყვანოთ.',
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PrinterTransportKind>(
            key: const ValueKey('printer-route-transport'),
            initialValue: transport,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'კავშირი'),
            items: [
              const DropdownMenuItem(
                value: PrinterTransportKind.tcp,
                child: Text('ქსელი (LAN / TCP)'),
              ),
              DropdownMenuItem(
                value: PrinterTransportKind.windowsSpooler,
                enabled:
                    LocalPrinterCatalog.windowsQueuesAvailable &&
                    LocalPrinterCatalog.enrolledDeviceId != null,
                child: const Text('Windows პრინტერის რიგი'),
              ),
            ],
            onChanged: authorized && !busy && !inventoryBusy
                ? (value) {
                    if (value == null) return;
                    setState(() {
                      transport = value;
                      error = null;
                    });
                    if (value == PrinterTransportKind.windowsSpooler)
                      _loadQueues();
                  }
                : null,
          ),
          const SizedBox(height: 12),
          if (transport == PrinterTransportKind.tcp) ...[
            PosOnScreenTextField(
              key: const ValueKey('printer-route-ip'),
              controller: ip,
              enabled: authorized && !busy,
              decoration: const InputDecoration(labelText: 'IP მისამართი'),
            ),
            const SizedBox(height: 12),
            PosOnScreenTextField(
              key: const ValueKey('printer-route-port'),
              controller: port,
              enabled: authorized && !busy,
              mode: PosInputMode.number,
              decoration: const InputDecoration(labelText: 'პორტი'),
            ),
          ] else ...[
            const Text('ESC/POS მხარდაჭერა ფიზიკურად ჯერ შესამოწმებელია.'),
            const SizedBox(height: 8),
            if (inventoryBusy) const Text('Windows რიგების მიღება...'),
            if (inventoryError != null) Text(inventoryError!),
            if (!inventoryBusy && inventoryError == null && queues.isEmpty)
              const Text('ამ ტერმინალზე Windows პრინტერის რიგი არ მოიძებნა.'),
            KeyedSubtree(
              key: ObjectKey(queues),
              child: DropdownButtonFormField<WindowsPrinterQueue>(
                key: const ValueKey('printer-route-queue'),
                initialValue: selectedQueue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'დაყენებული Windows რიგი',
                ),
                items: [
                  for (final queue in queues)
                    DropdownMenuItem(
                      value: queue,
                      child: Text(queue.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged:
                    authorized &&
                        !busy &&
                        !inventoryBusy &&
                        inventoryError == null
                    ? (value) => setState(() => selectedQueue = value)
                    : null,
              ),
            ),
            if (selectedQueue != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'დრაივერი: ${selectedQueue!.driver}\nპორტი: ${selectedQueue!.port}',
                ),
              ),
            TextButton.icon(
              key: const ValueKey('refresh-printer-route-queues'),
              onPressed: authorized && !busy && !inventoryBusy
                  ? _loadQueues
                  : null,
              icon: const Icon(Icons.refresh),
              label: const Text('რიგების განახლება'),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'ბეჭდვის შესაძლებლობები',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'პარამეტრები მიუთითეთ პრინტერის დადასტურებული შესაძლებლობებით. ქართული ტექსტი რასტრულ გამოსახულებად იბეჭდება.',
          ),
          const SizedBox(height: 12),
          PosOnScreenTextField(
            key: const ValueKey('printer-route-paper-width'),
            controller: paperWidth,
            enabled: authorized && !busy,
            mode: PosInputMode.number,
            decoration: const InputDecoration(
              labelText: 'ქაღალდის სიგანე (მმ)',
            ),
          ),
          const SizedBox(height: 12),
          PosOnScreenTextField(
            key: const ValueKey('printer-route-raster-width'),
            controller: rasterWidth,
            enabled: authorized && !busy,
            mode: PosInputMode.number,
            decoration: const InputDecoration(
              labelText: 'რასტრის სიგანე (წერტილი)',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PrinterCommandLanguage>(
            key: const ValueKey('printer-route-command-language'),
            initialValue: commandLanguage,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ბეჭდვის ენა'),
            items: [
              for (final language in PrinterCommandLanguage.values)
                DropdownMenuItem(
                  value: language,
                  child: Text(
                    _languageLabel(language),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: authorized && !busy
                ? (value) {
                    if (value != null) setState(() => commandLanguage = value);
                  }
                : null,
          ),
          if (commandLanguage == PrinterCommandLanguage.windowsDriverRendered)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'შეჩერებულია: Windows დრაივერის რენდერი ჯერ არ არის ხელმისაწვდომი.',
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PrinterCutter>(
            key: const ValueKey('printer-route-cutter'),
            initialValue: cutter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ქაღალდის ჭრა'),
            items: [
              for (final option in PrinterCutter.values)
                DropdownMenuItem(
                  value: option,
                  child: Text(_cutterLabel(option)),
                ),
            ],
            onChanged: authorized && !busy
                ? (value) {
                    if (value != null) setState(() => cutter = value);
                  }
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PrinterBeepCapability>(
            key: const ValueKey('printer-route-beep-capability'),
            initialValue: beepCapability,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ხმის თავსებადობა'),
            items: [
              for (final capability in PrinterBeepCapability.values)
                DropdownMenuItem(
                  value: capability,
                  child: Text(
                    _beepLabel(capability),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: authorized && !busy
                ? (value) {
                    if (value == null) return;
                    setState(() {
                      beepCapability = value;
                      beepCompatibilityConfirmed = false;
                      beepEnabled = false;
                    });
                  }
                : null,
          ),
          if (beepCapability == PrinterBeepCapability.epsonEscA97Pattern)
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const ValueKey('printer-route-beep-compatibility'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'დადასტურებულია Epson ESC ( A fn=97 რეგისტრირებული პატერნისა და დაყენებული ზუმერის თავსებადობა',
                ),
                value: beepCompatibilityConfirmed,
                onChanged: authorized && !busy
                    ? (value) => setState(() {
                        beepCompatibilityConfirmed = value == true;
                        if (!beepCompatibilityConfirmed) beepEnabled = false;
                      })
                    : null,
              ),
            ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('printer-route-beep-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('ხმის სიგნალის ჩართვა'),
              subtitle: const Text(
                'ხმა ნაგულისხმევად გამორთულია. უცნობი ან შეუთავსებელი მხარდაჭერა ხმას არ აგზავნის.',
              ),
              value: beepEnabled,
              onChanged:
                  authorized &&
                      !busy &&
                      beepCompatibilityConfirmed &&
                      beepCapability == PrinterBeepCapability.epsonEscA97Pattern
                  ? (value) => setState(() => beepEnabled = value)
                  : null,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            children: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('გაუქმება'),
              ),
              FilledButton(
                key: const ValueKey('printer-route-save'),
                onPressed:
                    authorized &&
                        !busy &&
                        !inventoryBusy &&
                        !LocalPrinterCatalog.cloudOwnsRole(role) &&
                        (beepCapability !=
                                PrinterBeepCapability.epsonEscA97Pattern ||
                            beepCompatibilityConfirmed) &&
                        (transport == PrinterTransportKind.tcp ||
                            selectedQueue != null)
                    ? _save
                    : null,
                child: Text(busy ? 'ინახება...' : 'შენახვა'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
