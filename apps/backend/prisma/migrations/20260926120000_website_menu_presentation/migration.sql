-- Website presentation for existing operational menu identities.
-- No MenuItem row is duplicated: this table only decides whether and how an
-- already-owned item appears on the generic SaaS website.
CREATE TABLE "pos"."MenuItemWebsitePresentation" (
  "menuItemId" TEXT NOT NULL,
  "venueId" TEXT NOT NULL,
  "visibleOnWebsite" BOOLEAN NOT NULL DEFAULT true,
  "displayName" TEXT,
  "description" TEXT,
  "imageUrl" TEXT,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "MenuItemWebsitePresentation_pkey" PRIMARY KEY ("menuItemId")
);
CREATE INDEX "MenuItemWebsitePresentation_venueId_idx"
  ON "pos"."MenuItemWebsitePresentation"("venueId");
-- Removing an item operationally removes its presentation with it, so the
-- website can never render a record whose product no longer exists.
ALTER TABLE "pos"."MenuItemWebsitePresentation"
  ADD CONSTRAINT "MenuItemWebsitePresentation_menuItemId_fkey"
  FOREIGN KEY ("menuItemId") REFERENCES "pos"."MenuItem"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pos"."MenuItemWebsitePresentation"
  ADD CONSTRAINT "MenuItemWebsitePresentation_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
-- Bounded text, and media held as a reference rather than inline bytes.
ALTER TABLE "pos"."MenuItemWebsitePresentation"
  ADD CONSTRAINT "menu_website_presentation_bounded" CHECK (
    ("displayName" IS NULL OR length("displayName") <= 120)
    AND ("description" IS NULL OR length("description") <= 600)
    AND ("imageUrl" IS NULL OR length("imageUrl") <= 2048)
    AND "sortOrder" >= 0 AND "sortOrder" <= 100000
  );
