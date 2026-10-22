CREATE TYPE "pos"."WebsitePublicationStatus" AS ENUM ('DRAFT', 'PUBLISHED');
ALTER TABLE "pos"."VenueWebsiteConfig"
  ADD COLUMN "status" "pos"."WebsitePublicationStatus" NOT NULL DEFAULT 'DRAFT',
  ADD COLUMN "slug" TEXT,
  ADD COLUMN "draft" JSONB,
  ADD COLUMN "revision" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "published" JSONB,
  ADD COLUMN "publishedRevision" INTEGER,
  ADD COLUMN "publishedAt" TIMESTAMP(3);
CREATE UNIQUE INDEX "VenueWebsiteConfig_slug_key" ON "pos"."VenueWebsiteConfig"("slug");
ALTER TABLE "pos"."VenueWebsiteConfig" ADD CONSTRAINT "website_publication_consistent" CHECK (
  "revision" >= 0 AND (
    ("status" = 'DRAFT' AND "published" IS NULL AND "publishedRevision" IS NULL AND "publishedAt" IS NULL AND "slug" IS NULL)
    OR ("status" = 'PUBLISHED' AND "published" IS NOT NULL AND "publishedRevision" > 0 AND "publishedRevision" <= "revision" AND "publishedAt" IS NOT NULL AND "slug" IS NOT NULL)
  )
);
