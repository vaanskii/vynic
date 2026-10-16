import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
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
  static const Color _surface = VynicFloorTokens.canvas;
  static const Color _border = VynicFloorTokens.panelBorder;
  static const Color _text = VynicFloorTokens.text;
  static const Color _muted = VynicFloorTokens.textMuted;
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _cash = VynicFloorTokens.successText;
  static const Color _bank = VynicFloorTokens.accentText;
  static const Color _split = VynicFloorTokens.accentStrong;

  Future<TablePaymentSelection?> collect() =>
      UpdateReadiness.track('collect', () => _updateTrackedCollect());

  Future<TablePaymentSelection?> _updateTrackedCollect() async {
    if (grossTotal != null && advanceApplied > grossTotal! + 0.005) {
      await showErrorToast(
        context,
        'ავანსი ანგარიშს აღემატება — თანხის დაბრუნება ან გადატანა მენეჯერთან გადაწყვიტეთ',
      );
      return null;
    }
    if (total.abs() < 0.005 && advanceApplied > 0) {
      final confirmed = await showPosModal<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ანგარიში სრულად დაფარულია'),
          content: Text(
            'ავანსი ${advanceApplied.toStringAsFixed(2)} ₾. დამატებით გადასახდელი: 0.00 ₾.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('უკან'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ანგარიშის დახურვა'),
            ),
          ],
        ),
      );
      return confirmed == true
          ? const TablePaymentSelection(
              method: TablePaymentMethod.cash,
              cashAmount: 0,
              bankAmount: 0,
            )
          : null;
    }
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
    return showPosModal<TablePaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PosFormDialog(
        title: 'აირჩიეთ გადახდის მეთოდი',
        subtitle: 'Select payment method',
        width: 600,
        onClose: () => Navigator.of(dialogContext).pop(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('უკან დაბრუნება'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAmountSummary(),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showConfirmationDialog(String methodLabel) async {
    final result = await showPosModal<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('მაგიდის დახურვა'),
        content: Text('ნამდვილად გსურთ დახურვა — $methodLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('დახურვა'),
          ),
        ],
      ),
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
            constraints: const BoxConstraints(minHeight: 158),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
    return showPosModal<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PosFormDialog(
        title: 'აირჩიეთ ტერმინალი',
        subtitle: 'Select bank terminal',
        width: 520,
        onClose: () => Navigator.of(dialogContext).pop(),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('უკან'),
          ),
        ],
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ),
      ),
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
            constraints: const BoxConstraints(minHeight: 150),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
    return showPosModal<TablePaymentSelection>(
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

            return PosFormDialog(
              title: 'გაყოფილი გადახდა',
              subtitle: 'Split payment',
              width: 760,
              onClose: () => Navigator.of(dialogContext).pop(),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('უკან'),
                ),
                ElevatedButton(
                  onPressed: isValid
                      ? () => Navigator.of(dialogContext).pop(
                          TablePaymentSelection(
                            method: TablePaymentMethod.split,
                            cashAmount: _round(cashPortion),
                            bankAmount: _round(bankPortion),
                            bankProvider: selectedBank,
                          ),
                        )
                      : null,
                  child: const Text('დადასტურება'),
                ),
              ],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAmountRow(
                          label: 'სულ ჯამი',
                          amount: total,
                          highlight: false,
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PinPad(
                          onDigitPressed: handleDigit,
                          onClearPressed: handleClear,
                          onDeletePressed: handleDelete,
                          showDecimalButton: true,
                        ),
                        if (!isValid) ...[
                          const SizedBox(height: 8),
                          PosFormError(
                            'თანხა უნდა უდრიდეს ₾${total.toStringAsFixed(2)}-ს',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
          constraints: const BoxConstraints(minHeight: 56),
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
