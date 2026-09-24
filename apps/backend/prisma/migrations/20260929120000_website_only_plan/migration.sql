-- Add an independently sellable product without reassigning existing Venues.
INSERT INTO "pos"."Plan" ("id", "key", "name", "status", "updatedAt")
VALUES ('00000000-0000-4000-8000-000000000024', 'WEBSITE_ONLY', 'Website only', 'ACTIVE', CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;
INSERT INTO "pos"."PlanFeature" ("planId", "featureId")
SELECT p."id", f."id" FROM "pos"."Plan" p CROSS JOIN "pos"."Feature" f
WHERE p."key" = 'WEBSITE_ONLY' AND f."key" = 'WEBSITE'
ON CONFLICT DO NOTHING;
