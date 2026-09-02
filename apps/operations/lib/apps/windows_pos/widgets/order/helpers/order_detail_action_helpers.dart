import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/pos_permission.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_actions_panel.dart';

class OrderDetailActionHelpers {
  static OrderActionsBundle buildActions({
    required String status,
    required Order order,
    required User user,
    required bool canPrintKitchenCheck,
    required bool canPrintReceipt,
    required bool canModify,
    required bool isTakeAwayOrder,
    required bool canCloseTable,
    required bool canNonFiscalClose,
    required bool serviceFeeAvailable,
    required String serviceFeePercentageLabel,
    required VoidCallback onConfirmOrder,
    required VoidCallback onPrintKitchenCheck,
    required VoidCallback onPrintReceipt,
    required VoidCallback onToggleServiceFee,
    required VoidCallback onOpenServiceFeeConfig,
    required VoidCallback onStartNonFiscalClosureFlow,
    required VoidCallback onShowDiscountDialog,
    required VoidCallback onShowManualAdjustmentDialog,
    required VoidCallback onShowChangeTableDialog,
    required VoidCallback onShowMoveItemsDialog,
    required VoidCallback onConfirmCancelOrder,
    required VoidCallback onStartTableClosureFlow,
  }) {
    final primaryActions = <OrderActionConfig>[];
    if (status == 'pending') {
      primaryActions.add(
        OrderActionConfig(
          id: OrderActionId.confirmOrder,
          label: 'შეკვეთის დადასტურება',
          icon: Icons.verified,
          onTap: onConfirmOrder,
          accent: const Color(0xFF2563EB),
          subtitle: 'გადააქვს შეკვეთა მომზადებაში.',
          emphasize: true,
        ),
      );
    }

    if (canPrintKitchenCheck) {
      primaryActions.add(
        OrderActionConfig(
          id: OrderActionId.printKitchenCheck,
          label: 'სამზარეულოს ჩეკი',
          icon: Icons.restaurant,
          onTap: onPrintKitchenCheck,
          accent: const Color(0xFFF97316),
          subtitle: 'ბეჭდავს ბოლო ვერსიას სამზარეულოსთვის.',
        ),
      );
    }

    if (canPrintReceipt) {
      primaryActions.add(
        OrderActionConfig(
          id: OrderActionId.printReceipt,
          label: 'ჩეკის დაბეჭდვა',
          icon: Icons.receipt_long,
          onTap: onPrintReceipt,
          accent: const Color(0xFF16A34A),
          subtitle: 'კლიენტისთვის დასაბეჭდი ქვითარი.',
        ),
      );
    }

    final secondaryActions = <OrderActionConfig>[];

    if (serviceFeeAvailable && !isTakeAwayOrder && canModify) {
      secondaryActions.add(
        OrderActionConfig(
          id: OrderActionId.toggleServiceFee,
          label: 'სერვისი ($serviceFeePercentageLabel%)',
          icon: Icons.room_service,
          onTap: onToggleServiceFee,
          onLongPress: onOpenServiceFeeConfig,
          accent: order.includeServiceFee
              ? const Color(0xFF2563EB)
              : const Color(0xFF64748B),
          subtitle: order.includeServiceFee
              ? 'ერთი დაჭერა: გამორთვა • დაჭერა და დაჭერა: კონფიგურაცია'
              : 'ერთი დაჭერა: ჩართვა • დაჭერა და დაჭერა: კონფიგურაცია',
          emphasize: order.includeServiceFee,
        ),
      );
    }

    if (canNonFiscalClose) {
      secondaryActions.add(
        OrderActionConfig(
          id: OrderActionId.nonFiscalClose,
          label: 'არაფისკალური დახურვა',
          icon: Icons.lock_person,
          onTap: onStartNonFiscalClosureFlow,
          accent: const Color(0xFFF97316),
          subtitle: 'დახურავს მაგიდას გაყიდვების გარეშე.',
          emphasize: false,
        ),
      );
    }

    if (canModify) {
      // Discount and manual price adjustment both reduce (or otherwise
      // alter) what the customer owes — same risk class, same permission.
      // Hidden for waiters per docs/UI_PLAN.md §4.4.
      if (PosPermissions.has(user, PosPermission.applyDiscount)) {
        secondaryActions.add(
          OrderActionConfig(
            id: OrderActionId.advance,
            label: 'ავანსი',
            icon: Icons.percent,
            onTap: onShowDiscountDialog,
            accent: order.effectiveAdvanceAmount > 0
                ? const Color(0xFF16A34A)
                : const Color(0xFFC0AD7B),
            subtitle: order.effectiveAdvanceAmount > 0
                ? 'აქტიური ავანსი -${order.effectiveAdvanceAmount.toStringAsFixed(2)} GEL.'
                : 'დაამატე ან შეცვალე ავანსი.',
            emphasize: order.effectiveAdvanceAmount > 0,
          ),
        );

        secondaryActions.add(
          OrderActionConfig(
            id: OrderActionId.priceAdjustment,
            label: 'ფასის კორექცია',
            icon: Icons.price_change,
            onTap: onShowManualAdjustmentDialog,
            accent: order.manualAdjustmentAmount != 0
                ? const Color(0xFFC0AD7B)
                : const Color(0xFF64748B),
            subtitle: order.manualAdjustmentAmount != 0
                ? 'აქტიური კორექცია ${order.manualAdjustmentAmount > 0 ? '+' : ''}${order.manualAdjustmentAmount.toStringAsFixed(2)} GEL.'
                : 'დაამატე ან შეამცირე თანხა შეკვეთაზე.',
            emphasize: order.manualAdjustmentAmount != 0,
          ),
        );
      }

      if (!isTakeAwayOrder) {
        secondaryActions.add(
          OrderActionConfig(
            id: OrderActionId.changeTable,
            label: 'მაგიდის შეცვლა',
            icon: Icons.table_restaurant,
            onTap: onShowChangeTableDialog,
            accent: const Color(0xFF2563EB),
            subtitle: 'გადაანაწილე შეკვეთა სხვა სუფრებზე.',
          ),
        );
      }

      // Offered on take-away too: „we ordered to go but we will sit down" is
      // the case this exists for, and it only works if it runs both ways.
      if (order.items.isNotEmpty) {
        secondaryActions.add(
          OrderActionConfig(
            id: OrderActionId.moveItems,
            label: 'პროდუქტების გადატანა',
            icon: Icons.swap_horiz,
            onTap: onShowMoveItemsDialog,
            accent: const Color(0xFF2563EB),
            subtitle: 'გადაიტანე პროდუქტები სხვა ღია შეკვეთაზე.',
          ),
        );
      }

      // Cancellation is manager-only (handled from mobile app for waiters)
      if (PosPermissions.has(user, PosPermission.voidOrder)) {
        secondaryActions.add(
          OrderActionConfig(
            id: OrderActionId.cancelOrder,
            label: 'შეკვეთის გაუქმება',
            icon: Icons.cancel,
            onTap: onConfirmCancelOrder,
            accent: const Color(0xFFDC2626),
            subtitle: 'დახურავს შეკვეთას გაუქმებით.',
            emphasize: true,
          ),
        );
      }
    }

    if (canCloseTable) {
      secondaryActions.add(
        OrderActionConfig(
          id: OrderActionId.closeTable,
          label: 'მაგიდის დახურვა',
          icon: Icons.check_circle,
          onTap: onStartTableClosureFlow,
          accent: const Color(0xFFC0AD7B),
          subtitle: 'გადახდის დასრულება და მაგიდის დახურვა.',
          emphasize: true,
        ),
      );
    }

    return OrderActionsBundle(
      primary: primaryActions,
      secondary: secondaryActions,
    );
  }
}
