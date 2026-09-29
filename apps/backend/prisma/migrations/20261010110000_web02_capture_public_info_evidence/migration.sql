-- WEB-02: keep the publication evidence that the shared website foundation
-- migration (20261010120000) discards. Migration is not publication consent.
--
-- 20261010120000 copies hours, contact email, map URL, socials and gallery
-- from COALESCE(draft, published) into the live VenuePublicProfile and then
-- deletes those keys from both SAAS documents: an unpublished draft goes live
-- and the published values are lost. It is already applied in some databases
-- and is never edited. This migration is ordered just before it. On a
-- database that has not run it yet, it records each Venue's draft and
-- published values (in the VenuePublicProfile column shape) and what the
-- foundation is about to write live, so 20261012120000 can restore the
-- published values and keep the draft private.
--
-- Where the foundation already ran (VenuePublicProfile exists and the keys are
-- gone), Prisma applies this migration late; it then only creates the table
-- and records nothing, because nothing trustworthy is left to record. That
-- history is reported and reviewed explicitly instead
-- (docs/WEB02_SAFE_PUBLICATION_MIGRATION.md).

-- CreateEnum
CREATE TYPE "pos"."PublicInfoReviewSource" AS ENUM ('PRE_FOUNDATION_SNAPSHOT', 'POST_MIGRATION_REVIEW');

-- CreateEnum
CREATE TYPE "pos"."PublicInfoProvenance" AS ENUM ('EMPTY', 'PUBLISHED', 'DRAFT_ONLY', 'DIVERGENT', 'AMBIGUOUS');

-- CreateEnum
CREATE TYPE "pos"."PublicInfoReviewState" AS ENUM ('NOT_REQUIRED', 'PENDING', 'APPLIED', 'DISMISSED', 'CONFIRMED');

-- CreateTable
CREATE TABLE "pos"."VenuePublicInfoReview" (
    "venueId" TEXT NOT NULL,
    "source" "pos"."PublicInfoReviewSource" NOT NULL,
    "provenance" "pos"."PublicInfoProvenance" NOT NULL,
    "state" "pos"."PublicInfoReviewState" NOT NULL DEFAULT 'PENDING',
    "draftInfo" JSONB,
    "publishedInfo" JSONB,
    "migratedInfo" JSONB,
    "draftRevision" INTEGER,
    "publishedRevision" INTEGER,
    "capturedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedAt" TIMESTAMP(3),
    "decidedBy" TEXT,
    "decisionNote" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenuePublicInfoReview_pkey" PRIMARY KEY ("venueId")
);

-- CreateIndex
CREATE INDEX "VenuePublicInfoReview_state_idx" ON "pos"."VenuePublicInfoReview"("state");

-- AddForeignKey
ALTER TABLE "pos"."VenuePublicInfoReview" ADD CONSTRAINT "VenuePublicInfoReview_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

DO $$
BEGIN
  -- The foundation creates VenuePublicProfile: if it exists, the evidence is
  -- already gone and this late application records nothing.
  IF to_regclass('"pos"."VenuePublicProfile"') IS NOT NULL THEN
    RETURN;
  END IF;

  -- `info` normalizes one document exactly as 20261010120000 does per column
  -- (absent list = [], absent/empty text = null); `migrated` is the value the
  -- foundation will write live: COALESCE(draft, published), only if an object.
  INSERT INTO "pos"."VenuePublicInfoReview"
    ("venueId", "source", "provenance", "state", "draftInfo", "publishedInfo",
     "migratedInfo", "draftRevision", "publishedRevision", "updatedAt")
  SELECT
    e."venueId",
    'PRE_FOUNDATION_SNAPSHOT',
    CASE
      WHEN COALESCE(e.d, e.empty) = e.empty AND COALESCE(e.p, e.empty) = e.empty
        THEN 'EMPTY'
      WHEN e.d IS NULL OR e.d = COALESCE(e.p, e.empty) THEN 'PUBLISHED'
      WHEN COALESCE(e.p, e.empty) = e.empty THEN 'DRAFT_ONLY'
      ELSE 'DIVERGENT'
    END::"pos"."PublicInfoProvenance",
    'PENDING',
    e.d,
    e.p,
    e.m,
    e."revision",
    e."publishedRevision",
    CURRENT_TIMESTAMP
  FROM (
    SELECT
      c."venueId",
      c."revision",
      c."publishedRevision",
      '{"workingHours":[],"contactEmail":null,"mapUrl":null,"socials":[],"gallery":[]}'::jsonb AS empty,
      CASE WHEN jsonb_typeof(c."draft") = 'object' THEN jsonb_build_object(
        'workingHours', COALESCE(c."draft"->'workingHours', '[]'::jsonb),
        'contactEmail', NULLIF(c."draft"->>'contactEmail', ''),
        'mapUrl', NULLIF(c."draft"->>'mapUrl', ''),
        'socials', COALESCE(c."draft"->'socials', '[]'::jsonb),
        'gallery', COALESCE(c."draft"->'gallery', '[]'::jsonb)) END AS d,
      CASE WHEN jsonb_typeof(c."published") = 'object' THEN jsonb_build_object(
        'workingHours', COALESCE(c."published"->'workingHours', '[]'::jsonb),
        'contactEmail', NULLIF(c."published"->>'contactEmail', ''),
        'mapUrl', NULLIF(c."published"->>'mapUrl', ''),
        'socials', COALESCE(c."published"->'socials', '[]'::jsonb),
        'gallery', COALESCE(c."published"->'gallery', '[]'::jsonb)) END AS p,
      CASE WHEN jsonb_typeof(COALESCE(c."draft", c."published")) = 'object' THEN jsonb_build_object(
        'workingHours', COALESCE(COALESCE(c."draft", c."published")->'workingHours', '[]'::jsonb),
        'contactEmail', NULLIF(COALESCE(c."draft", c."published")->>'contactEmail', ''),
        'mapUrl', NULLIF(COALESCE(c."draft", c."published")->>'mapUrl', ''),
        'socials', COALESCE(COALESCE(c."draft", c."published")->'socials', '[]'::jsonb),
        'gallery', COALESCE(COALESCE(c."draft", c."published")->'gallery', '[]'::jsonb)) END AS m
    FROM "pos"."VenueWebsiteConfig" c
    WHERE jsonb_typeof(c."draft") = 'object' OR jsonb_typeof(c."published") = 'object'
  ) e;
END $$;
