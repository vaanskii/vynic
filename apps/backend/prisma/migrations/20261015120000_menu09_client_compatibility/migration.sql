ALTER TABLE "pos"."Device"
  ADD COLUMN "menuClientReport" JSONB,
  ADD COLUMN "menuClientObservedAt" TIMESTAMP(3),
  ADD COLUMN "lastLegacyMenuSyncAt" TIMESTAMP(3);
ALTER TABLE "pos"."Venue" ADD COLUMN "menuCutover" JSONB;
