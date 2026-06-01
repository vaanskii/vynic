import 'package:flutter/material.dart';

class ServiceFeeAdjustResult {
  final bool includeServiceFee;
  final double percentage;

  const ServiceFeeAdjustResult({
    required this.includeServiceFee,
    required this.percentage,
  });
}

class ServiceFeeAdjustDialog extends StatefulWidget {
  const ServiceFeeAdjustDialog({
    super.key,
    required this.initialIncludeServiceFee,
    required this.initialPercentage,
    required this.defaultPercentage,
  });

  final bool initialIncludeServiceFee;
  final double initialPercentage;
  final double defaultPercentage;

  @override
  State<ServiceFeeAdjustDialog> createState() => _ServiceFeeAdjustDialogState();
}

class _ServiceFeeAdjustDialogState extends State<ServiceFeeAdjustDialog> {
  late bool _includeServiceFee;
  late TextEditingController _percentageController;

  static const List<double> _quickValues = [5, 10, 15, 20, 25, 30];

  @override
  void initState() {
    super.initState();
    _includeServiceFee = widget.initialIncludeServiceFee;
    _percentageController = TextEditingController(
      text: _formatPercentage(widget.initialPercentage),
    );
  }

  @override
  void dispose() {
    _percentageController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final current = _normalizedPercentage;
    return _includeServiceFee != widget.initialIncludeServiceFee ||
        (current - widget.initialPercentage).abs() > 0.009;
  }

  double get _normalizedPercentage {
    final parsed =
        double.tryParse(_percentageController.text.trim()) ??
        widget.initialPercentage;
    final clamped = parsed.clamp(0.0, 100.0).toDouble();
    return double.parse(clamped.toStringAsFixed(2));
  }

  bool get _canConfirm => _normalizedPercentage >= 0;

  Future<void> _handleCancel() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ცვლილებების გაუქმება'),
        content: const Text(
          'ცვლილებები არ არის შენახული. ნამდვილად გსურთ გასვლა?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('დაბრუნება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('გასვლა'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _applyQuickValue(double value) {
    setState(() {
      _percentageController.text = _formatPercentage(value);
    });
  }

  String _formatPercentage(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _handleCancel();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 26,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'სერვისის კონფიგურაცია',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage service fee for this table only',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'სერვისი',
                            style: TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'ჩართე ან გამორთე ამ მაგიდაზე',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _includeServiceFee,
                      onChanged: (value) {
                        setState(() {
                          _includeServiceFee = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'პროცენტი (%)',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _percentageController,
                enabled: _includeServiceFee,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'მაგ: 10, 15, 20',
                  suffixText: '%',
                  filled: true,
                  fillColor: _includeServiceFee
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2563EB)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickValues
                    .map(
                      (value) => ChoiceChip(
                        label: Text('${value.toStringAsFixed(0)}%'),
                        selected:
                            (_normalizedPercentage - value).abs() <= 0.009,
                        onSelected: _includeServiceFee
                            ? (_) => _applyQuickValue(value)
                            : null,
                        selectedColor: const Color(0xFFDBEAFE),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          color: (_normalizedPercentage - value).abs() <= 0.009
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF334155),
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide.none,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _includeServiceFee
                    ? () => _applyQuickValue(widget.defaultPercentage)
                    : null,
                child: Text(
                  'გამოიყენე დეფოლტი (${_formatPercentage(widget.defaultPercentage)}%)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _handleCancel,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF6B7280),
                      ),
                      label: const Text(
                        'გაუქმება',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _canConfirm
                          ? () {
                              Navigator.of(context).pop(
                                ServiceFeeAdjustResult(
                                  includeServiceFee: _includeServiceFee,
                                  percentage: _normalizedPercentage,
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('დადასტურება'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
