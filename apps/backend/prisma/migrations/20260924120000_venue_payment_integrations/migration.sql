CREATE TABLE "pos"."PaymentIntegration" (
  "id" TEXT PRIMARY KEY,
  "venueId" TEXT NOT NULL REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT,
  "provider" TEXT NOT NULL CHECK ("provider" = 'BOG'),
  "revision" INTEGER NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "encryptedConfig" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE ("venueId", "provider", "revision"),
  UNIQUE ("id", "venueId")
);
CREATE UNIQUE INDEX "PaymentIntegration_one_enabled" ON "pos"."PaymentIntegration" ("venueId", "provider") WHERE "enabled";
ALTER TABLE "website"."reservations" ADD COLUMN "paymentIntegrationId" TEXT;
ALTER TABLE "website"."reservations" ADD CONSTRAINT "reservations_paymentIntegrationId_venueId_fkey"
  FOREIGN KEY ("paymentIntegrationId", "venueId") REFERENCES "pos"."PaymentIntegration"("id", "venueId") ON DELETE RESTRICT;
INSERT INTO "pos"."Feature" ("id", "key", "name", "updatedAt") VALUES
 ('feature-online-payments', 'ONLINE_PAYMENTS', 'Online payments', CURRENT_TIMESTAMP)
 ON CONFLICT ("key") DO NOTHING;
