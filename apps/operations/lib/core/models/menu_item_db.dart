import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'menu_item_db.g.dart';

const Uuid _uuid = Uuid();

/// Mints one stable [MenuItemDB.id].
///
/// Uuid v4 for the same reason `Package.packageId` and reservation ids are:
/// two items created in the same millisecond, on two POS terminals, offline,
/// must not collide. Never derived from the name, the path, the price, the
/// list position or the clock.
String newMenuItemId() => _uuid.v4();

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

/// One product on the menu.
///
/// Identity is [id], not the item's name or where it sits in the tree. An item
/// is a position in a category's list, so before [id] existed the only thing
/// that could identify it was its path — which meant renaming Khinkali to
/// Khinkali Classic, or moving it to another category, made it a different
/// product to every reader downstream: the audit timeline split in two, and
/// the Cloud mirror (which matches on `nameEn` under a parent) grew a second
/// row and left the old one behind.
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

  /// Stable business identity: a uuid minted once, on the POS, offline, and
  /// never regenerated. It survives a rename, a price change, an availability
  /// or kitchen-routing change, a category move, app restart, backup/restore
  /// and Cloud sync.
  ///
  /// Nullable only because rows written before this field existed carry no
  /// value. `MenuRepository.ensureStableItemIds` assigns those exactly once
  /// (Hive migration v7, and again after a restore of an older backup); it is
  /// deliberately not minted on read, because a fresh uuid per decode would be
  /// the opposite of an identity. Treat null as "not yet migrated", never as
  /// "make one up here".
  @HiveField(5)
  String? id;

  MenuItemDB({
    required this.translationsEn,
    required this.translationsKa,
    this.price,
    this.variants,
    this.sendToKitchen = true,
    this.id,
  });

  /// A new item, with its identity minted up front.
  factory MenuItemDB.create({
    required Map<String, String> translationsEn,
    required Map<String, String> translationsKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool sendToKitchen = true,
  }) => MenuItemDB(
    translationsEn: translationsEn,
    translationsKa: translationsKa,
    price: price,
    variants: variants,
    sendToKitchen: sendToKitchen,
    id: newMenuItemId(),
  );

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
