class MenuCategory {
  final String slug;
  final Map<String, Translation> translations;
  final List<MenuItem>? items;
  final List<MenuSubcategory>? subcategories;
  final bool sendToKitchen;

  MenuCategory({
    required this.slug,
    required this.translations,
    this.items,
    this.subcategories,
    this.sendToKitchen = true,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      slug: json['slug'] as String,
      translations: (json['translations'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Translation.fromJson(value)),
      ),
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
      items: json['items'] != null
          ? (json['items'] as List)
                .map((item) => MenuItem.fromJson(item))
                .toList()
          : null,
      subcategories: json['subcategories'] != null
          ? (json['subcategories'] as List)
                .map((sub) => MenuSubcategory.fromJson(sub))
                .toList()
          : null,
    );
  }

  String getName(String language) {
    return translations[language]?.name ?? translations['en']?.name ?? slug;
  }
}

class MenuSubcategory {
  final String slug;
  final Map<String, Translation> translations;
  final List<MenuItem> items;

  MenuSubcategory({
    required this.slug,
    required this.translations,
    required this.items,
  });

  factory MenuSubcategory.fromJson(Map<String, dynamic> json) {
    return MenuSubcategory(
      slug: json['slug'] as String,
      translations: (json['translations'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Translation.fromJson(value)),
      ),
      items: (json['items'] as List)
          .map((item) => MenuItem.fromJson(item))
          .toList(),
    );
  }

  String getName(String language) {
    return translations[language]?.name ?? translations['en']?.name ?? slug;
  }
}

class MenuItem {
  final Map<String, Translation> translations;
  final double? price;
  final List<MenuVariant>? variants;
  final bool sendToKitchen;

  MenuItem({
    required this.translations,
    this.price,
    this.variants,
    this.sendToKitchen = true,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      translations: (json['translations'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Translation.fromJson(value)),
      ),
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
      variants: json['variants'] != null
          ? (json['variants'] as List)
                .map((variant) => MenuVariant.fromJson(variant))
                .toList()
          : null,
    );
  }

  String getName(String language) {
    return translations[language]?.name ?? translations['en']?.name ?? '';
  }

  bool hasVariants() => variants != null && variants!.isNotEmpty;
}

class MenuVariant {
  final double size;
  final double price;

  MenuVariant({required this.size, required this.price});

  factory MenuVariant.fromJson(Map<String, dynamic> json) {
    return MenuVariant(
      size: (json['size'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
    );
  }

  String getSizeLabel() {
    if (size < 1) {
      return '${(size * 1000).toInt()} ml';
    } else {
      return '${size.toStringAsFixed(size.truncateToDouble() == size ? 1 : 2)} L';
    }
  }
}

class Translation {
  final String name;

  Translation({required this.name});

  factory Translation.fromJson(Map<String, dynamic> json) {
    return Translation(name: json['name'] as String);
  }
}
