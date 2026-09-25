ALTER TABLE "pos"."VenueWebsiteConfig" ADD COLUMN "assignedSlug" TEXT;
UPDATE "pos"."VenueWebsiteConfig" SET "assignedSlug" = "slug" WHERE "slug" IS NOT NULL;
-- A pre-upgrade draft may have requested a different address. Preserve its content,
-- restore the assigned published identity, and fence any stale editor revision.
UPDATE "pos"."VenueWebsiteConfig"
SET draft = jsonb_set(draft, '{slug}', to_jsonb(slug)), revision = revision + 1
WHERE slug IS NOT NULL AND draft IS NOT NULL AND draft->>'slug' IS DISTINCT FROM slug;
CREATE UNIQUE INDEX "VenueWebsiteConfig_assignedSlug_key" ON "pos"."VenueWebsiteConfig"("assignedSlug");
CREATE TABLE "pos"."WebsiteHostnameRequest" (
  "id" TEXT PRIMARY KEY, "venueId" TEXT NOT NULL REFERENCES "pos"."Venue"("id") ON DELETE CASCADE,
  "requestedBy" TEXT NOT NULL, "hostname" TEXT NOT NULL, "slug" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING' CHECK ("status" IN ('PENDING','APPROVED','REJECTED')),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "reviewedAt" TIMESTAMP(3), "reviewedBy" TEXT, "reason" TEXT
);
CREATE INDEX "WebsiteHostnameRequest_venueId_status_idx" ON "pos"."WebsiteHostnameRequest"("venueId", "status");
CREATE UNIQUE INDEX "WebsiteHostnameRequest_one_pending" ON "pos"."WebsiteHostnameRequest"("venueId") WHERE "status" = 'PENDING';
