-- No Device identity or historical operational data is removed.
ALTER TABLE "pos"."Venue" ADD COLUMN "activeOperationalDeviceId" TEXT;
CREATE UNIQUE INDEX "Venue_activeOperationalDeviceId_key" ON "pos"."Venue"("activeOperationalDeviceId");
ALTER TABLE "pos"."Venue" ADD CONSTRAINT "Venue_activeOperationalDeviceId_fkey"
  FOREIGN KEY ("activeOperationalDeviceId") REFERENCES "pos"."Device"("id") ON DELETE SET NULL ON UPDATE CASCADE;
-- Exactly one historical Device AND it is ACTIVE. Multiple Devices, including
-- disabled/revoked history, require an explicit operator selection.
UPDATE "pos"."Venue" v SET "activeOperationalDeviceId" = d.id
FROM "pos"."Device" d
WHERE d."venueId" = v.id AND d.status = 'ACTIVE'
  AND (SELECT count(*) FROM "pos"."Device" all_devices WHERE all_devices."venueId" = v.id) = 1;

-- Previously delivered work from an unselected installation has an uncertain
-- local outcome. Hold it for reconciliation instead of moving it to another Hive.
UPDATE "pos"."EdgeCommand" c SET status = 'FAILED',
  "resultCode" = 'primary_selection_outcome_unknown',
  "resultDetail" = 'Reconcile the previous POS journal before issuing new work.',
  "acknowledgedAt" = CURRENT_TIMESTAMP, "claimExpiresAt" = NULL
FROM "pos"."Venue" v
WHERE c."venueId" = v.id AND c.status IN ('CLAIMED', 'PENDING')
  AND c."attemptCount" > 0
  AND (c."deviceId" IS NULL OR c.type <> 'NOOP')
  AND (c."claimedByDeviceId" IS NULL OR c."claimedByDeviceId" IS DISTINCT FROM v."activeOperationalDeviceId");
