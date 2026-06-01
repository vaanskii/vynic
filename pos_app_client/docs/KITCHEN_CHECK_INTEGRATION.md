# Kitchen Check Integration - Georgian Language

## Overview
When an order is confirmed in the POS system, a kitchen check is automatically printed to the kitchen printer in Georgian language with no prices.

## What Gets Printed

### Kitchen Check Format (Georgian)

```
    *** სამზარეულოს ჩეკი ***

    შეკვეთა #: 123
    მაგიდა: 5, 6
    ოფიციანტი: vaanskii
    დრო: 14:30:25
    ─────────────────────────────

    პროდუქცია:
    
    2x ხინკალი
    
    1x ქაბაბი
    
    3x ლუდი 0.5L
    
    1x ლიმონათი
    



    [Paper cut]
```

## Integration Details

### Workflow

1. **User Confirms Order**
   - User clicks "Confirm Order" button in Order Detail Screen
   - Order status changes from `pending` to `confirmed`

2. **Printing Process**
   - Loading dialog appears: "იბეჭდება სამზარეულოს ჩეკი..."
   - System connects to kitchen printer (192.168.100.33:9100)
   - Generates ESC/POS commands with Georgian text
   - Sends data to printer
   - Retries up to 2 times if connection fails

3. **Result Notification**
   - Success: Green snackbar "✓ სამზარეულოს ჩეკი დაიბეჭდა"
   - Failure: Orange snackbar "⚠️ პრინტერი მიუწვდომელია"

### What's Included in Kitchen Check

✅ **Included:**
- Order number (შეკვეთა #)
- Table number(s) (მაგიდა)
- Waiter/Admin username (ოფიციანტი)
- Time order was created (დრო)
- List of items with quantities (პროდუქცია)

❌ **NOT Included:**
- Item prices
- Total price
- Payment information

### Georgian Translations Used

| English | Georgian |
|---------|----------|
| Kitchen Check | სამზარეულოს ჩეკი |
| Order # | შეკვეთა # |
| Table | მაგიდა |
| Waiter | ოფიციანტი |
| Time | დრო |
| Products/Items | პროდუქცია |
| Printing kitchen check... | იბეჭდება სამზარეულოს ჩეკი... |
| Kitchen check printed | სამზარეულოს ჩეკი დაიბეჭდა |
| Printer unavailable | პრინტერი მიუწვდომელია |

## Code Implementation

### Files Modified

1. **`lib/services/printer_service.dart`**
   - Updated `printKitchenCheck()` to accept `waiterName` and `createdAt`
   - Updated `_generateKitchenCheckBytes()` to use Georgian text
   - Removed prices from kitchen check
   - Increased font size for items (easier to read in kitchen)

2. **`lib/screens/order_detail_screen.dart`**
   - Added `import '../services/printer_service.dart'`
   - Updated `_updateStatus()` method to print when status changes to 'confirmed'
   - Added loading dialog during printing
   - Added success/failure notifications in Georgian

### Order Confirmation Flow

```dart
// In _updateStatus method:
if (newStatus == 'confirmed' && _order != null) {
  // 1. Format items (quantity + name only)
  final kitchenItems = _order!.items.map((item) {
    return '${item.quantity}x ${item.itemName}';
  }).toList();

  // 2. Show loading dialog
  showDialog(...);

  // 3. Print to kitchen
  final printSuccess = await PrinterService.printKitchenCheck(
    items: kitchenItems,
    tableNumber: _order!.tableNumbers.join(', '),
    orderNumber: _order!.orderId.toString(),
    waiterName: _order!.createdBy,
    createdAt: _order!.createdAt,
  );

  // 4. Close loading & show result
  Navigator.pop(context);
  ScaffoldMessenger.showSnackBar(...);
}
```

## Usage Example

### Scenario: Confirming Order #123

**Order Details:**
- Tables: 5, 6
- Waiter: vaanskii
- Items:
  - 2x ხინკალი
  - 1x ქაბაბი
  - 3x ლუდი 0.5L
  - 1x ლიმონათი
- Created: 19/10/2025 14:30:25

**User Action:**
1. Opens Order Detail Screen
2. Clicks "Confirm Order" button

**System Response:**
1. Shows loading: "იბეჭდება სამზარეულოს ჩეკი..."
2. Connects to printer at 192.168.100.33:9100
3. Prints kitchen check with:
   - შეკვეთა #: 123
   - მაგიდა: 5, 6
   - ოფიციანტი: vaanskii
   - დრო: 14:30:25
   - პროდუქცია: [items list]
4. Shows success message
5. Order status → "confirmed" (blue badge)

## Error Handling

### Printer Offline
- **Symptom**: Kitchen printer is turned off or disconnected
- **Behavior**: 
  - Tries to connect (5 second timeout)
  - Retries 2 more times (500ms, 1000ms delays)
  - Shows orange warning: "⚠️ პრინტერი მიუწვდომელია"
  - **Order still confirmed** (doesn't block workflow)

### Network Issues
- **Symptom**: Network connection lost
- **Behavior**:
  - Same retry logic as above
  - User can continue working
  - Kitchen check not printed (manual reprint may be needed)

### Invalid Printer IP
- **Symptom**: Wrong IP in .env file
- **Behavior**:
  - Connection fails immediately
  - Shows warning message
  - Check console logs for details

## Testing

### Test Checklist

- [ ] Confirm order with printer ON → Should print successfully
- [ ] Confirm order with printer OFF → Should show warning but not crash
- [ ] Confirm order with multiple tables → Should print all table numbers
- [ ] Confirm order with Georgian item names → Should print correctly
- [ ] Verify no prices are printed
- [ ] Verify waiter name appears
- [ ] Verify time appears correctly
- [ ] Test with admin user
- [ ] Test with regular waiter user

### Manual Testing Steps

1. **Setup**:
   - Ensure kitchen printer is at 192.168.100.33
   - Printer has paper loaded
   - Printer is powered on

2. **Create Order**:
   - Select tables
   - Add items to cart
   - Place order
   - Order status = "pending"

3. **Confirm Order**:
   - Open order detail screen
   - Click "Confirm Order"
   - Watch for loading dialog
   - Verify success message
   - Check printer output

4. **Verify Print**:
   - Check Georgian text is readable
   - Verify all information is present
   - Confirm no prices are shown
   - Ensure paper cuts at the end

## Troubleshooting

### Georgian Characters Not Printing
- **Problem**: Georgian text shows as boxes or question marks
- **Solution**: Most modern ESC/POS printers support Unicode. If not, may need to configure printer's character set.

### Print Quality Issues
- **Problem**: Text is too small or too large
- **Solution**: Adjust `PosTextSize` values in `_generateKitchenCheckBytes()`

### Printer Not Responding
- **Problem**: No output from printer
- **Solution**: 
  1. Ping printer IP: `ping 192.168.100.33`
  2. Check port 9100 is open
  3. Verify printer is in network mode
  4. Check .env file has correct IP

### Order Confirmed But No Print
- **Problem**: Order confirmed but nothing printed
- **Solution**: Check console logs for error messages. Order workflow continues even if print fails.

## Future Enhancements

Potential improvements:
- [ ] Add reprint button for kitchen checks
- [ ] Add kitchen printer status indicator
- [ ] Support multiple kitchen printers (for different stations)
- [ ] Add printer test button in settings
- [ ] Add print queue management
- [ ] Add order number barcode/QR code
- [ ] Customize font sizes per kitchen preference

## Configuration

### Printer Settings (.env)
```env
PRINTER_KITCHEN_IP=192.168.100.33
PRINTER_RECEIPT_IP=192.168.100.34
PRINTER_PORT=9100
```

### Font Sizes
- **Header**: Size 2x2 (large)
- **Table Number**: Size 2x1 (emphasis on table)
- **Order Info**: Size 1x1 (normal)
- **Items**: Size 2x1 (easier to read from distance)

## Benefits

✅ **For Kitchen Staff:**
- Clear Georgian text
- Large, readable font
- Only relevant information
- No distracting prices
- Quick to read items

✅ **For Waiters:**
- Automatic printing (no manual steps)
- Confirmation feedback
- Error handling (doesn't block workflow)
- Clear success/failure messages

✅ **For Management:**
- Timestamp tracking
- Waiter accountability
- Order traceability
- Consistent format

---

**Last Updated**: October 19, 2025
**Status**: ✅ Implemented and Ready
