import 'package:vynic/apps/mobile_app/core/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/widgets/manager_toast.dart';


/// Full-screen, dark "glass" reservation creation form. Slides in from right.
class ReservationCreateScreen extends StatefulWidget {
  const ReservationCreateScreen({
    super.key,
    required this.user,
    required this.initialDate,
  });

  final User user;
  final DateTime initialDate;

  static Route<bool> route({
    required User user,
    required DateTime initialDate,
  }) {
    return PageRouteBuilder<bool>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => managerThemedPage(
            ReservationCreateScreen(user: user, initialDate: initialDate),
          ),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  State<ReservationCreateScreen> createState() =>
      _ReservationCreateScreenState();
}

class _ReservationCreateScreenState extends State<ReservationCreateScreen> {
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _tableNumbersController = TextEditingController();
  final TextEditingController _guestsController =
      TextEditingController(text: '2');
  final TextEditingController _notesController = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  late DateTime _selectedDate;
  final List<_DraftMenuItem> _selectedMenuItems = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _tableNumbersController.dispose();
    _guestsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _timeAsText(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  DateTime _businessNow() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    if (raw != null && raw.trim().isNotEmpty) {
      final parts = raw.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
    }
    return DateTime.now();
  }

  List<int> _parseTableNumbers(String raw) {
    return raw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
  }

  double get _preOrderTotal => _selectedMenuItems.fold<double>(
      0, (sum, e) => sum + e.price * e.qty);

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ManagerToast.showSnackBar(context, msg, isError: error);
  }

  Future<void> _pickDate() async {
    final businessDate = _businessNow();
    final initial =
        _selectedDate.isBefore(businessDate) ? businessDate : _selectedDate;
    if (!kIsWeb && Platform.isIOS) {
      DateTime temp = initial;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: MobileGlassTheme.data.surfaceCard,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('გაუქმება',
                            style: TextStyle(color: MobileGlassTheme.textSecondary)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedDate =
                              DateTime(temp.year, temp.month, temp.day));
                          Navigator.pop(ctx);
                        },
                        child: Text('არჩევა',
                            style: TextStyle(color: MobileGlassTheme.accentText)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(brightness: Brightness.dark),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      minimumDate: DateTime(businessDate.year,
                          businessDate.month, businessDate.day),
                      initialDateTime: initial,
                      onDateTimeChanged: (value) => temp = value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      firstDate:
          DateTime(businessDate.year, businessDate.month, businessDate.day),
      lastDate: businessDate.add(const Duration(days: 365)),
      initialDate: initial,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: MobileGlassTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    DateTime temp = DateTime(_selectedDate.year, _selectedDate.month,
        _selectedDate.day, _selectedTime.hour, _selectedTime.minute);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobileGlassTheme.data.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: MobileGlassTheme.muted(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('გაუქმება',
                          style: TextStyle(color: MobileGlassTheme.textSecondary)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedTime = TimeOfDay(
                            hour: temp.hour, minute: temp.minute));
                        Navigator.pop(ctx);
                      },
                      child: Text('არჩევა',
                          style: TextStyle(color: MobileGlassTheme.accentText)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(brightness: Brightness.dark),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: temp,
                    onDateTimeChanged: (value) => temp = value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenuPicker() async {
    final selected = await Navigator.of(context).push<List<MenuSelectionLine>>(
      MaterialPageRoute(
        builder: (_) => managerThemedPage(
          MobileCalculatorScreen(
          selectionMode: true,
          initialSelection: _selectedMenuItems
              .map((e) => MenuSelectionLine(
                    key: '${e.name}_${e.price}',
                    itemName: e.name,
                    unitPrice: e.price,
                    qty: e.qty,
                  ))
              .toList(),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMenuItems
        ..clear()
        ..addAll(selected.map((e) => _DraftMenuItem(
              name: e.itemName,
              price: e.unitPrice,
              qty: e.qty,
            )));
    });
  }

  Future<void> _createReservation() async {
    final name = _customerNameController.text.trim();
    final phone = _customerPhoneController.text.trim();
    final tables = _parseTableNumbers(_tableNumbersController.text);
    final guests = int.tryParse(_guestsController.text.trim()) ?? 0;
    if (name.isEmpty || guests <= 0) {
      _toast('შეავსეთ სახელი და სტუმრების რაოდენობა', error: true);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await MobileApiService.createReservation(
        customerName: name,
        customerPhone: phone,
        tableNumbers: tables,
        reservationDate: _dateFmt.format(_selectedDate),
        reservationTime: _timeAsText(_selectedTime),
        numberOfGuests: guests,
        notes: _notesController.text.trim(),
        createdBy: widget.user.username,
        preOrderItems: _selectedMenuItems
            .map((e) => {
                  'itemKey': '${e.name}_${e.price.toStringAsFixed(2)}',
                  'itemName': e.name,
                  'unitPrice': e.price,
                  'quantity': e.qty,
                  'total': e.price * e.qty,
                  'comment': null,
                })
            .toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _toast('რეზერვაციის შექმნა ვერ მოხერხდა', error: true);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileGlassTheme.bg,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            left: -60,
            child: _GlowOrb(color: MobileGlassTheme.primary, size: 280),
          ),
          Positioned(
            bottom: 80,
            right: -90,
            child: _GlowOrb(color: Color(0xFF10B981), size: 240),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                  child: Row(
                    children: [
                      _GlassCircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'ახალი რეზერვაცია',
                        style: TextStyle(
                          color: MobileGlassTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      _GlassCard(
                        child: Column(
                          children: [
                            _field(_customerNameController, 'კლიენტის სახელი',
                                icon: Icons.person_outline_rounded),
                            SizedBox(height: 12),
                            _field(_customerPhoneController, 'ტელეფონი',
                                icon: Icons.phone_outlined, phone: true),
                            SizedBox(height: 12),
                            _field(_tableNumbersController,
                                'მაგიდები (არასავალდებულო: 1,2,3)',
                                icon: Icons.table_bar_outlined),
                            SizedBox(height: 12),
                            _field(_guestsController, 'სტუმრები',
                                icon: Icons.groups_outlined, number: true),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _pickerTile(
                              icon: Icons.calendar_today_rounded,
                              label: 'თარიღი',
                              value: _dateFmt.format(_selectedDate),
                              onTap: _pickDate,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _pickerTile(
                              icon: Icons.schedule_rounded,
                              label: 'დრო',
                              value: _timeAsText(_selectedTime),
                              onTap: _pickTime,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      _GlassCard(
                        child: _field(_notesController, 'შენიშვნა',
                            icon: Icons.notes_rounded, maxLines: 2),
                      ),
                      SizedBox(height: 16),
                      _buildPreOrder(),
                      SizedBox(height: 24),
                      _primaryButton(
                        label: _isSubmitting
                            ? 'ინახება...'
                            : 'რეზერვაციის შექმნა',
                        onTap: _isSubmitting ? null : _createReservation,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreOrder() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu_rounded,
                  color: MobileGlassTheme.accentText, size: 18),
              SizedBox(width: 8),
              Text(
                'წინასწარი შეკვეთა',
                style: TextStyle(
                    color: MobileGlassTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
              const Spacer(),
              if (_selectedMenuItems.isNotEmpty)
                Text(
                  '₾${_preOrderTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: MobileGlassTheme.good, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          SizedBox(height: 12),
          if (_selectedMenuItems.isEmpty)
            Text(
              'პოზიციები არჩეული არ არის',
              style:
                  TextStyle(color: MobileGlassTheme.muted(0.5), fontSize: 13),
            )
          else
            ..._selectedMenuItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 14),
                      ),
                    ),
                    _qtyBtn(Icons.remove_rounded, () {
                      setState(() {
                        if (item.qty <= 1) {
                          _selectedMenuItems.removeAt(idx);
                        } else {
                          _selectedMenuItems[idx] =
                              item.copyWith(qty: item.qty - 1);
                        }
                      });
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${item.qty}',
                          style: TextStyle(
                              color: MobileGlassTheme.textPrimary,
                              fontWeight: FontWeight.bold)),
                    ),
                    _qtyBtn(Icons.add_rounded, () {
                      setState(() => _selectedMenuItems[idx] =
                          item.copyWith(qty: item.qty + 1));
                    }),
                  ],
                ),
              );
            }),
          SizedBox(height: 8),
          _outlineButton(
            icon: Icons.add_rounded,
            label: 'მენიუდან არჩევა',
            onTap: _openMenuPicker,
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: MobileGlassTheme.surface(0.06),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: MobileGlassTheme.data.borderSubtle),
        ),
        child: Icon(icon, size: 16, color: MobileGlassTheme.textPrimary),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return _GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: MobileGlassTheme.accentText, size: 18),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 11)),
              Text(value,
                  style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData? icon,
    bool number = false,
    bool phone = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: number
          ? TextInputType.number
          : phone
              ? TextInputType.phone
              : null,
      style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 15),
      cursorColor: MobileGlassTheme.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 13),
        prefixIcon: icon != null
            ? Icon(icon, color: MobileGlassTheme.muted(0.4), size: 20)
            : null,
        filled: true,
        fillColor: MobileGlassTheme.surface(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobileGlassTheme.data.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobileGlassTheme.primary),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: MobileGlassTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MobileGlassTheme.primary.withValues(alpha: 0.4),
          disabledForegroundColor: MobileGlassTheme.textSecondary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: MobileGlassTheme.accentText,
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: MobileGlassTheme.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _DraftMenuItem {
  final String name;
  final double price;
  final int qty;
  const _DraftMenuItem(
      {required this.name, required this.price, required this.qty});

  _DraftMenuItem copyWith({String? name, double? price, int? qty}) =>
      _DraftMenuItem(
        name: name ?? this.name,
        price: price ?? this.price,
        qty: qty ?? this.qty,
      );
}

/// ── shared dark glass widgets ───────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const _GlassCard({
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final radius = BorderRadius.circular(20);
    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.useGlassCards
            ? MobileGlassTheme.surface(0.04)
            : theme.heroCardBackground,
        borderRadius: radius,
        border: Border.all(color: theme.cardBorder, width: 1),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: theme.cardShadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
    if (theme.useGlassCards) {
      card = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: card,
        ),
      );
    } else {
      card = ClipRRect(borderRadius: radius, child: card);
    }
    if (onTap != null) {
      card = GestureDetector(
          onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
    }
    return card;
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    Widget btn = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.headerButtonBackground,
        border: Border.all(color: theme.cardBorder),
      ),
      child: Icon(icon, color: theme.textPrimary, size: 18),
    );
    if (theme.useGlassCards) {
      btn = ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: btn,
        ),
      );
    } else {
      btn = ClipOval(child: btn);
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: btn,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
