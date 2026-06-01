# Printer Service Integration Guide

This guide shows you how to integrate the `PrinterService` into your existing `OrderDetailScreen`.

## Step 1: Add Import

At the top of `lib/screens/order_detail_screen.dart`, add:

```dart
import '../services/printer_service.dart';
```

## Step 2: Add Helper Methods

Add these helper methods to your `_OrderDetailScreenState` class:

### Format Items for Kitchen Check

```dart
List<String> _formatItemsForKitchen() {
  return widget.order.items.map((item) {
    return '${item.quantity}x ${item.itemName}';
  }).toList();
}
```

### Format Items for Receipt

```dart
List<String> _formatItemsForReceipt() {
  return widget.order.items.map((item) {
    final quantity = item.quantity;
    final name = item.itemName;
    final itemTotal = item.total;
    
    // Format: "2 x Burger                    30.00"
    final itemLine = '$quantity x $name';
    return itemLine.padRight(30) + itemTotal.toStringAsFixed(2).padLeft(10);
  }).toList();
}
```

## Step 3: Update Status Method (Recommended Approach)

Replace or update your `_updateStatus` method to include printing:

```dart
Future<void> _updateStatus(String newStatus) async {
  try {
    // Update order status in database
    await DatabaseService.updateOrderStatus(
      orderId: widget.order.orderId,
      status: newStatus,
    );

    // If confirming order, print kitchen check
    if (newStatus == 'confirmed') {
      // Format items for kitchen
      final kitchenItems = _formatItemsForKitchen();
      
      // Print kitchen check (don't block on failure)
      final printSuccess = await PrinterService.printKitchenCheck(
        items: kitchenItems,
        tableNumber: widget.order.tableNumbers.join(', '),
        orderNumber: widget.order.orderId.toString(),
      );
      
      // Show warning if print failed
      if (!printSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Kitchen printer unavailable'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (printSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Kitchen check printed'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }

    // If closing table (paid status), print receipt
    if (newStatus == 'paid') {
      // Format items for receipt
      final receiptItems = _formatItemsForReceipt();
      
      // Print receipt (don't block on failure)
      final printSuccess = await PrinterService.printReceipt(
        items: receiptItems,
        total: widget.order.totalAmount,
        tableNumber: widget.order.tableNumbers.join(', '),
        orderNumber: widget.order.orderId.toString(),
        paymentMethod: 'Cash', // TODO: Add payment method selection
      );
      
      // Show warning if print failed
      if (!printSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Receipt printer unavailable'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (printSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Receipt printed'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }

    // Navigate back
    if (mounted) {
      Navigator.pop(context);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

## Alternative: Show Loading While Printing

If you prefer to show a loading dialog while printing:

```dart
Future<void> _updateStatusWithPrintLoading(String newStatus) async {
  try {
    // Update status in database
    await DatabaseService.updateOrderStatus(
      orderId: widget.order.orderId,
      status: newStatus,
    );

    if (newStatus == 'confirmed') {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Printing kitchen check...'),
              ],
            ),
          ),
        );
      }
      
      // Print kitchen check
      final kitchenItems = _formatItemsForKitchen();
      final printSuccess = await PrinterService.printKitchenCheck(
        items: kitchenItems,
        tableNumber: widget.order.tableNumbers.join(', '),
        orderNumber: widget.order.orderId.toString(),
      );
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Show result
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              printSuccess 
                ? '✓ Kitchen check printed' 
                : '⚠️ Kitchen printer unavailable',
            ),
            backgroundColor: printSuccess ? Colors.green : Colors.orange,
          ),
        );
      }
    }

    if (newStatus == 'paid') {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Printing receipt...'),
              ],
            ),
          ),
        );
      }
      
      // Print receipt
      final receiptItems = _formatItemsForReceipt();
      final printSuccess = await PrinterService.printReceipt(
        items: receiptItems,
        total: widget.order.totalAmount,
        tableNumber: widget.order.tableNumbers.join(', '),
        orderNumber: widget.order.orderId.toString(),
        paymentMethod: 'Cash',
      );
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Show result
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              printSuccess 
                ? '✓ Receipt printed' 
                : '⚠️ Receipt printer unavailable',
            ),
            backgroundColor: printSuccess ? Colors.green : Colors.orange,
          ),
        );
      }
    }

    // Navigate back
    if (mounted) {
      Navigator.pop(context);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

## Optional: Add Test Printer Button

You can add a button to test printer connections (useful in settings or admin screens):

```dart
Widget _buildTestPrinterButton() {
  return ElevatedButton.icon(
    onPressed: () async {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Test printers
      final results = await PrinterService.testConnections();
      
      // Close loading
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Show results
      if (mounted) {
        final kitchenOk = results['kitchen'] == true;
        final receiptOk = results['receipt'] == true;
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Printer Status'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      kitchenOk ? Icons.check_circle : Icons.error,
                      color: kitchenOk ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    const Text('Kitchen Printer'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      receiptOk ? Icons.check_circle : Icons.error,
                      color: receiptOk ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    const Text('Receipt Printer'),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    },
    icon: const Icon(Icons.print),
    label: const Text('Test Printers'),
  );
}
```

## Integration Checklist

- [ ] Import `PrinterService` at top of file
- [ ] Add `_formatItemsForKitchen()` helper method
- [ ] Add `_formatItemsForReceipt()` helper method
- [ ] Update `_updateStatus()` to print on `'confirmed'` status
- [ ] Update `_updateStatus()` to print on `'paid'` status
- [ ] (Optional) Add test printer button
- [ ] Verify `.env` file has correct printer IPs
- [ ] Test with actual printers on network

## Testing

Before deploying, test the following scenarios:

1. **Confirm Order** → Should print kitchen check
2. **Close Table (Paid)** → Should print receipt
3. **Printer Offline** → Should show warning but not crash
4. **Network Issue** → Should retry 2 times then show warning

## Troubleshooting

### Printer Not Responding
- Verify printer is on and connected to network
- Check printer IP in `.env` file
- Test connection using `PrinterService.testConnections()`

### Print Failed But No Error
- Check printer has paper
- Verify port 9100 is open on network
- Ensure no firewall blocking connection

### Compilation Errors
- Ensure `flutter_dotenv` and `flutter_esc_pos_utils` are in `pubspec.yaml`
- Run `flutter pub get`
- Ensure `.env` file is loaded in `main.dart`

## Need Help?

Check the full documentation in `docs/PRINTER_SERVICE.md` for more details and examples.
