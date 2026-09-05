-- CreateTable
CREATE TABLE "pos"."MenuConsumptionRecipe" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "menuItemId" TEXT NOT NULL,
    "variantId" TEXT,
    "variantKey" TEXT NOT NULL,
    "menuItemNameSnapshot" TEXT NOT NULL,
    "variantLabelSnapshot" TEXT,
    "yieldQuantity" DECIMAL(18,3) NOT NULL DEFAULT 1,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "revision" INTEGER NOT NULL DEFAULT 1,
    "createdById" TEXT NOT NULL,
    "createdByName" TEXT NOT NULL,
    "updatedById" TEXT NOT NULL,
    "updatedByName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MenuConsumptionRecipe_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."MenuConsumptionComponent" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "recipeId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "stockItemNameSnapshot" TEXT NOT NULL,
    "quantity" DECIMAL(18,3) NOT NULL,
    "unit" TEXT NOT NULL,
    "baseQuantity" DECIMAL(18,3) NOT NULL,
    "baseUnit" TEXT NOT NULL,
    "baseQuantityPerUnit" DECIMAL(18,6) NOT NULL,
    "sequence" INTEGER NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MenuConsumptionComponent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "MenuConsumptionRecipe_venueId_isActive_idx" ON "pos"."MenuConsumptionRecipe"("venueId", "isActive");

-- CreateIndex
CREATE INDEX "MenuConsumptionRecipe_venueId_menuItemId_idx" ON "pos"."MenuConsumptionRecipe"("venueId", "menuItemId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuConsumptionRecipe_menuItemId_variantKey_key" ON "pos"."MenuConsumptionRecipe"("menuItemId", "variantKey");

-- CreateIndex
CREATE INDEX "MenuConsumptionComponent_venueId_stockItemId_idx" ON "pos"."MenuConsumptionComponent"("venueId", "stockItemId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuConsumptionComponent_recipeId_sequence_key" ON "pos"."MenuConsumptionComponent"("recipeId", "sequence");

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionRecipe" ADD CONSTRAINT "MenuConsumptionRecipe_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionRecipe" ADD CONSTRAINT "MenuConsumptionRecipe_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "pos"."MenuItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionRecipe" ADD CONSTRAINT "MenuConsumptionRecipe_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "pos"."MenuItemVariant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionComponent" ADD CONSTRAINT "MenuConsumptionComponent_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionComponent" ADD CONSTRAINT "MenuConsumptionComponent_recipeId_fkey" FOREIGN KEY ("recipeId") REFERENCES "pos"."MenuConsumptionRecipe"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuConsumptionComponent" ADD CONSTRAINT "MenuConsumptionComponent_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "pos"."StockItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

