class TakeawayMenuItem {
  final String name;
  final double price;

  const TakeawayMenuItem({required this.name, required this.price});
}

class TakeawayCartEntry {
  final String? itemName;
  final String? menuItemId;
  final String? variantId;
  final double price;
  int quantity;

  TakeawayCartEntry({
    required this.price,
    this.quantity = 1,
    this.itemName,
    this.menuItemId,
    this.variantId,
  });
}

class TakeawayCreatePayload {
  final String customerName;
  final String pickupTime;
  final String waiterName;
  final List<Map<String, dynamic>> items;

  const TakeawayCreatePayload({
    required this.customerName,
    required this.pickupTime,
    required this.waiterName,
    required this.items,
  });
}
