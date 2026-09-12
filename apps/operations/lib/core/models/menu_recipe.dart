import 'package:vynic/core/models/inventory.dart';

/// One Menu Item's consumption definition, as the Manager edits it.
///
/// The same shape covers a bottled drink, a draft pour and a four-ingredient
/// recipe. They differ only in how many components they carry, so the Manager
/// UI presents two of them more simply rather than modelling them separately.
class MenuRecipe {
  const MenuRecipe({
    required this.id,
    required this.menuItemId,
    required this.menuItemName,
    required this.isActive,
    required this.revision,
    required this.components,
    this.variantId,
    this.variantLabel,
    this.yieldQuantity = '1.000',
    this.notes,
    this.updatedByName,
  });

  final String id;

  /// The durable identity. A Menu Item rename never moves a definition.
  final String menuItemId;

  /// Frozen display context, not identity.
  final String menuItemName;

  final String? variantId;
  final String? variantLabel;

  /// How many sold units the component quantities describe.
  final String yieldQuantity;

  final bool isActive;
  final String? notes;

  /// Bumped by Cloud on every save.
  final int revision;

  final String? updatedByName;
  final List<MenuRecipeComponent> components;

  double get yieldValue => double.tryParse(yieldQuantity) ?? 1;

  /// A single-component definition is a direct product link, which the editor
  /// presents as "link to stock" rather than as a recipe.
  bool get isDirectLink => components.length == 1;

  factory MenuRecipe.fromJson(Map<String, dynamic> json) {
    return MenuRecipe(
      id: _text(json['id']) ?? '',
      menuItemId: _text(json['menuItemId']) ?? '',
      menuItemName: _text(json['menuItemName']) ?? '',
      variantId: _text(json['variantId']),
      variantLabel: _text(json['variantLabel']),
      yieldQuantity: _text(json['yieldQuantity']) ?? '1.000',
      isActive: json['isActive'] as bool? ?? true,
      notes: _text(json['notes']),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      updatedByName: _text(json['updatedByName']),
      components: (json['components'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                MenuRecipeComponent.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
    );
  }
}

/// One Stock Item a recipe consumes.
class MenuRecipeComponent {
  const MenuRecipeComponent({
    required this.stockItemId,
    required this.stockItemName,
    required this.quantity,
    required this.unit,
    required this.baseQuantity,
    required this.baseUnit,
    required this.baseQuantityPerUnit,
    this.id = '',
    this.sequence = 0,
    this.notes,
  });

  final String id;
  final int sequence;

  /// The durable identity behind the display name.
  final String stockItemId;
  final String stockItemName;

  /// As entered — "35 g" — for the whole recipe yield.
  final String quantity;
  final InventoryUnit unit;

  /// The same amount in the Stock Item's own base unit.
  final String baseQuantity;
  final InventoryUnit baseUnit;

  /// Consumption for one sold unit, already divided by the yield.
  final String baseQuantityPerUnit;

  final String? notes;

  /// True when "500 ml" is stored as "0.500 L".
  bool get isConverted => unit != baseUnit;

  factory MenuRecipeComponent.fromJson(Map<String, dynamic> json) {
    return MenuRecipeComponent(
      id: _text(json['id']) ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      stockItemId: _text(json['stockItemId']) ?? '',
      stockItemName: _text(json['stockItemName']) ?? '',
      quantity: _text(json['quantity']) ?? '0',
      unit: InventoryUnit.parse(_text(json['unit']) ?? 'piece'),
      baseQuantity: _text(json['baseQuantity']) ?? '0',
      baseUnit: InventoryUnit.parse(_text(json['baseUnit']) ?? 'piece'),
      baseQuantityPerUnit: _text(json['baseQuantityPerUnit']) ?? '0',
      notes: _text(json['notes']),
    );
  }
}

/// Whether one product is configured, without loading its whole card.
class MenuRecipeSummary {
  const MenuRecipeSummary({
    required this.id,
    required this.isActive,
    required this.componentCount,
    this.revision = 1,
  });

  final String id;
  final bool isActive;
  final int componentCount;
  final int revision;

  static MenuRecipeSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = _text(json['id']);
    if (id == null) return null;
    return MenuRecipeSummary(
      id: id,
      isActive: json['isActive'] as bool? ?? true,
      componentCount: (json['componentCount'] as num?)?.toInt() ?? 0,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
    );
  }
}

/// One Menu Item in the recipe list, configured or not.
///
/// A product with no definition is a first-class row here: the gap is what the
/// Manager is looking for.
class RecipeMenuItem {
  const RecipeMenuItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    this.posMenuItemId,
    this.categoryName,
    this.parentCategoryName,
    this.subcategoryName,
    this.menuGroup = 'OTHER',
    this.recipe,
    this.variants = const <RecipeMenuVariant>[],
  });

  final String menuItemId;
  final String? posMenuItemId;
  final String name;
  final double price;
  final String? categoryName, parentCategoryName, subcategoryName;
  String get browseCategory => parentCategoryName ?? categoryName ?? 'სხვა';
  final String menuGroup;

  /// The definition for the item itself (`variantId = null`).
  final MenuRecipeSummary? recipe;

  final List<RecipeMenuVariant> variants;

  bool get hasVariants => variants.isNotEmpty;

  /// Configured when the item or any of its variants has an active card.
  bool get isConfigured =>
      recipe?.isActive == true ||
      variants.any((variant) => variant.recipe?.isActive == true);

  int get componentCount =>
      (recipe?.isActive == true ? recipe!.componentCount : 0) +
      variants.fold<int>(
        0,
        (total, variant) =>
            total +
            (variant.recipe?.isActive == true
                ? variant.recipe!.componentCount
                : 0),
      );

  factory RecipeMenuItem.fromJson(Map<String, dynamic> json) {
    return RecipeMenuItem(
      menuItemId: _text(json['menuItemId']) ?? '',
      posMenuItemId: _text(json['posMenuItemId']),
      name: _text(json['nameKa']) ?? _text(json['nameEn']) ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      categoryName: _text(json['categoryName']),
      parentCategoryName: _text(json['parentCategoryName']),
      subcategoryName: _text(json['subcategoryName']),
      menuGroup: _text(json['menuGroup']) ?? 'OTHER',
      recipe: MenuRecipeSummary.fromJson(json['recipe']),
      variants: (json['variants'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => RecipeMenuVariant.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
    );
  }
}

/// One size of a Menu Item, with its own definition.
class RecipeMenuVariant {
  const RecipeMenuVariant({
    required this.variantId,
    required this.size,
    required this.price,
    this.posMenuVariantId,
    this.recipe,
  });

  /// Stable variant identity. Never inferred from a display label.
  final String variantId;
  final String? posMenuVariantId;
  final double size;
  final double price;
  final MenuRecipeSummary? recipe;

  String get label => size.toString();

  factory RecipeMenuVariant.fromJson(Map<String, dynamic> json) {
    return RecipeMenuVariant(
      variantId: _text(json['variantId']) ?? '',
      posMenuVariantId: _text(json['posMenuVariantId']),
      size: (json['size'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      recipe: MenuRecipeSummary.fromJson(json['recipe']),
    );
  }
}

/// The editor's whole context: the product, and its card if it has one.
class MenuRecipeDetail {
  const MenuRecipeDetail({
    required this.menuItemId,
    required this.menuItemName,
    required this.price,
    this.currentCost,
    this.posMenuItemId,
    this.variantId,
    this.variantLabel,
    this.recipe,
  });

  final String menuItemId;
  final String? posMenuItemId;
  final String menuItemName;
  final double price;
  final String? variantId;
  final String? variantLabel;
  final MenuRecipe? recipe;
  final CurrentRecipeCost? currentCost;

  factory MenuRecipeDetail.fromJson(Map<String, dynamic> json) {
    final recipe = json['recipe'];
    return MenuRecipeDetail(
      menuItemId: _text(json['menuItemId']) ?? '',
      posMenuItemId: _text(json['posMenuItemId']),
      menuItemName: _text(json['menuItemName']) ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      variantId: _text(json['variantId']),
      variantLabel: _text(json['variantLabel']),
      currentCost: json['currentCost'] is Map
          ? CurrentRecipeCost.fromJson(
              Map<String, dynamic>.from(json['currentCost']),
            )
          : null,
      recipe: recipe is Map
          ? MenuRecipe.fromJson(Map<String, dynamic>.from(recipe))
          : null,
    );
  }
}

/// Which product consumes a Stock Item, and how much of it per sold unit.
class StockItemUsage {
  const StockItemUsage({
    required this.recipeId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantityPerUnit,
    required this.baseUnit,
    this.variantId,
    this.variantLabel,
  });

  final String recipeId;
  final String menuItemId;
  final String menuItemName;
  final String? variantId;
  final String? variantLabel;
  final String quantityPerUnit;
  final InventoryUnit baseUnit;

  factory StockItemUsage.fromJson(Map<String, dynamic> json) {
    return StockItemUsage(
      recipeId: _text(json['recipeId']) ?? '',
      menuItemId: _text(json['menuItemId']) ?? '',
      menuItemName: _text(json['menuItemName']) ?? '',
      variantId: _text(json['variantId']),
      variantLabel: _text(json['variantLabel']),
      quantityPerUnit: _text(json['quantityPerUnit']) ?? '0',
      baseUnit: InventoryUnit.parse(_text(json['baseUnit']) ?? 'piece'),
    );
  }
}

String? _text(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

class CurrentRecipeCost {
  const CurrentRecipeCost({
    required this.status,
    this.total,
    this.components = const [],
  });
  final String status;
  final String? total;
  final List<CurrentCostComponent> components;
  factory CurrentRecipeCost.fromJson(Map<String, dynamic> json) =>
      CurrentRecipeCost(
        status: json['status'] as String,
        total: json['total'] as String?,
        components: (json['components'] as List? ?? [])
            .map(
              (row) =>
                  CurrentCostComponent.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(),
      );
}

class CurrentCostComponent {
  const CurrentCostComponent({
    required this.name,
    required this.quantity,
    required this.baseUnit,
    this.unitCost,
    this.cost,
  });
  final String name;
  final String quantity;
  final InventoryUnit baseUnit;
  final String? unitCost;
  final String? cost;
  factory CurrentCostComponent.fromJson(Map<String, dynamic> json) =>
      CurrentCostComponent(
        name: json['stockItemName'] as String,
        quantity: json['quantity'] as String,
        baseUnit: InventoryUnit.parse(json['baseUnit'] as String),
        unitCost: json['weightedUnitCost'] as String?,
        cost: json['cost'] as String?,
      );
}
