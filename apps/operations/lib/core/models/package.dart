import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'package.g.dart';

@HiveType(typeId: 11)
class Package extends HiveObject {
  @HiveField(0)
  String packageId;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? description;

  @HiveField(3)
  List<PackageItem> items;

  @HiveField(4)
  double pricePerPerson;

  @HiveField(5)
  bool isActive;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  String createdBy;

  @HiveField(8)
  int servingSize;

  @HiveField(9)
  List<String> allowedTables;

  Package({
    required this.packageId,
    required this.name,
    this.description,
    required this.items,
    required this.pricePerPerson,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    required this.servingSize,
    List<String>? allowedTables,
  }) : allowedTables = allowedTables ?? <String>[];

  factory Package.create({
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    required String createdBy,
    List<String>? allowedTables,
  }) {
    return Package(
      packageId: const Uuid().v4(),
      name: name,
      description: description,
      items: items,
      pricePerPerson: pricePerPerson,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      servingSize: servingSize,
      allowedTables: allowedTables ?? <String>[],
    );
  }

  double getTotalQuantity() {
    return items.fold(0, (sum, item) => sum + item.quantity);
  }
}

@HiveType(typeId: 12)
class PackageItem extends HiveObject {
  @HiveField(0)
  String itemKey; // Format: "categorySlug|itemName" or "categorySlug|itemName|variantSize"

  @HiveField(1)
  String itemName;

  @HiveField(2)
  int quantity;

  @HiveField(3)
  double unitPrice;

  PackageItem({
    required this.itemKey,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => unitPrice * quantity;
}
