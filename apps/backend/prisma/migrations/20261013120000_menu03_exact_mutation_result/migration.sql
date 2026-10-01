-- Existing outcomes cannot be backfilled from the mutable catalog: preserve NULL.
-- New writers record the server-serialized response in the catalog transaction.
ALTER TABLE "pos"."MenuCatalogMutation" ADD COLUMN "acceptedResult" JSONB;
