# Kitchen Check Print Preview

## Visual Example of What Prints

When you confirm Order #123 with:
- Tables: 5, 6
- Waiter: vaanskii
- Items: 2x ხინკალი, 1x ქაბაბი, 3x ლუდი 0.5L, 1x ლიმონათი
- Time: 14:30:25

---

```
╔════════════════════════════════════════════════╗
║                                                ║
║                                                ║
║        *** სამზარეულოს ჩეკი ***              ║
║                                                ║
║                                                ║
║  შეკვეთა #: 123                               ║
║                                                ║
║                                                ║
║  მაგიდა: 5, 6                                 ║
║                                                ║
║  ოფიციანტი: vaanskii                         ║
║                                                ║
║  დრო: 14:30:25                                ║
║  ────────────────────────────────────────     ║
║                                                ║
║  პროდუქცია:                                   ║
║                                                ║
║  2x ხინკალი                                   ║
║                                                ║
║  1x ქაბაბი                                    ║
║                                                ║
║  3x ლუდი 0.5L                                 ║
║                                                ║
║  1x ლიმონათი                                  ║
║                                                ║
║                                                ║
║                                                ║
║                                                ║
╚════════════════════════════════════════════════╝
      [✂️ Paper cut here]
```

---

## Font Sizes Used

| Section | Size | Purpose |
|---------|------|---------|
| Header "სამზარეულოს ჩეკი" | 2x2 (Large) | Immediately identifies as kitchen check |
| Order # "შეკვეთა #" | 1x1 (Bold) | Clear order identification |
| Table "მაგიდა" | 2x1 (Big) | **Emphasized** - most important for kitchen |
| Waiter "ოფიციანტი" | 1x1 (Bold) | Who to ask if questions |
| Time "დრო" | 1x1 (Normal) | Timestamp reference |
| Items Header "პროდუქცია" | 1x1 (Bold) | Section separator |
| Individual Items | 2x1 (Big) | **Easy to read from distance** |

---

## Key Design Decisions

### ✅ What's Included
- **Table Number** - LARGE font, easy to see
- **Quantity & Item Name** - Clear, readable
- **Waiter Name** - For kitchen questions
- **Order Number** - Tracking
- **Time Created** - Freshness reference

### ❌ What's NOT Included
- **No prices** - Kitchen doesn't need to know cost
- **No totals** - Focus on preparation only
- **No payment info** - Not relevant for kitchen

### 🎨 Visual Layout
- **Extra spacing** between items - Easy to scan quickly
- **Bold text** for important info
- **Large items** - Readable from cooking distance
- **Clean separators** - Clear sections

---

## Real-World Example Scenarios

### Scenario 1: Simple Order
```
*** სამზარეულოს ჩეკი ***

შეკვეთა #: 45
მაგიდა: 3
ოფიციანტი: ana
დრო: 12:15:30
─────────────────────────

პროდუქცია:

1x ხაჭაპური
```

### Scenario 2: Large Party
```
*** სამზარეულოს ჩეკი ***

შეკვეთა #: 78
მაგიდა: 10, 11, 12
ოფიციანტი: giorgi
დრო: 19:45:12
─────────────────────────

პროდუქცია:

5x ხინკალი

3x მცხეთა

2x ქაბაბი

8x ლუდი 0.5L

4x ლიმონათი

2x ყველი
```

### Scenario 3: Admin Order
```
*** სამზარეულოს ჩეკი ***

შეკვეთა #: 99
მაგიდა: VIP 1
ოფიციანტი: vaanskii
დრო: 20:30:00
─────────────────────────

პროდუქცია:

2x სტეიკი

1x ღვინო
```

---

## Comparison: Before vs After

### ❌ Old Way (Manual)
1. Waiter writes order on paper
2. Carries to kitchen
3. Kitchen reads handwriting (errors possible)
4. Paper gets lost/dirty
5. No timestamp
6. No accountability

### ✅ New Way (Automatic)
1. Waiter confirms in system (one click)
2. Kitchen printer outputs immediately
3. Clear printed Georgian text
4. Automatic timestamp
5. Waiter name recorded
6. Order number for tracking

---

## Kitchen Staff Benefits

### Quick Reading
- **3-5 seconds** to read entire check
- Large text readable from 2-3 meters away
- No need to squint at handwriting
- Clear quantities

### No Confusion
- Georgian language (native)
- Standard format every time
- No price distractions
- Just what to cook

### Organization
- Can pin checks in order
- Time stamp shows priority
- Order number for tracking
- Table number clearly visible

---

## Technical Details

### Paper Width
- **80mm** thermal paper
- Standard for most POS printers
- ~48 characters per line (normal size)
- ~24 characters per line (double width)

### Character Encoding
- **UTF-8** for Georgian characters
- Most modern thermal printers support this
- If issues, check printer's character set settings

### Print Speed
- **~2-3 seconds** for typical order
- Depends on number of items
- Network latency: ~0.5-1 second

### Paper Usage
- Small orders: ~10cm of paper
- Large orders: ~20cm of paper
- Efficient - no waste

---

## Troubleshooting Visual Issues

### Georgian Text Looks Wrong
**Problem:** Boxes, question marks, or garbled text
**Solution:** 
- Printer may not support Georgian Unicode
- Check printer settings for UTF-8 support
- Update printer firmware if available

### Text Too Small
**Problem:** Kitchen staff can't read from distance
**Solution:** Already using large fonts (Size 2x1 for items)
- Can increase to Size 2x2 if needed
- Edit `_generateKitchenCheckBytes()` in printer_service.dart

### Text Too Large
**Problem:** Takes too much paper
**Solution:** Reduce font sizes in printer_service.dart
- Current sizes are optimized for readability

### Items Running Off Page
**Problem:** Long item names cut off
**Solution:** 
- 80mm paper supports ~40 Georgian characters at Size 1
- At Size 2x1: ~20 characters
- Item names should be concise

---

## Customization Options

If you want to adjust the layout, edit `lib/services/printer_service.dart`:

### Change Font Size
```dart
// Current (items):
styles: const PosStyles(
  height: PosTextSize.size2,  // ← Change this
  width: PosTextSize.size1,   // ← Or this
),

// Options:
// size1 = Normal (100%)
// size2 = Double (200%)
// size3 = Triple (300%)
```

### Add More Spacing
```dart
bytes += generator.emptyLines(3);  // ← Change number
```

### Change Alignment
```dart
styles: const PosStyles(
  align: PosAlign.left,    // or center, right
),
```

---

**This is exactly what your kitchen will see! 📄**
