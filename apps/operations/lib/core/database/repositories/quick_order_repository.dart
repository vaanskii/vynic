import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';

import 'business_day_repository.dart';
import '../database_core.dart';
import 'settings_repository.dart';

/// Saved quick-order drafts (the calculator's parked orders).
class QuickOrderRepository {
  QuickOrderRepository._();

  static const Uuid _uuid = Uuid();

  static List<OrderItem> cloneOrderItems(List<OrderItem> items) {
    return items
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: item.total,
            comment: item.comment,
          ),
        )
        .toList();
  }

  static QuickOrderDraft _cloneQuickOrderDraft(QuickOrderDraft draft) {
    return QuickOrderDraft(
      id: draft.id,
      items: cloneOrderItems(draft.items),
      subtotal: draft.subtotal,
      serviceFeeAmount: draft.serviceFeeAmount,
      total: draft.total,
      includeServiceFee: draft.includeServiceFee,
      serviceFeeRate: draft.serviceFeeRate,
      createdAt: draft.createdAt,
      createdBy: draft.createdBy,
      displayName: draft.displayName,
    );
  }

  static List<QuickOrderDraft> getQuickOrderDrafts() {
    if (DatabaseCore.quickOrderBox == null) {
      return [];
    }

    final drafts = DatabaseCore.quickOrderBox!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return drafts.map(_cloneQuickOrderDraft).toList();
  }

  static QuickOrderDraft? getQuickOrderDraft(String id) {
    if (DatabaseCore.quickOrderBox == null) {
      return null;
    }

    final draft = DatabaseCore.quickOrderBox!.get(id);
    if (draft == null) {
      return null;
    }

    return _cloneQuickOrderDraft(draft);
  }

  static Future<QuickOrderDraft> saveQuickOrderDraft({
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) async {
    if (DatabaseCore.quickOrderBox == null) {
      throw StateError('Quick order storage is not initialized');
    }

    final normalizedSubtotal = double.parse(subtotal.toStringAsFixed(2));
    final includeFee = SettingsRepository.resolveIncludeServiceFee(
      includeServiceFee,
    );
    final rate = includeFee ? serviceFeeRate : 0.0;
    final serviceFeeAmount = includeFee
        ? double.parse((normalizedSubtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = double.parse(
      (normalizedSubtotal + serviceFeeAmount).toStringAsFixed(2),
    );

    final draft = QuickOrderDraft(
      id: _uuid.v4(),
      items: cloneOrderItems(items),
      subtotal: normalizedSubtotal,
      serviceFeeAmount: serviceFeeAmount,
      total: total,
      includeServiceFee: includeFee,
      serviceFeeRate: rate,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: createdBy,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : null,
    );

    await DatabaseCore.quickOrderBox!.put(draft.id, draft);
    return _cloneQuickOrderDraft(draft);
  }

  static Future<QuickOrderDraft> updateQuickOrderDraft({
    required String id,
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) async {
    if (DatabaseCore.quickOrderBox == null) {
      throw StateError('Quick order storage is not initialized');
    }

    final normalizedSubtotal = double.parse(subtotal.toStringAsFixed(2));
    final includeFee = SettingsRepository.resolveIncludeServiceFee(
      includeServiceFee,
    );
    final rate = includeFee ? serviceFeeRate : 0.0;
    final serviceFeeAmount = includeFee
        ? double.parse((normalizedSubtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = double.parse(
      (normalizedSubtotal + serviceFeeAmount).toStringAsFixed(2),
    );

    final existing = DatabaseCore.quickOrderBox!.get(id);

    final draft = QuickOrderDraft(
      id: id,
      items: cloneOrderItems(items),
      subtotal: normalizedSubtotal,
      serviceFeeAmount: serviceFeeAmount,
      total: total,
      includeServiceFee: includeFee,
      serviceFeeRate: rate,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: createdBy,
      displayName: displayName ?? existing?.displayName,
    );

    await DatabaseCore.quickOrderBox!.put(draft.id, draft);
    return _cloneQuickOrderDraft(draft);
  }

  static Future<void> deleteQuickOrderDraft(String id) async {
    if (DatabaseCore.quickOrderBox == null) {
      return;
    }

    await DatabaseCore.quickOrderBox!.delete(id);
  }

  static Future<void> setQuickOrderDraftDisplayName({
    required String id,
    String? displayName,
  }) async {
    if (DatabaseCore.quickOrderBox == null) {
      return;
    }

    final draft = DatabaseCore.quickOrderBox!.get(id);
    if (draft == null) {
      return;
    }

    final normalized = displayName?.trim();
    draft.displayName = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    await draft.save();
  }

  static Future<void> clearQuickOrderDrafts() async {
    if (DatabaseCore.quickOrderBox == null) {
      return;
    }

    await DatabaseCore.quickOrderBox!.clear();
  }
}
