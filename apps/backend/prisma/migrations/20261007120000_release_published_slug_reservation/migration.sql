-- The published-name column is a mirror of the last publication, not a
-- reservation: `assignedSlug` (unique) and "VenueDomain"."hostname" (unique)
-- reserve SaaS names. Keeping it unique let a lapsed Venue's retained
-- publication block another Venue from a genuinely released name.
-- No rows are changed.
DROP INDEX "pos"."VenueWebsiteConfig_slug_key";
