-- AlterTable
ALTER TABLE "MenuItem" ADD COLUMN     "subcategoryId" TEXT;

-- CreateTable
CREATE TABLE "MenuSubcategory" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "nameKa" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MenuSubcategory_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "MenuSubcategory_categoryId_idx" ON "MenuSubcategory"("categoryId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuSubcategory_categoryId_slug_key" ON "MenuSubcategory"("categoryId", "slug");

-- CreateIndex
CREATE INDEX "MenuItem_subcategoryId_idx" ON "MenuItem"("subcategoryId");

-- AddForeignKey
ALTER TABLE "MenuSubcategory" ADD CONSTRAINT "MenuSubcategory_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "MenuCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_subcategoryId_fkey" FOREIGN KEY ("subcategoryId") REFERENCES "MenuSubcategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;
