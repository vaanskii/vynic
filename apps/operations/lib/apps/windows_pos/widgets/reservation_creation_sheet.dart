import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'time_entry_pad.dart';

// The sheet used to carry its own slate-and-blue palette, which read as a
// different product from the screen that opened it. It now draws from the
// same tokens as the order detail and floor screens, so „დეტალების შეცვლა"
// looks like it belongs to the page behind it.
const Color _reservationAccent = VynicFloorTokens.accentStrong;
const Color _reservationSurface = VynicFloorTokens.panel;
const Color _reservationSurfaceAlt = VynicFloorTokens.metricFill;
const Color _reservationOutline = VynicFloorTokens.panelBorder;
const Color _reservationLabel = VynicFloorTokens.textMuted;
const Color _reservationMuted = VynicFloorTokens.textFaint;
const Color _reservationTextPrimary = VynicFloorTokens.text;

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
  });

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
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TimeEntryDialog(initialTime: _timeController.text),
    );

    if (result != null) {
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
    final nameValue = _nameController.text.trim();
    if (nameValue.isEmpty) {
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ შეიყვანოთ სტუმრის სახელი',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final time = _tryParseTime(_timeController.text);
    if (time == null) {
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ მიუთითოთ სწორი დრო (საათი:წუთი)',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final guestCount = int.tryParse(_guestsController.text.trim());
    if (guestCount == null || guestCount <= 0) {
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ მიუთითოთ სტუმრების სწორი რაოდენობა',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final result = {
      'customerName': nameValue,
      'customerPhone': _digitsOnly(_phoneController.text),
      'notes': _notesController.text.trim(),
      'date': _selectedDate,
      'time': time,
      'guests': guestCount,
      'numberOfGuests': guestCount,
    };

    Navigator.pop(context, result);
  }

  bool _hasUnsavedChanges() {
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

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _reservationSurface,
        title: const PosText(
          'დახურვის დადასტურება',
          style: TextStyle(color: _reservationTextPrimary),
        ),
        content: const PosText(
          'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
          style: TextStyle(color: _reservationLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const PosText('გაგრძელება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const PosText('დახურვა'),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  Future<void> _handleCancelRequested() async {
    final shouldClose = await _confirmDiscardIfNeeded();
    if (!shouldClose || !mounted) {
      return;
    }
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_reservationSurface, _reservationSurfaceAlt],
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: const BoxDecoration(
                  color: _reservationSurface,
                  border: Border(
                    bottom: BorderSide(color: _reservationOutline),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PosText(
                      widget.title,
                      style: const TextStyle(
                        color: _reservationAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    IconButton(
                      onPressed: _handleCancelRequested,
                      icon: const Icon(Icons.close, color: _reservationMuted),
                      tooltip: 'დახურვა',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('თარიღი'),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final today = _normalizeDate(
                                DatabaseService.getCurrentDate(),
                              );
                              final initialDate = _selectedDate.isBefore(today)
                                  ? today
                                  : _selectedDate;
                              final date = await showDatePicker(
                                context: context,
                                initialDate: initialDate,
                                firstDate: today,
                                lastDate: today.add(const Duration(days: 365)),
                                builder: (context, child) {
                                  final base = Theme.of(context);
                                  return Theme(
                                    data: base.copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: _reservationAccent,
                                        onPrimary: Colors.white,
                                        surface: _reservationSurface,
                                        onSurface: _reservationTextPrimary,
                                      ),
                                      datePickerTheme:
                                          const DatePickerThemeData(
                                            backgroundColor:
                                                _reservationSurfaceAlt,
                                          ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (date != null) {
                                setState(() {
                                  _selectedDate = _normalizeDate(date);
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _reservationSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _reservationOutline),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x11000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: _reservationAccent,
                                  ),
                                  const SizedBox(width: 12),
                                  PosText(
                                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                    style: const TextStyle(
                                      color: _reservationTextPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('დრო'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _timeController,
                            hint: 'საათი:წუთი',
                            icon: Icons.access_time,
                            onTap: _selectTime,
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('სტუმრის სახელი'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _nameController,
                            hint: 'შეიყვანეთ სახელი',
                            icon: Icons.person,
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('ტელეფონი'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _phoneController,
                            hint: 'შეიყვანეთ ტელეფონის ნომერი',
                            icon: Icons.phone,
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('სტუმრების რაოდენობა'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _guestsController,
                            hint: 'შეიყვანეთ სტუმრების რაოდენობა',
                            icon: Icons.groups_2_outlined,
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('შენიშვნები'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _notesController,
                            hint: 'დამატებითი ინფორმაცია...',
                            icon: Icons.note,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                decoration: const BoxDecoration(
                  color: _reservationSurface,
                  border: Border(top: BorderSide(color: _reservationOutline)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _handleCancelRequested,
                      style: TextButton.styleFrom(
                        foregroundColor: _reservationMuted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: const PosText('გაუქმება'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _reservationAccent,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: PosText(widget.confirmLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return PosText(
      text,
      style: const TextStyle(
        color: _reservationLabel,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    VoidCallback? onTap,
    int maxLines = 1,
  }) {
    if (controller == _timeController) {
      return TextField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      );
    }
    return PosOnScreenTextField(
      controller: controller,
      maxLines: maxLines,
      allowQuestionMark: controller == _phoneController,
      mode: controller == _phoneController || controller == _guestsController
          ? PosInputMode.number
          : PosInputMode.text,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
