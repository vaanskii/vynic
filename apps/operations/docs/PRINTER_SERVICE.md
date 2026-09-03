# Printer Service Documentation

## Overview
The `PrinterService` class provides a production-ready solution for printing to POS thermal printers over raw TCP sockets. It supports both kitchen checks and customer receipts with automatic retry logic and comprehensive error handling.

## Features
- ✅ Raw TCP socket connections to network printers
- ✅ ESC/POS command generation for 80mm thermal printers
- ✅ Kitchen check printing
- ✅ Customer receipt printing
- ✅ Automatic retry logic (up to 2 retries with exponential backoff)
- ✅ Comprehensive error handling
- ✅ Connection testing utilities
- ✅ Environment-based configuration

## Prerequisites

### Dependencies (Already Installed)
```yaml
dependencies:
  flutter_dotenv: ^6.0.0
  flutter_esc_pos_utils: ^1.0.1
```

### Environment Configuration
The `.env` file must contain:
```env
PRINTER_TYPE=network
PRINTER_KITCHEN_IP=192.168.100.33
PRINTER_RECEIPT_IP=192.168.100.34
PRINTER_PORT=9100
```

### Printer Requirements
- Network-enabled thermal printer with ESC/POS support
- 80mm paper width
- Raw TCP socket support (typically port 9100)
- Static IP address configured

## Usage

### 1. Kitchen Check Printing

Print order items to the kitchen printer:

```dart
import 'package:pos_app/services/printer_service.dart';

// Simple example
final success = await PrinterService.printKitchenCheck(
  items: [
    '2x Burger',
    '1x Fries',
    '3x Coca-Cola 0.5L',
  ],
  tableNumber: 'Table 5',
  orderNumber: '123',
);

if (success) {
  print('Kitchen check sent successfully');
} else {
  print('Failed to print kitchen check');
}
```

**Printed Output:**
```
*** KITCHEN CHECK ***

Order #: 123
Table: Table 5
Time: 14:30:25
─────────────────────

ITEMS:
2x Burger
1x Fries
3x Coca-Cola 0.5L


[Paper cut]
```

### 2. Receipt Printing

Print customer receipt with total:

```dart
import 'package:pos_app/services/printer_service.dart';

final success = await PrinterService.printReceipt(
  items: [
    '2 x Burger                    30.00',
    '1 x Fries                      5.00',
    '3 x Coca-Cola 0.5L            12.00',
  ],
  total: 47.00,
  tableNumber: 'Table 5',
  orderNumber: '123',
  paymentMethod: 'Cash',
);

if (success) {
  print('Receipt printed successfully');
} else {
  print('Failed to print receipt');
}
```

**Printed Output:**
```
        RECEIPT

Order #: 123
Table: Table 5
Date: 19/10/2025 14:30
─────────────────────

2 x Burger                    30.00
1 x Fries                      5.00
3 x Coca-Cola 0.5L            12.00
─────────────────────

            TOTAL: 47.00

Payment: Cash


      Thank You!

[Paper cut]
```

### 3. Test Printer Connections

Before using the printers, test connectivity:

```dart
final results = await PrinterService.testConnections();

print('Kitchen Printer: ${results['kitchen'] ? 'Connected' : 'Failed'}');
print('Receipt Printer: ${results['receipt'] ? 'Connected' : 'Failed'}');
```

## Integration Examples

### Example 1: Order Confirmation (Kitchen Check)

In your `order_detail_screen.dart`:

```dart
Future<void> _confirmOrder() async {
  // Format items for kitchen
  final kitchenItems = widget.order.items.map((item) {
    return '${item.quantity}x ${item.itemName}';
  }).toList();

  // Update order status in database
  await DatabaseService.updateOrderStatus(
    orderId: widget.order.orderId,
    status: 'confirmed',
  );

  // Print kitchen check
  final printSuccess = await PrinterService.printKitchenCheck(
    items: kitchenItems,
    tableNumber: widget.order.tableNumbers.join(', '),
    orderNumber: widget.order.orderId.toString(),
  );

  if (!printSuccess) {
    // Show warning but don't block the process
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warning: Kitchen printer not available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Navigate back
  if (mounted) {
    Navigator.of(context).pop();
  }
}
```

### Example 2: Table Close (Receipt)

In your `order_detail_screen.dart`:

```dart
Future<void> _closeTable() async {
  // Format items for receipt
  final receiptItems = widget.order.items.map((item) {
    final quantity = item.quantity;
    final name = item.itemName;
    final itemTotal = item.total;
    
    // Format: "2 x Burger                    30.00"
    final itemLine = '$quantity x $name';
    return itemLine.padRight(30) + itemTotal.toStringAsFixed(2).padLeft(10);
  }).toList();

  // Update order status to paid
  await DatabaseService.updateOrderStatus(
    orderId: widget.order.orderId,
    status: 'paid',
  );

  // Print receipt
  final printSuccess = await PrinterService.printReceipt(
    items: receiptItems,
    total: widget.order.totalAmount,
    tableNumber: widget.order.tableNumbers.join(', '),
    orderNumber: widget.order.orderId.toString(),
    paymentMethod: 'Cash', // Or get from a payment method selector
  );

  if (!printSuccess) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warning: Receipt printer not available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Navigate back to home
  if (mounted) {
    Navigator.of(context).pop();
  }
}
```

### Example 3: Settings Screen - Test Printers

Create a settings screen to test printer connections:

```dart
class PrinterSettingsScreen extends StatefulWidget {
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool? _kitchenStatus;
  bool? _receiptStatus;
  bool _testing = false;

  Future<void> _testPrinters() async {
    setState(() {
      _testing = true;
      _kitchenStatus = null;
      _receiptStatus = null;
    });

    final results = await PrinterService.testConnections();

    setState(() {
      _testing = false;
      _kitchenStatus = results['kitchen'];
      _receiptStatus = results['receipt'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printer Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildPrinterStatus('Kitchen Printer', _kitchenStatus),
            const SizedBox(height: 16),
            _buildPrinterStatus('Receipt Printer', _receiptStatus),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _testing ? null : _testPrinters,
              child: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test Connections'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterStatus(String name, bool? status) {
    return Card(
      child: ListTile(
        leading: Icon(
          status == null
              ? Icons.help_outline
              : status
                  ? Icons.check_circle
                  : Icons.error,
          color: status == null
              ? Colors.grey
              : status
                  ? Colors.green
                  : Colors.red,
        ),
        title: Text(name),
        subtitle: Text(
          status == null
              ? 'Not tested'
              : status
                  ? 'Connected'
                  : 'Connection failed',
        ),
      ),
    );
  }
}
```

## Technical Details

### Connection Flow
1. **Load Configuration**: Read printer IP from `.env`
2. **Generate Commands**: Create ESC/POS byte commands
3. **Establish Connection**: Connect via raw TCP socket (5 second timeout)
4. **Send Data**: Write bytes to socket
5. **Flush & Close**: Ensure data is sent and close connection
6. **Retry Logic**: If fails, retry up to 2 more times with exponential backoff

### Retry Mechanism
- **Initial Attempt**: Immediate connection attempt
- **Retry 1**: Wait 500ms, then retry
- **Retry 2**: Wait 1000ms, then retry
- **Total Attempts**: 3 (initial + 2 retries)

### Error Handling
The service handles:
- `SocketException`: Network errors, connection refused
- Connection timeouts (5 seconds)
- Socket write failures
- Invalid printer IP configurations

All errors are logged to console with descriptive messages.

### ESC/POS Commands Used
- `reset()`: Initialize printer
- `text()`: Print text with styling (size, alignment, bold)
- `hr()`: Print horizontal line
- `emptyLines()`: Add blank lines
- `cut()`: Cut paper

### Paper Size
- **Width**: 80mm
- **Profile**: Default capability profile
- **Character Width**: ~48 characters per line at normal size

## Troubleshooting

### Printer Not Responding
1. Check printer is powered on
2. Verify network connection (ping printer IP)
3. Ensure printer port is 9100 (or correct port in `.env`)
4. Check firewall settings on the network

### Connection Timeout
- Printer may be busy processing another job
- Network congestion
- Printer offline or unreachable

### Garbled Output
- Ensure printer supports ESC/POS commands
- Check paper width matches 80mm
- Verify printer model compatibility

### Test Connection First
Always test printer connections before production use:
```dart
final results = await PrinterService.testConnections();
if (results['kitchen'] != true) {
  print('Kitchen printer not available!');
}
```

## Network Configuration

### Recommended Setup
- **Static IP**: Assign static IPs to printers (via router DHCP reservation)
- **Same Subnet**: Ensure POS device and printers are on same network
- **No Firewall**: Allow TCP port 9100 on all devices
- **Low Latency**: Use wired connection for printers if possible

### IP Configuration Example
```
POS Device:      192.168.100.10
Kitchen Printer: 192.168.100.33
Receipt Printer: 192.168.100.34
Port:            9100 (all)
```

## Performance

### Typical Print Times
- Kitchen Check: 1-2 seconds
- Receipt: 1-2 seconds
- Connection Test: < 1 second per printer

### Optimization Tips
1. Pre-format items before calling print methods
2. Don't await print operations if user experience can continue
3. Cache printer status to avoid repeated connection tests
4. Consider printing in background for better UX

## Future Enhancements

Potential improvements:
- [ ] Bluetooth printer support
- [ ] USB printer support
- [ ] Custom paper sizes (58mm, 110mm)
- [ ] Logo/image printing
- [ ] Barcode/QR code generation
- [ ] Multi-language character sets (Georgian, etc.)
- [ ] Printer queue management
- [ ] Automatic printer discovery

## Support

For issues or questions:
1. Check printer logs in console output
2. Verify `.env` configuration
3. Test printer connectivity separately
4. Ensure ESC/POS compatibility

## License

Part of the POS App project.
