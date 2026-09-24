-- Non-fiscal close stops being a default plan grant.
--
-- 20260920120000_non_fiscal_close_feature attached it to every plan holding
-- POS, which made it something operators could only take away. It is a
-- capability to sell, not a baseline, so the plan grants go and the Feature
-- row stays: a Venue is given it through VenueFeatureOverride (ENABLED).
-- Venues already holding an explicit override keep it, and historical
-- non-fiscal records are untouched.
DELETE FROM "pos"."PlanFeature" pf
USING "pos"."Feature" f
WHERE pf."featureId" = f."id" AND f."key" = 'NON_FISCAL_CLOSE';
