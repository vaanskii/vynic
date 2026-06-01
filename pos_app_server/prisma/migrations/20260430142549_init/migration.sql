/*
  Warnings:

  - A unique constraint covering the columns `[slug,categoryId]` on the table `MenuSubcategory` will be added. If there are existing duplicate values, this will fail.

*/
-- DropForeignKey
ALTER TABLE "MenuItem" DROP CONSTRAINT "MenuItem_subcategoryId_fkey";

-- DropIndex
DROP INDEX "MenuSubcategory_categoryId_idx";

-- DropIndex
DROP INDEX "MenuSubcategory_categoryId_slug_key";

-- AlterTable
ALTER TABLE "MenuItem" ALTER COLUMN "categoryId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "businessDate" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "customerName" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "customerPhone" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "floor" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "pickupTime" TEXT NOT NULL DEFAULT '';

-- CreateTable
CREATE TABLE "MenuItemVariant" (
    "id" TEXT NOT NULL,
    "menuItemId" TEXT NOT NULL,
    "size" DOUBLE PRECISION NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "MenuItemVariant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEventLog" (
    "id" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "deviceType" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEventLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuickOrderDraft" (
    "id" TEXT NOT NULL,
    "draftId" TEXT NOT NULL,
    "displayName" TEXT,
    "subtotal" DOUBLE PRECISION NOT NULL,
    "serviceFeeAmount" DOUBLE PRECISION NOT NULL,
    "total" DOUBLE PRECISION NOT NULL,
    "includeServiceFee" BOOLEAN NOT NULL DEFAULT false,
    "serviceFeeRate" DOUBLE PRECISION NOT NULL DEFAULT 0.1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdBy" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "QuickOrderDraft_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuickOrderDraftItem" (
    "id" TEXT NOT NULL,
    "draftId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "comment" TEXT,

    CONSTRAINT "QuickOrderDraftItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Setting" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Setting_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "MenuItemVariant_menuItemId_idx" ON "MenuItemVariant"("menuItemId");

-- CreateIndex
CREATE INDEX "AuditEventLog_createdAt_idx" ON "AuditEventLog"("createdAt");

-- CreateIndex
CREATE INDEX "AuditEventLog_action_idx" ON "AuditEventLog"("action");

-- CreateIndex
CREATE UNIQUE INDEX "QuickOrderDraft_draftId_key" ON "QuickOrderDraft"("draftId");

-- CreateIndex
CREATE INDEX "QuickOrderDraftItem_draftId_idx" ON "QuickOrderDraftItem"("draftId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuSubcategory_slug_categoryId_key" ON "MenuSubcategory"("slug", "categoryId");

-- AddForeignKey
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_subcategoryId_fkey" FOREIGN KEY ("subcategoryId") REFERENCES "MenuSubcategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItemVariant" ADD CONSTRAINT "MenuItemVariant_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QuickOrderDraftItem" ADD CONSTRAINT "QuickOrderDraftItem_draftId_fkey" FOREIGN KEY ("draftId") REFERENCES "QuickOrderDraft"("id") ON DELETE CASCADE ON UPDATE CASCADE;
