-- Separate transaction: PostgreSQL enum values must commit before use.
ALTER TABLE "pos"."VenueSubscription" ALTER COLUMN "status" SET DEFAULT 'NO_PLAN';
