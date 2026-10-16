import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'shared/pos_guest_fields.dart';
import 'time_entry_pad.dart';
import 'package:uuid/uuid.dart';

class ReservationCreationSheet extends StatefulWidget {
  final VoidCallback? onCancel;
  final String title;
  final String confirmLabel;
  final String? initialName;
  final String? initialPhone;
  final String? initialNotes;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final int? initialGuests;
  final bool showFinancialFields;
  final String? requestId;
  final String initialStatus;
  final double initialAdvanceAmount;

  const ReservationCreationSheet({
    super.key,
    this.onCancel,
    this.title = 'ახალი რეზერვაცია',
    this.confirmLabel = 'რეზერვაციის შექმნა',
    this.initialName,
    this.initialPhone,
    this.initialNotes,
    this.initialDate,
    this.initialTime,
    this.initialGuests,
    this.showFinancialFields = true,
    this.requestId,
    this.initialStatus = 'confirmed',
    this.initialAdvanceAmount = 0,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required ReservationCreationSheet form,
  }) => showPosModal<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => form,
  );

  @override
  State<ReservationCreationSheet> createState() =>
      _ReservationCreationSheetState();
}

class _ReservationCreationSheetState extends State<ReservationCreationSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _guestsController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController(
    text: '0',
  );
  late final String _requestId;
  bool _tentativeHold = false;
  bool _submitted = false;
  bool _closing = false;
  String? _error;
  final _errorKey = GlobalKey();
  final _nameFocus = FocusNode();
  late final bool _initialHold;
  late final String _initialAdvance;

  DateTime _selectedDate = _normalizeDate(DatabaseService.getCurrentDate());
  late final String _initialName;
  late final String _initialPhone;
  late final String _initialNotes;
  late final String _initialTime;
  late final String _initialGuests;
  late final DateTime _initialDate;

  @override
  void initState() {
    super.initState();
    _requestId = widget.requestId ?? const Uuid().v4();
    _tentativeHold =
        widget.showFinancialFields && widget.initialStatus == 'hold';
    _advanceController.text = widget.initialAdvanceAmount == 0
        ? '0'
        : widget.initialAdvanceAmount.toStringAsFixed(2);
    _initialHold = _tentativeHold;
    _initialAdvance = _advanceController.text;
    _nameController.text = (widget.initialName ?? '').trim();
    _phoneController.text = _digitsOnly(widget.initialPhone ?? '');
    _notesController.text = (widget.initialNotes ?? '').trim();

    final today = _normalizeDate(DatabaseService.getCurrentDate());
    if (widget.initialDate != null) {
      _selectedDate = _normalizeDate(widget.initialDate!);
    }
    if (_selectedDate.isBefore(today)) {
      _selectedDate = today;
    }

    if (widget.initialTime != null) {
      _timeController.text = _formatTimeOfDay(widget.initialTime!);
    }

    final initialGuests =
        (widget.initialGuests != null && widget.initialGuests! > 0)
        ? widget.initialGuests!
        : "";
    _guestsController.text = initialGuests.toString();

    _initialName = _nameController.text.trim();
    _initialPhone = _phoneController.text.trim();
    _initialNotes = _notesController.text.trim();
    _initialTime = _timeController.text.trim();
    _initialGuests = _guestsController.text.trim();
    _initialDate = _selectedDate;
  }

  static DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _advanceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _timeController.dispose();
    _guestsController.dispose();
    super.dispose();
  }

  String _digitsOnly(String value) {
    final trimmed = value.trim();
    if (trimmed == '?') return '?';
    return trimmed.replaceAll(RegExp(r'\D+'), '');
  }

  Future<void> _selectTime() async {
    final result = await showPosModal<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TimeEntryDialog(initialTime: _timeController.text),
    );

    if (result != null && mounted) {
      setState(() {
        _timeController.text = result;
      });
    }
  }

  TimeOfDay? _tryParseTime(String raw) {
    final value = raw.trim();
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _submit() {
    if (_submitted) return;
    final advance = widget.showFinancialFields
        ? double.tryParse(_advanceController.text.replaceAll(',', '.'))
        : 0.0;
    if (advance == null ||
        !advance.isFinite ||
        advance < 0 ||
        advance > 999999999.99) {
      _showError('ავანსი უნდა იყოს არაუარყოფითი თანხა');
      return;
    }
    if (_tentativeHold &&
        !_selectedDate.isAfter(
          _normalizeDate(DatabaseService.getCurrentDate()),
        )) {
      _showError('დროებითი დაკავებისთვის აირჩიეთ მომავალი თარიღი');
      return;
    }
    final nameValue = _nameController.text.trim();
    if (nameValue.isEmpty) {
      _showError('გთხოვთ შეიყვანოთ სტუმრის სახელი');
      _nameFocus.requestFocus();
      return;
    }

    final time = _tryParseTime(_timeController.text);
    if (time == null) {
      _showError('გთხოვთ მიუთითოთ სწორი დრო (საათი:წუთი)');
      return;
    }

    final guestCount = int.tryParse(_guestsController.text.trim());
    if (guestCount == null || guestCount <= 0) {
      _showError('გთხოვთ მიუთითოთ სტუმრების სწორი რაოდენობა');
      return;
    }

    final result = {
      'id': _requestId,
      'status': _tentativeHold ? 'hold' : 'confirmed',
      'advanceAmount': advance,
      'customerName': nameValue,
      'customerPhone': _digitsOnly(_phoneController.text),
      'notes': _notesController.text.trim(),
      'date': _selectedDate,
      'time': time,
      'guests': guestCount,
      'numberOfGuests': guestCount,
    };

    _submitted = true;
    Navigator.pop(context, result);
  }

  bool _hasUnsavedChanges() {
    if (_tentativeHold != _initialHold) return true;
    if (_advanceController.text.trim() != _initialAdvance) return true;
    if (_nameController.text.trim() != _initialName) return true;
    if (_phoneController.text.trim() != _initialPhone) return true;
    if (_notesController.text.trim() != _initialNotes) return true;
    if (_timeController.text.trim() != _initialTime) return true;
    if (_guestsController.text.trim() != _initialGuests) return true;
    if (!_selectedDate.isAtSameMomentAs(_initialDate)) return true;
    return false;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges()) {
      return true;
    }

    final confirm = await showPosModal<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const PosText(
          'დახურვის დადასტურება',
          style: TextStyle(color: VynicFloorTokens.text),
        ),
        content: const PosText(
          'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
          style: TextStyle(color: VynicFloorTokens.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const PosText('გაგრძელება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: VynicFloorTokens.dangerText,
              foregroundColor: Colors.white,
            ),
            child: const PosText('დახურვა'),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  void _showError(String message) {
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final errorContext = _errorKey.currentContext;
      if (mounted && errorContext != null)
        Scrollable.ensureVisible(errorContext);
    });
  }

  Future<void> _handleCancelRequested() async {
    if (_closing || _submitted) return;
    _closing = true;
    final shouldClose = await _confirmDiscardIfNeeded();
    _closing = false;
    if (!shouldClose || !mounted) return;
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _selectDate() async {
    final today = _normalizeDate(DatabaseService.getCurrentDate());
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      builder: (_, child) => PosDialogTheme(child: child!),
    );
    if (date != null && mounted)
      setState(() => _selectedDate = _normalizeDate(date));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_handleCancelRequested());
    },
    child: PosFormDialog(
      bodyKey: const Key('reservation-compact-form'),
      title: widget.title,
      onClose: _handleCancelRequested,
      actions: [
        TextButton(
          onPressed: _handleCancelRequested,
          child: const PosText('გაუქმება'),
        ),
        ElevatedButton(onPressed: _submit, child: PosText(widget.confirmLabel)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            PosFormError(_error!, key: _errorKey),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final date = OutlinedButton.icon(
                key: const Key('reservation-date'),
                onPressed: _selectDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: PosText(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
              );
              final time = TextField(
                controller: _timeController,
                readOnly: true,
                onTap: _selectTime,
                decoration: const InputDecoration(
                  labelText: 'დრო',
                  hintText: 'საათი:წუთი',
                  prefixIcon: Icon(Icons.schedule),
                ),
              );
              return constraints.maxWidth < 400
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [date, const SizedBox(height: 16), time],
                    )
                  : Row(
                      children: [
                        Expanded(child: date),
                        const SizedBox(width: 16),
                        Expanded(child: time),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
          PosGuestFields(
            name: _nameController,
            phone: _phoneController,
            nameFocus: _nameFocus,
            allowUnknownPhone: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                key: const Key('reservation-guests-minus'),
                tooltip: 'სტუმრის გამოკლება',
                onPressed: () {
                  final current = int.tryParse(_guestsController.text) ?? 1;
                  _guestsController.text = '${(current - 1).clamp(1, 999)}';
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: PosOnScreenTextField(
                  controller: _guestsController,
                  mode: PosInputMode.number,
                  decoration: const InputDecoration(
                    labelText: 'სტუმრების რაოდენობა',
                    hintText: 'სტუმრების რაოდენობა',
                    prefixIcon: Icon(Icons.groups_2_outlined),
                  ),
                ),
              ),
              IconButton(
                key: const Key('reservation-guests-plus'),
                tooltip: 'სტუმრის დამატება',
                onPressed: () {
                  final current = int.tryParse(_guestsController.text) ?? 0;
                  _guestsController.text = '${(current + 1).clamp(1, 999)}';
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (widget.showFinancialFields) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const PosText('დროებითი დაკავება (hold)'),
              subtitle: const PosText(
                'მომავალი თარიღი • დადასტურებული ჯავშნისგან ცალკე',
              ),
              value: _tentativeHold,
              onChanged: (value) =>
                  setState(() => _tentativeHold = value ?? false),
            ),
            const SizedBox(height: 12),
            PosOnScreenTextField(
              controller: _advanceController,
              mode: PosInputMode.decimal,
              decoration: const InputDecoration(
                labelText: 'მიღებული ავანსი (₾)',
                helperText:
                    'მხოლოდ უკვე მიღებული თანხა • ანგარიშში ერთხელ ჩაითვლება',
              ),
            ),
          ],
          const SizedBox(height: 24),
          PosOnScreenTextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'შენიშვნები',
              hintText: 'დამატებითი ინფორმაცია...',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
    ),
  );
}
