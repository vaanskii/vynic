-- Stable POS-owned identity remains separate from Cloud primary keys so
-- existing website/public identifiers stay unchanged.
ALTER TABLE "pos"."MenuCategory"
ADD COLUMN "posMenuCategoryId" TEXT;

ALTER TABLE "pos"."MenuSubcategory"
ADD COLUMN "posMenuSubcategoryId" TEXT;

ALTER TABLE "pos"."MenuItemVariant"
ADD COLUMN "posMenuVariantId" TEXT;

ALTER TABLE "pos"."OrderItem"
ADD COLUMN "menuItemId" TEXT,
ADD COLUMN "variantId" TEXT;

CREATE UNIQUE INDEX "MenuCategory_venueId_posMenuCategoryId_key"
ON "pos"."MenuCategory"("venueId", "posMenuCategoryId");

CREATE UNIQUE INDEX "MenuSubcategory_categoryId_posMenuSubcategoryId_key"
ON "pos"."MenuSubcategory"("categoryId", "posMenuSubcategoryId");

CREATE UNIQUE INDEX "MenuItemVariant_menuItemId_posMenuVariantId_key"
ON "pos"."MenuItemVariant"("menuItemId", "posMenuVariantId");
