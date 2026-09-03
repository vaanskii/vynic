-- Preserve POS menu ordering (category / subcategory / item index from sync payload)
ALTER TABLE "pos"."MenuCategory" ADD COLUMN IF NOT EXISTS "sortOrder" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "pos"."MenuSubcategory" ADD COLUMN IF NOT EXISTS "sortOrder" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "pos"."MenuItem" ADD COLUMN IF NOT EXISTS "sortOrder" INTEGER NOT NULL DEFAULT 0;
