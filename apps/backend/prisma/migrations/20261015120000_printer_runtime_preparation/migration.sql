-- Additive PREPARED-only printer request journal. No current Device config,
-- credentials, lifecycle status, legacy authority, or activation state changes.
CREATE TABLE "pos"."DevicePrinterRuntimeRequest" (
    "deviceId" TEXT NOT NULL,
    "requestId" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "actorType" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "inputSha256" TEXT NOT NULL,
    "expectedRevision" INTEGER NOT NULL,
    "outcomeStatus" INTEGER NOT NULL,
    "outcome" JSON NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DevicePrinterRuntimeRequest_pkey" PRIMARY KEY ("deviceId", "requestId"),
    CONSTRAINT "DevicePrinterRuntimeRequest_actor_check" CHECK ("actorType" IN ('CUSTOMER', 'PLATFORM')),
    CONSTRAINT "DevicePrinterRuntimeRequest_sha_check" CHECK ("inputSha256" ~ '^[0-9a-f]{64}$'),
    CONSTRAINT "DevicePrinterRuntimeRequest_expected_check" CHECK ("expectedRevision" >= 0),
    CONSTRAINT "DevicePrinterRuntimeRequest_status_check" CHECK ("outcomeStatus" IN (200, 409)),
    CONSTRAINT "DevicePrinterRuntimeRequest_uuid_check" CHECK (
        "requestId" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        AND "deviceId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        AND "venueId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        AND "actorId" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    ),
    CONSTRAINT "DevicePrinterRuntimeRequest_outcome_check" CHECK (COALESCE(
        json_typeof("outcome") = 'object' AND octet_length("outcome"::text) <= 262144
        AND (("outcomeStatus" = 200
              AND "outcome"->>'version' = '2'
              AND "outcome"->>'deviceId' = "deviceId"
              AND "outcome"->>'venueId' = "venueId"
              AND "outcome"->>'phase' = 'PREPARED'
              AND "outcome"->>'minimumReaderVersion' = '2')
             OR ("outcomeStatus" = 409
                 AND "outcome"->>'statusCode' = '409'
                 AND "outcome"->>'error' = 'Conflict'
                 AND "outcome"->>'code' IN ('PRINTER_REVISION_CONFLICT', 'PRINTER_REVISION_EXHAUSTED'))),
        FALSE
    )),
    CONSTRAINT "DevicePrinterRuntimeRequest_device_fkey" FOREIGN KEY ("deviceId") REFERENCES "pos"."Device"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT "DevicePrinterRuntimeRequest_venue_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX "DevicePrinterRuntimeRequest_venueId_createdAt_idx"
    ON "pos"."DevicePrinterRuntimeRequest"("venueId", "createdAt");

CREATE FUNCTION "pos"."reject_device_printer_runtime_request_mutation"()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Device printer runtime request outcomes are immutable'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER "DevicePrinterRuntimeRequest_immutable"
    BEFORE UPDATE OR DELETE ON "pos"."DevicePrinterRuntimeRequest"
    FOR EACH ROW EXECUTE FUNCTION "pos"."reject_device_printer_runtime_request_mutation"();

CREATE TRIGGER "DevicePrinterRuntimeRequest_no_truncate"
    BEFORE TRUNCATE ON "pos"."DevicePrinterRuntimeRequest"
    FOR EACH STATEMENT EXECUTE FUNCTION "pos"."reject_device_printer_runtime_request_mutation"();
