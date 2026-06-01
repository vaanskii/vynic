import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

enum TablePaymentMethod { cash, bank, split }

class TablePaymentSelection {
  final TablePaymentMethod method;
  final double cashAmount;
  final double bankAmount;
  final String? bankProvider;

  const TablePaymentSelection({
    required this.method,
    required this.cashAmount,
    required this.bankAmount,
    this.bankProvider,
  });

  double get total =>
      double.parse((cashAmount + bankAmount).toStringAsFixed(2));

  bool get hasBankPortion => bankAmount > 0;
  bool get hasCashPortion => cashAmount > 0;
}

class TablePaymentService {
  TablePaymentService({required this.context, required this.total});

  final BuildContext context;
  final double total;

  static const double _amountTolerance = 0.01;

  Future<TablePaymentSelection?> collect() async {
    if (total <= 0) {
      await showErrorToast(context, 'გადახდამდე გადათვალეთ შეკვეთის ჯამი');
      return null;
    }

    while (true) {
      final method = await _showMethodDialog();
      if (method == null) {
        return null;
      }

      switch (method) {
        case TablePaymentMethod.cash:
          final confirm = await _showConfirmationDialog('ნაღდი / Cash');
          if (!confirm) return null;
          return TablePaymentSelection(
            method: TablePaymentMethod.cash,
            cashAmount: _round(total),
            bankAmount: 0,
          );
        case TablePaymentMethod.bank:
          final bank = await _showBankDialog();
          // Returning from bank terminal selection should go back to method choice.
          if (bank == null) {
            continue;
          }
          final confirm = await _showConfirmationDialog(
            'ბანკი / Bank POS (${bank.toUpperCase()})',
          );
          if (!confirm) return null;
          return TablePaymentSelection(
            method: TablePaymentMethod.bank,
            cashAmount: 0,
            bankAmount: _round(total),
            bankProvider: bank,
          );
        case TablePaymentMethod.split:
          final selection = await _showSplitDialog();
          // Returning from split dialog should go back to method choice.
          if (selection == null) {
            continue;
          }
          final confirm = await _showConfirmationDialog(
            'გაყოფილი / Split Payment',
          );
          if (!confirm) return null;
          return selection;
      }
    }
  }

  Future<TablePaymentMethod?> _showMethodDialog() {
    return showDialog<TablePaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 600, // Reduced from 720
            padding: const EdgeInsets.all(24), // Reduced from 32
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 30,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'აირჩიეთ გადახდის მეთოდი',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select Payment Method',
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'ნაღდი ფული',
                      englishLabel: 'Cash Payment',
                      icon: Icons.payments_rounded,
                      color: const Color(0xFF10B981),
                      method: TablePaymentMethod.cash,
                    ),
                    const SizedBox(width: 20),
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'ბარათით',
                      englishLabel: 'Bank POS',
                      icon: Icons.credit_card_rounded,
                      color: const Color(0xFF3B82F6),
                      method: TablePaymentMethod.bank,
                    ),
                    const SizedBox(width: 20),
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'გაყოფილი',
                      englishLabel: 'Split Bill',
                      icon: Icons.call_split_rounded,
                      color: const Color(0xFF8B5CF6),
                      method: TablePaymentMethod.split,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.black54,
                    size: 20,
                  ),
                  label: const Text(
                    'გაუქმება',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showConfirmationDialog(String methodLabel) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 40),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: Color(0xFF3B82F6),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'დადასტურება',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ნამდვილად გსურთ მაგიდის დახურვა ($methodLabel)-ით?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'გაუქმება',
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'დიახ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Widget _buildModernMethodCard(
    BuildContext context, {
    required String label,
    required String englishLabel,
    required IconData icon,
    required Color color,
    required TablePaymentMethod method,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(method),
          borderRadius: BorderRadius.circular(20),
          highlightColor: color.withOpacity(0.15),
          splashColor: color.withOpacity(0.2),
          child: Container(
            height: 170, // Reduced from 190
            padding: const EdgeInsets.all(20), // Reduced from 24
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: color,
                  ), // Reduced icon size
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 16, // Reduced font size
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  englishLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showBankDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 540,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 40,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'აირჩიეთ ტერმინალი',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select Bank Terminal',
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    _buildModernBankCard(
                      dialogContext,
                      label: 'TBC Bank',
                      iconAsset: Icons.account_balance_rounded,
                      color: const Color(0xFF0E69C3),
                      value: 'tbc',
                    ),
                    const SizedBox(width: 20),
                    _buildModernBankCard(
                      dialogContext,
                      label: 'Bank of Georgia',
                      iconAsset: Icons.account_balance_rounded,
                      color: const Color(0xFFFF8A00),
                      value: 'bog',
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.black54,
                  ),
                  label: const Text(
                    'უკან დაბრუნება',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernBankCard(
    BuildContext context, {
    required String label,
    required IconData iconAsset,
    required Color color,
    required String value,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          borderRadius: BorderRadius.circular(20),
          highlightColor: color.withOpacity(0.15),
          splashColor: color.withOpacity(0.2),
          child: Container(
            height: 160,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconAsset, size: 36, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<TablePaymentSelection?> _showSplitDialog() {
    return showDialog<TablePaymentSelection>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String selectedBank = 'tbc';
        String inputValue = _formatAmount(total / 2);
        double bankPortion = _round(total / 2);
        double cashPortion = _round(total - bankPortion);

        void updateFromInput(String newValue) {
          final parsed = _parseAmount(newValue);
          // Clamp only for logic, but don't force string back to inputValue here
          // to allow users to keep typing (e.g. "1." before "1.5")
          final clamped = parsed.clamp(0.0, total);
          bankPortion = _round(clamped.toDouble());
          cashPortion = _round(total - bankPortion);
        }

        return StatefulBuilder(
          builder: (stateContext, setState) {
            void handleDigit(String digit) {
              setState(() {
                inputValue = _appendDigit(inputValue, digit);
                updateFromInput(inputValue);
              });
            }

            void handleClear() {
              setState(() {
                inputValue = '0';
                updateFromInput(inputValue);
              });
            }

            void handleDelete() {
              setState(() {
                inputValue = _deleteDigit(inputValue);
                updateFromInput(inputValue);
              });
            }

            final sumMatches =
                (bankPortion + cashPortion - total).abs() <= _amountTolerance;
            final hasAnyPayment = bankPortion > 0 || cashPortion > 0;
            final isValid = sumMatches && hasAnyPayment;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 720, // Reduced from 780
                height: 520, // Reduced from 580
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 40,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Left Pane (Details)
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'გაყოფილი გადახდა',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Split Payment',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'სულ ჯამი :',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '₾${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildAmountRow(
                              label: 'ბანკი / Bank',
                              amountText: inputValue,
                              highlight: true,
                            ),
                            const SizedBox(height: 8),
                            _buildAmountRow(
                              label: 'ნაღდი / Cash',
                              amount: cashPortion,
                              highlight: false,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('TBC POS'),
                                    selected: selectedBank == 'tbc',
                                    onSelected: (_) =>
                                        setState(() => selectedBank = 'tbc'),
                                    selectedColor: const Color(0xFF0E69C3),
                                    labelStyle: TextStyle(
                                      color: selectedBank == 'tbc'
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('BOG POS'),
                                    selected: selectedBank == 'bog',
                                    onSelected: (_) =>
                                        setState(() => selectedBank = 'bog'),
                                    selectedColor: const Color(0xFFFF8A00),
                                    labelStyle: TextStyle(
                                      color: selectedBank == 'bog'
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 18,
                                    color: Colors.black54,
                                  ),
                                  label: const Text(
                                    'უკან დაბრუნება',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: isValid
                                        ? () {
                                            Navigator.of(dialogContext).pop(
                                              TablePaymentSelection(
                                                method:
                                                    TablePaymentMethod.split,
                                                cashAmount: _round(cashPortion),
                                                bankAmount: _round(bankPortion),
                                                bankProvider: selectedBank,
                                              ),
                                            );
                                          }
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: const Color(
                                        0xFF10B981,
                                      ).withOpacity(0.3),
                                      disabledForegroundColor: Colors.white
                                          .withOpacity(0.8),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      'დადასტურება',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
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
                    // Right Pane (PinPad)
                    Container(width: 1, color: Colors.black12),
                    Expanded(
                      flex: 4,
                      child: Container(
                        color: const Color(0xFFF9FAFB),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 16.0,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: PinPad(
                                      onDigitPressed: handleDigit,
                                      onClearPressed: handleClear,
                                      onDeletePressed: handleDelete,
                                      showDecimalButton: true,
                                    ),
                                  ),
                                  if (!isValid) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFEF4444,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5),
                                        ),
                                      ),
                                      child: Text(
                                        'თანხა უნდა უდრიდეს ₾${total.toStringAsFixed(2)}-ს',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
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
            );
          },
        );
      },
    );
  }

  Widget _buildAmountRow({
    required String label,
    double? amount,
    String? amountText,
    required bool highlight,
  }) {
    final displayValue =
        amountText ?? (amount != null ? amount.toStringAsFixed(2) : '0.00');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF3B82F6).withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? const Color(0xFF3B82F6).withOpacity(0.6)
              : Colors.black12,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            '₾$displayValue',
            style: TextStyle(
              color: highlight ? const Color(0xFF3B82F6) : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  static double _parseAmount(String value) {
    if (value.trim().isEmpty) {
      return 0;
    }
    return double.tryParse(value) ?? 0;
  }

  static String _formatAmount(double value) => value.toStringAsFixed(2);

  static String _appendDigit(String currentValue, String digit) {
    var value = currentValue.isEmpty ? '0' : currentValue;

    if (value == '0' && digit != '.') {
      value = digit;
    } else if (digit == '.') {
      if (value.contains('.')) return value;
      value = '$value.';
    } else {
      final parts = value.split('.');
      if (parts.length == 2 && parts[1].length >= 2) {
        return value;
      }
      value = '$value$digit';
    }

    if (value.startsWith('.')) {
      value = '0$value';
    }
    return value;
  }

  static String _deleteDigit(String currentValue) {
    if (currentValue.isEmpty) {
      return '0';
    }
    final updated = currentValue.substring(0, currentValue.length - 1);
    if (updated.isEmpty || updated == '-') {
      return '0';
    }
    if (updated == '0' || updated == '-0') {
      return '0';
    }
    return updated;
  }
}

class TableClosureHelper {
  static Map<String, double>? buildSaleBreakdown(
    TablePaymentSelection? selection,
  ) {
    if (selection == null) {
      return null;
    }
    final breakdown = <String, double>{};
    if (selection.cashAmount > 0) {
      breakdown[PaymentUtils.methodCash] = _round(selection.cashAmount);
    }
    if (selection.bankAmount > 0) {
      final provider = _normalizeProvider(selection.bankProvider);
      final key = provider == 'bog'
          ? PaymentUtils.methodCardBog
          : PaymentUtils.methodCardTbc;
      breakdown[key] = _round(selection.bankAmount);
    }
    return breakdown.isEmpty ? null : breakdown;
  }

  static String resolvePaymentMethod(TablePaymentSelection selection) {
    if (selection.method == TablePaymentMethod.cash) {
      return PaymentUtils.methodCash;
    }
    if (selection.method == TablePaymentMethod.bank) {
      final provider = _normalizeProvider(selection.bankProvider);
      return provider == 'bog'
          ? PaymentUtils.methodCardBog
          : PaymentUtils.methodCardTbc;
    }
    return 'split';
  }

  static Map<String, dynamic> buildFinalTransactionRecord({
    required Order order,
    TablePaymentSelection? selection,
    Map<String, double>? paymentBreakdown,
    required double subtotal,
    required double serviceFee,
    required DateTime closedAt,
    required bool isFiscal,
  }) {
    final items = order.items
        .map(
          (item) => {
            'name': item.itemName,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'total': item.total,
          },
        )
        .toList();

    return {
      'tableId': _resolvePrimaryTable(order.tableNumbers),
      'tableNumbers': order.tableNumbers,
      'orderId': order.orderId,
      'items': items,
      'subtotal': _round(subtotal),
      'total': _round(order.totalAmount),
      'serviceFee': _round(serviceFee),
      'discount': _round(order.discountAmount),
      'manualAdjustment': _round(order.manualAdjustmentAmount),
      'paymentBreakdown':
          paymentBreakdown ??
          (selection != null
              ? {
                  'cash': _round(selection.cashAmount),
                  'bank': _round(selection.bankAmount),
                }
              : null),
      'bankProvider': selection != null
          ? _normalizeProvider(selection.bankProvider)?.toUpperCase()
          : null,
      'closedAt': closedAt.toIso8601String(),
      'createdBy': order.createdBy,
      'isFiscal': isFiscal,
    };
  }

  static String buildSuccessMessage(TablePaymentSelection selection) {
    final bankLabel = _normalizeProvider(selection.bankProvider)?.toUpperCase();
    if (selection.method == TablePaymentMethod.cash) {
      return 'ნაღდი ₾${selection.cashAmount.toStringAsFixed(2)} / Cash';
    }
    if (selection.method == TablePaymentMethod.bank) {
      return 'ბანკი (${bankLabel ?? 'POS'}) ₾${selection.bankAmount.toStringAsFixed(2)}';
    }
    final bankPart =
        'ბანკი (${bankLabel ?? 'POS'}) ₾${selection.bankAmount.toStringAsFixed(2)}';
    final cashPart = 'ნაღდი ₾${selection.cashAmount.toStringAsFixed(2)}';
    return '$bankPart + $cashPart';
  }

  static String buildNonFiscalSuccessMessage() {
    return 'მაგიდა დაიხურა არაფისკალურად / Table closed (non-fiscal)';
  }

  static String bankDisplayLabel(TablePaymentSelection selection) {
    final normalized = _normalizeProvider(selection.bankProvider);
    if (normalized == 'bog') {
      return 'BOG';
    }
    if (normalized == 'tbc') {
      return 'TBC';
    }
    return selection.bankProvider?.toUpperCase() ?? 'POS';
  }

  static String _resolvePrimaryTable(List<String> tables) {
    if (tables.isEmpty) {
      return 'NA';
    }
    return tables.first;
  }

  static String? _normalizeProvider(String? raw) {
    final lower = raw?.toLowerCase().trim();
    if (lower == 'bog') {
      return 'bog';
    }
    if (lower == 'tbc') {
      return 'tbc';
    }
    return raw == null || raw.isEmpty ? null : lower;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));
}
