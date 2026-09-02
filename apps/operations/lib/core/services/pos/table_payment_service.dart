import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'package:vynic/core/widgets/pin_button.dart';
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
  TablePaymentService({
    required this.context,
    required this.total,
    this.grossTotal,
    this.advanceApplied = 0.0,
  });

  final BuildContext context;

  /// What is left to collect at the table.
  final double total;

  /// The full value of the order, advance included. Null when there is no
  /// advance, in which case it equals [total].
  final double? grossTotal;

  /// Money the guest already handed over before this closure.
  final double advanceApplied;

  static const double _amountTolerance = 0.01;

  // Shared design tokens — aligned with the redesigned POS surfaces
  // (take-away section / order detail) for a consistent look.
  static const Color _panel = Colors.white;
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _accent = Color(0xFF0F766E);
  static const Color _cash = Color(0xFF047857);
  static const Color _bank = Color(0xFF2563EB);
  static const Color _split = Color(0xFF7C3AED);
  static const Color _danger = Color(0xFFB91C1C);

  static const List<BoxShadow> _dialogShadow = [
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 32, offset: Offset(0, 16)),
  ];

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

  /// What the guest owes, and why it is not the order total.
  ///
  /// With a deposit already taken, the number to collect at the table is the
  /// balance — but showing only the balance leaves the cashier no way to see
  /// that the order was for more, or to notice a wrong deposit before the
  /// money is booked. So all three are on screen: the order, what came off
  /// it, and what is left.
  Widget _buildAmountSummary() {
    final gross = grossTotal ?? total;
    final hasAdvance = advanceApplied > 0.005;

    Widget line(
      String label,
      double amount, {
      bool strong = false,
      Color? color,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: strong ? _text : _muted,
                  fontSize: strong ? 15 : 13,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '₾${amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: color ?? (strong ? _text : _muted),
                fontSize: strong ? 18 : 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasAdvance) ...[
            line('შეკვეთის ჯამი', gross),
            line('ავანსი', -advanceApplied, color: _accent),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: _border),
            ),
          ],
          line(
            hasAdvance ? 'დარჩენილი გადასახდელი' : 'გადასახდელი',
            total,
            strong: true,
          ),
        ],
      ),
    );
  }

  Future<TablePaymentMethod?> _showMethodDialog() {
    return showDialog<TablePaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 600,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
              boxShadow: _dialogShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: _accent,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'აირჩიეთ გადახდის მეთოდი',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select payment method',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildAmountSummary(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'ნაღდი ფული',
                      englishLabel: 'Cash',
                      icon: Icons.payments_rounded,
                      color: _cash,
                      method: TablePaymentMethod.cash,
                    ),
                    const SizedBox(width: 14),
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'ბარათით',
                      englishLabel: 'Bank POS',
                      icon: Icons.credit_card_rounded,
                      color: _bank,
                      method: TablePaymentMethod.bank,
                    ),
                    const SizedBox(width: 14),
                    _buildModernMethodCard(
                      dialogContext,
                      label: 'გაყოფილი',
                      englishLabel: 'Split',
                      icon: Icons.call_split_rounded,
                      color: _split,
                      method: TablePaymentMethod.split,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _muted,
                    size: 18,
                  ),
                  label: const Text(
                    'გაუქმება',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
              boxShadow: _dialogShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: _accent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'მაგიდის დახურვა',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ნამდვილად გსურთ დახურვა — $methodLabel?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _muted,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'გაუქმება',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'დახურვა',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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
          borderRadius: BorderRadius.circular(18),
          hoverColor: color.withValues(alpha: 0.04),
          highlightColor: color.withValues(alpha: 0.10),
          splashColor: color.withValues(alpha: 0.12),
          child: Container(
            height: 158,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  englishLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 12),
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
            width: 520,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
              boxShadow: _dialogShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'აირჩიეთ ტერმინალი',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select bank terminal',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildModernBankCard(
                      dialogContext,
                      label: 'TBC Bank',
                      iconAsset: Icons.account_balance_rounded,
                      color: const Color(0xFF0E69C3),
                      value: 'tbc',
                    ),
                    const SizedBox(width: 14),
                    _buildModernBankCard(
                      dialogContext,
                      label: 'Bank of Georgia',
                      iconAsset: Icons.account_balance_rounded,
                      color: const Color(0xFFFF8A00),
                      value: 'bog',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: _muted,
                    size: 18,
                  ),
                  label: const Text(
                    'უკან',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
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
          borderRadius: BorderRadius.circular(18),
          hoverColor: color.withValues(alpha: 0.04),
          highlightColor: color.withValues(alpha: 0.10),
          splashColor: color.withValues(alpha: 0.12),
          child: Container(
            height: 150,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(iconAsset, size: 30, color: color),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
                width: 720,
                height: 520,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                  boxShadow: _dialogShadow,
                ),
                child: Row(
                  children: [
                    // Left Pane (Details)
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 22,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'გაყოფილი გადახდა',
                              style: TextStyle(
                                color: _text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Split payment',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _accent.withValues(alpha: 0.20),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'სულ ჯამი',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '₾${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: _accent,
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
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildBankChip(
                                    label: 'TBC POS',
                                    selected: selectedBank == 'tbc',
                                    color: const Color(0xFF0E69C3),
                                    onTap: () =>
                                        setState(() => selectedBank = 'tbc'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildBankChip(
                                    label: 'BOG POS',
                                    selected: selectedBank == 'bog',
                                    color: const Color(0xFFFF8A00),
                                    onTap: () =>
                                        setState(() => selectedBank = 'bog'),
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
                                    color: _muted,
                                  ),
                                  label: const Text(
                                    'უკან',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                                      backgroundColor: _accent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: _accent
                                          .withValues(alpha: 0.30),
                                      disabledForegroundColor: Colors.white
                                          .withValues(alpha: 0.85),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'დადასტურება',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
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
                    Container(width: 1, color: _border),
                    Expanded(
                      flex: 4,
                      child: Container(
                        color: _surface,
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
                                        color: _danger.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _danger.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        'თანხა უნდა უდრიდეს ₾${total.toStringAsFixed(2)}-ს',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: _danger,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: highlight ? _bank.withValues(alpha: 0.06) : _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? _bank.withValues(alpha: 0.55) : _border,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '₾$displayValue',
            style: TextStyle(
              color: highlight ? _bank : _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : _border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : _muted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
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
  /// Tolerance for reconciling tendered amounts against a sale total. Matches
  /// [TablePaymentService._amountTolerance] so a split that the payment dialog
  /// accepted can never be rejected here.
  static const double breakdownTolerance = 0.01;

  /// Returns `null` when [breakdown] reconciles with [total]; otherwise a
  /// description of the mismatch.
  ///
  /// A sale whose tender lines don't add up to its recorded total is a
  /// money-integrity failure: the guest was charged one amount and a different
  /// one would be booked. Callers must block the close and surface the reason
  /// rather than persisting the two numbers.
  static String? describeBreakdownMismatch({
    required Map<String, double>? breakdown,
    required double total,
  }) {
    if (breakdown == null || breakdown.isEmpty) {
      return 'payment breakdown is empty for a total of '
          '${total.toStringAsFixed(2)}';
    }
    // Round before comparing: binary floating point makes an exact
    // one-tetri difference (105.01 - 105.00) come out fractionally above
    // 0.01, which would reject a legitimate tender.
    final sum = _round(breakdown.values.fold<double>(0, (a, b) => a + b));
    final delta = _round(sum - total);
    if (delta.abs() <= breakdownTolerance) {
      return null;
    }
    final parts = breakdown.entries
        .map((entry) => '${entry.key}=${entry.value.toStringAsFixed(2)}')
        .join(', ');
    return 'payment breakdown ($parts) sums to ${sum.toStringAsFixed(2)} '
        'but the sale total is ${total.toStringAsFixed(2)} '
        '(difference ${delta.toStringAsFixed(2)})';
  }

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
