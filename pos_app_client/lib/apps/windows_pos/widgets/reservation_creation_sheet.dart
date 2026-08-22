import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'on_screen_keyboard.dart';
import 'time_entry_pad.dart';

// The sheet used to carry its own slate-and-blue palette, which read as a
// different product from the screen that opened it. It now draws from the
// same tokens as the order detail and floor screens, so „დეტალების შეცვლა"
// looks like it belongs to the page behind it.
const Color _reservationAccent = VynicFloorTokens.accentStrong;
const Color _reservationAccentSoft = VynicFloorTokens.accentText;
const Color _reservationSurface = VynicFloorTokens.panel;
const Color _reservationSurfaceAlt = VynicFloorTokens.metricFill;
const Color _reservationOutline = VynicFloorTokens.panelBorder;
const Color _reservationLabel = VynicFloorTokens.textMuted;
const Color _reservationMuted = VynicFloorTokens.textFaint;
const Color _reservationTextPrimary = VynicFloorTokens.text;
const double _reservationKeyboardHeight = 380;

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

  TextEditingController? _activeController;

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

  void _setActiveField(TextEditingController controller) {
    FocusScope.of(context).unfocus();
    setState(() {
      _activeController = controller;
    });
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  void _closeKeyboard() {
    setState(() {
      _activeController = null;
    });
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D+'), '');
  }

  Future<void> _openPhoneKeyboard() async {
    _closeKeyboard();

    final updated = await showPosNumberKeyboardInputSheet(
      context: context,
      initialValue: _phoneController.text,
      title: 'ტელეფონის ნომერი',
      maxDigits: 15,
    );

    if (!mounted || updated == null) {
      return;
    }

    final sanitized = _digitsOnly(updated);
    setState(() {
      _phoneController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    });
  }

  Future<void> _selectTime() async {
    _closeKeyboard();

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
        title: const Text(
          'დახურვის დადასტურება',
          style: TextStyle(color: _reservationTextPrimary),
        ),
        content: const Text(
          'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
          style: TextStyle(color: _reservationLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაგრძელება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('დახურვა'),
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
    final double dynamicBottomPadding = _activeController != null
        ? _reservationKeyboardHeight + 48
        : 24;

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
                    Text(
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
                      padding: EdgeInsets.fromLTRB(
                        24,
                        24,
                        24,
                        dynamicBottomPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('თარიღი'),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              _closeKeyboard();
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
                                  Text(
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
                            onTap: () => _setActiveField(_nameController),
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('ტელეფონი'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _phoneController,
                            hint: 'შეიყვანეთ ტელეფონის ნომერი',
                            icon: Icons.phone,
                            onTap: _openPhoneKeyboard,
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('სტუმრების რაოდენობა'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _guestsController,
                            hint: 'შეიყვანეთ სტუმრების რაოდენობა',
                            icon: Icons.groups_2_outlined,
                            onTap: () => _setActiveField(_guestsController),
                          ),
                          const SizedBox(height: 20),
                          _buildLabel('შენიშვნები'),
                          const SizedBox(height: 8),
                          _buildInputField(
                            controller: _notesController,
                            hint: 'დამატებითი ინფორმაცია...',
                            icon: Icons.note,
                            maxLines: 3,
                            onTap: () => _setActiveField(_notesController),
                          ),
                        ],
                      ),
                    ),
                    if (_activeController != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 12,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _reservationSurfaceAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _reservationOutline),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.keyboard_outlined,
                                        size: 18,
                                        color: _reservationMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _activeController == _nameController
                                            ? 'სტუმრის სახელი'
                                            : _activeController ==
                                                  _phoneController
                                            ? 'ტელეფონი'
                                            : _activeController ==
                                                  _guestsController
                                            ? 'სტუმრების რაოდენობა'
                                            : 'შენიშვნები',
                                        style: const TextStyle(
                                          color: _reservationLabel,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        onPressed: _closeKeyboard,
                                        icon: const Icon(Icons.close, size: 18),
                                        color: _reservationMuted,
                                      ),
                                    ],
                                  ),
                                ),
                                OnScreenKeyboard(
                                  controller: _activeController!,
                                  language: 'ka',
                                  onClose: _closeKeyboard,
                                  showHeader: false,
                                ),
                              ],
                            ),
                          ),
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
                      child: const Text('გაუქმება'),
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
                      child: Text(widget.confirmLabel),
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
    return Text(
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
    required VoidCallback onTap,
    int maxLines = 1,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final isActive = _activeController == controller;
          final displayText = value.text;
          final isEmpty = displayText.isEmpty;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _reservationSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? _reservationAccent : _reservationOutline,
                width: isActive ? 2 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _reservationAccentSoft.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: Row(
              crossAxisAlignment: maxLines > 1
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? _reservationAccent : _reservationMuted,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isEmpty ? hint : displayText,
                    style: TextStyle(
                      color: isEmpty
                          ? _reservationMuted
                          : _reservationTextPrimary,
                      fontSize: 17,
                      height: maxLines > 1 ? 1.4 : 1.2,
                    ),
                    maxLines: maxLines,
                    overflow: maxLines == 1
                        ? TextOverflow.ellipsis
                        : TextOverflow.visible,
                  ),
                ),
                if (isActive)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 2,
                    height: maxLines > 1 ? 32 : 22,
                    margin: const EdgeInsets.only(left: 8),
                    color: _reservationAccent,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
