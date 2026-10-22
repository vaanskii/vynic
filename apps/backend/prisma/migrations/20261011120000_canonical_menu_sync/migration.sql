-- Canonical Cloud Menu + local-first POS projection (docs/CANONICAL_MENU_SYNC.md, D030).
-- Additive only: existing rows keep their UUIDs and start at revision 1 with
-- changeSeq 0 (they are part of any full snapshot; catch-up only reports
-- changes made through the canonical protocol). No authority is changed.
-- CreateEnum
CREATE TYPE "pos"."MenuEntityKind" AS ENUM ('CATEGORY', 'SUBCATEGORY', 'ITEM', 'VARIANT');

-- CreateEnum
CREATE TYPE "pos"."MenuMutationActor" AS ENUM ('DEVICE', 'CUSTOMER', 'STAFF', 'PLATFORM', 'SYSTEM');

-- AlterTable
ALTER TABLE "pos"."MenuCategory" ADD COLUMN     "changeSeq" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "revision" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
ALTER TABLE "pos"."MenuItem" ADD COLUMN     "changeSeq" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "revision" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
ALTER TABLE "pos"."MenuItemVariant" ADD COLUMN     "changeSeq" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "revision" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
ALTER TABLE "pos"."MenuSubcategory" ADD COLUMN     "changeSeq" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "revision" INTEGER NOT NULL DEFAULT 1;

-- CreateTable
CREATE TABLE "pos"."MenuCatalogTombstone" (
    "venueId" TEXT NOT NULL,
    "entityType" "pos"."MenuEntityKind" NOT NULL,
    "entityId" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "revision" INTEGER NOT NULL,
    "mutationId" TEXT,
    "deletedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MenuCatalogTombstone_pkey" PRIMARY KEY ("venueId","entityId")
);

-- CreateTable
CREATE TABLE "pos"."MenuCatalogMutation" (
    "venueId" TEXT NOT NULL,
    "mutationId" TEXT NOT NULL,
    "entityType" "pos"."MenuEntityKind" NOT NULL,
    "entityId" TEXT NOT NULL,
    "operation" TEXT NOT NULL,
    "expectedRevision" INTEGER NOT NULL,
    "resultRevision" INTEGER NOT NULL,
    "seq" INTEGER NOT NULL,
    "actorType" "pos"."MenuMutationActor" NOT NULL,
    "actorId" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "changes" JSONB NOT NULL,
    "resolution" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MenuCatalogMutation_pkey" PRIMARY KEY ("venueId","mutationId")
);

-- CreateIndex
CREATE INDEX "MenuCatalogTombstone_venueId_seq_idx" ON "pos"."MenuCatalogTombstone"("venueId", "seq");

-- CreateIndex
CREATE INDEX "MenuCatalogMutation_venueId_entityId_idx" ON "pos"."MenuCatalogMutation"("venueId", "entityId");

-- CreateIndex
CREATE INDEX "MenuCatalogMutation_venueId_createdAt_idx" ON "pos"."MenuCatalogMutation"("venueId", "createdAt");

-- AddForeignKey
ALTER TABLE "pos"."MenuCatalogTombstone" ADD CONSTRAINT "MenuCatalogTombstone_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuCatalogMutation" ADD CONSTRAINT "MenuCatalogMutation_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;
