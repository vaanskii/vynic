DO $$ BEGIN
  IF (SELECT count(*) FROM pos."Venue" WHERE "organizationId"='phase0-backfill' AND "activeOperationalDeviceId" IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'Only the sole active historical Device may be auto-selected';
  END IF;
  IF (SELECT "activeOperationalDeviceId" FROM pos."Venue" WHERE id='phase0-one') IS DISTINCT FROM 'phase0-one-device' THEN
    RAISE EXCEPTION 'Single Device backfill failed';
  END IF;
  IF (SELECT count(*) FROM pos."Device" WHERE "venueId" LIKE 'phase0-%') <> 6 THEN
    RAISE EXCEPTION 'Device identity was removed';
  END IF;
  IF (SELECT count(*) FROM pos."EdgeCommand" WHERE id IN ('phase0-uncertain','phase0-uncertain-pending') AND status='FAILED' AND "resultCode"='primary_selection_outcome_unknown') <> 2 THEN
    RAISE EXCEPTION 'Uncertain old work must be held';
  END IF;
  IF (SELECT status FROM pos."EdgeCommand" WHERE id='phase0-safe-retry') <> 'CLAIMED' THEN
    RAISE EXCEPTION 'Single-primary retry compatibility changed';
  END IF;
END $$;
