-- Retain identities and historical recipe/presentation authority; no backfill
-- can recreate recipes or presentation that old writers already deleted.
ALTER TABLE "pos"."MenuCategory" ADD COLUMN "retiredAt" TIMESTAMP(3);
ALTER TABLE "pos"."MenuSubcategory" ADD COLUMN "retiredAt" TIMESTAMP(3);
ALTER TABLE "pos"."MenuItem" ADD COLUMN "retiredAt" TIMESTAMP(3);
ALTER TABLE "pos"."MenuItemVariant" ADD COLUMN "retiredAt" TIMESTAMP(3);

-- An old/destructive writer must fail instead of silently erasing authority.
ALTER TABLE "pos"."MenuConsumptionRecipe" DROP CONSTRAINT "MenuConsumptionRecipe_menuItemId_fkey";
ALTER TABLE "pos"."MenuConsumptionRecipe" ADD CONSTRAINT "MenuConsumptionRecipe_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "pos"."MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."MenuConsumptionRecipe" DROP CONSTRAINT "MenuConsumptionRecipe_variantId_fkey";
ALTER TABLE "pos"."MenuConsumptionRecipe" ADD CONSTRAINT "MenuConsumptionRecipe_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "pos"."MenuItemVariant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."MenuItemWebsitePresentation" DROP CONSTRAINT "MenuItemWebsitePresentation_menuItemId_fkey";
ALTER TABLE "pos"."MenuItemWebsitePresentation" ADD CONSTRAINT "MenuItemWebsitePresentation_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "pos"."MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
