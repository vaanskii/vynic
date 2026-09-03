class TakeawayMenuItem {
  final String name;
  final double price;

  const TakeawayMenuItem({required this.name, required this.price});
}

class TakeawayCartEntry {
  final double price;
  int quantity;

  TakeawayCartEntry({required this.price, this.quantity = 1});
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
