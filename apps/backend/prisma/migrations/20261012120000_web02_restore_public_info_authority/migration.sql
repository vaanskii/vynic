-- WEB-02: restore publication authority over the shared public information
-- that 20261010120000_shared_website_foundation moved, using only the
-- evidence 20261010110000 captured before it ran. Nothing is inferred.
--
-- The live VenuePublicProfile must hold what was published, never an
-- unpublished draft: the published values when a version was published,
-- otherwise nothing. A differing draft stays private in VenuePublicInfoReview
-- (state PENDING) until an explicit decision. Compare-and-set: a profile is
-- corrected only while it is exactly what the foundation wrote (same values,
-- revision 0); anything else is left untouched and stays PENDING for review.
--
-- Where the foundation ran before evidence was kept, there are no
-- PRE_FOUNDATION_SNAPSHOT rows and this migration changes nothing.

-- Published values replace what the foundation copied from the draft.
UPDATE "pos"."VenuePublicProfile" AS p
SET
  "workingHours" = r."publishedInfo"->'workingHours',
  "contactEmail" = r."publishedInfo"->>'contactEmail',
  "mapUrl" = r."publishedInfo"->>'mapUrl',
  "socials" = r."publishedInfo"->'socials',
  "gallery" = r."publishedInfo"->'gallery',
  "updatedAt" = CURRENT_TIMESTAMP
FROM "pos"."VenuePublicInfoReview" AS r
WHERE r."venueId" = p."venueId"
  AND r."source" = 'PRE_FOUNDATION_SNAPSHOT'
  AND r."publishedInfo" IS NOT NULL
  AND p."revision" = 0
  AND jsonb_build_object('workingHours', p."workingHours", 'contactEmail', p."contactEmail",
        'mapUrl', p."mapUrl", 'socials', p."socials", 'gallery', p."gallery") = r."migratedInfo"
  AND r."migratedInfo" <> r."publishedInfo";

-- A never-published draft is not public information: remove the row the
-- foundation created from it, restoring "no public information".
DELETE FROM "pos"."VenuePublicProfile" AS p
USING "pos"."VenuePublicInfoReview" AS r
WHERE r."venueId" = p."venueId"
  AND r."source" = 'PRE_FOUNDATION_SNAPSHOT'
  AND r."publishedInfo" IS NULL
  AND p."revision" = 0
  AND jsonb_build_object('workingHours', p."workingHours", 'contactEmail', p."contactEmail",
        'mapUrl', p."mapUrl", 'socials', p."socials", 'gallery', p."gallery") = r."migratedInfo";

-- A published version whose draft was not a document got no row at all.
INSERT INTO "pos"."VenuePublicProfile"
  ("venueId", "workingHours", "contactEmail", "mapUrl", "socials", "gallery", "updatedAt")
SELECT
  r."venueId",
  r."publishedInfo"->'workingHours',
  r."publishedInfo"->>'contactEmail',
  r."publishedInfo"->>'mapUrl',
  r."publishedInfo"->'socials',
  r."publishedInfo"->'gallery',
  CURRENT_TIMESTAMP
FROM "pos"."VenuePublicInfoReview" AS r
WHERE r."source" = 'PRE_FOUNDATION_SNAPSHOT'
  AND r."publishedInfo" IS NOT NULL
  AND r."migratedInfo" IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM "pos"."VenuePublicProfile" AS p WHERE p."venueId" = r."venueId"
  );

-- No review is needed only when the live row now holds exactly the approved
-- values and there is no differing private draft.
UPDATE "pos"."VenuePublicInfoReview" AS r
SET
  "state" = CASE
    WHEN COALESCE(
           (SELECT jsonb_build_object('workingHours', p."workingHours", 'contactEmail', p."contactEmail",
                     'mapUrl', p."mapUrl", 'socials', p."socials", 'gallery', p."gallery")
              FROM "pos"."VenuePublicProfile" AS p WHERE p."venueId" = r."venueId"),
           '{"workingHours":[],"contactEmail":null,"mapUrl":null,"socials":[],"gallery":[]}'::jsonb)
         = COALESCE(r."publishedInfo",
           '{"workingHours":[],"contactEmail":null,"mapUrl":null,"socials":[],"gallery":[]}'::jsonb)
     AND (r."draftInfo" IS NULL OR r."draftInfo" = COALESCE(r."publishedInfo",
           '{"workingHours":[],"contactEmail":null,"mapUrl":null,"socials":[],"gallery":[]}'::jsonb))
    THEN 'NOT_REQUIRED'::"pos"."PublicInfoReviewState"
    ELSE 'PENDING'::"pos"."PublicInfoReviewState"
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE r."source" = 'PRE_FOUNDATION_SNAPSHOT';
