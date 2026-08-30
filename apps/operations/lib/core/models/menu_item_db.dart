import 'package:hive/hive.dart';

part 'menu_item_db.g.dart';

@HiveType(typeId: 5)
class MenuCategoryDB extends HiveObject {
  @HiveField(0)
  String slug;

  @HiveField(1)
  Map<String, String> translationsEn; // {name: "..."}

  @HiveField(2)
  Map<String, String> translationsKa; // {name: "..."}

  @HiveField(3)
  List<MenuItemDB>? items;

  @HiveField(4)
  List<MenuSubcategoryDB>? subcategories;

  @HiveField(5)
  bool sendToKitchen;

  MenuCategoryDB({
    required this.slug,
    required this.translationsEn,
    required this.translationsKa,
    this.items,
    this.subcategories,
    this.sendToKitchen = true,
  });

  String getName(String language) {
    if (language == 'ka') {
      return translationsKa['name'] ?? translationsEn['name'] ?? slug;
    }
    return translationsEn['name'] ?? slug;
  }
}

@HiveType(typeId: 6)
class MenuSubcategoryDB extends HiveObject {
  @HiveField(0)
  String slug;

  @HiveField(1)
  Map<String, String> translationsEn;

  @HiveField(2)
  Map<String, String> translationsKa;

  @HiveField(3)
  List<MenuItemDB> items;

  MenuSubcategoryDB({
    required this.slug,
    required this.translationsEn,
    required this.translationsKa,
    required this.items,
  });

  String getName(String language) {
    if (language == 'ka') {
      return translationsKa['name'] ?? translationsEn['name'] ?? slug;
    }
    return translationsEn['name'] ?? slug;
  }
}

@HiveType(typeId: 7)
class MenuItemDB extends HiveObject {
  @HiveField(0)
  Map<String, String> translationsEn;

  @HiveField(1)
  Map<String, String> translationsKa;

  @HiveField(2)
  double? price;

  @HiveField(3)
  List<MenuVariantDB>? variants;

  @HiveField(4)
  bool sendToKitchen;

  MenuItemDB({
    required this.translationsEn,
    required this.translationsKa,
    this.price,
    this.variants,
    this.sendToKitchen = true,
  });

  String getName(String language) {
    if (language == 'ka') {
      return translationsKa['name'] ?? translationsEn['name'] ?? '';
    }
    return translationsEn['name'] ?? '';
  }

  bool hasVariants() => variants != null && variants!.isNotEmpty;
}

@HiveType(typeId: 8)
class MenuVariantDB {
  @HiveField(0)
  double size;

  @HiveField(1)
  double price;

  MenuVariantDB({required this.size, required this.price});

  String getSizeLabel() {
    if (size < 1) {
      return '${(size * 1000).toInt()} ml';
    } else {
      return '${size.toStringAsFixed(size.truncateToDouble() == size ? 1 : 2)} L';
    }
  }
}
