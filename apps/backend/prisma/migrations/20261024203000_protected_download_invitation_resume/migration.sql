ALTER TABLE "pos"."OwnerInvitation" ADD COLUMN "recoveryRequestedAt" TIMESTAMP(3);
CREATE TABLE "pos"."InvitationResumeSession" (
  "sessionHash" TEXT PRIMARY KEY, "invitationId" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "InvitationResumeSession_invitationId_idx" ON "pos"."InvitationResumeSession"("invitationId");
CREATE INDEX "InvitationResumeSession_expiresAt_idx" ON "pos"."InvitationResumeSession"("expiresAt");
CREATE TABLE "pos"."InstallerDownloadGrant" (
  "id" TEXT PRIMARY KEY, "tokenHash" TEXT NOT NULL UNIQUE,
  "artifactId" TEXT NOT NULL, "artifactBytes" INTEGER NOT NULL, "artifactSha256" TEXT NOT NULL,
  "customerAccountId" TEXT, "platformUserId" TEXT, "venueId" TEXT,
  "expiresAt" TIMESTAMP(3) NOT NULL, "revokedAt" TIMESTAMP(3),
  "requestCount" INTEGER NOT NULL DEFAULT 0, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "InstallerDownloadGrant_single_issuer" CHECK (("customerAccountId" IS NULL) <> ("platformUserId" IS NULL)),
  CONSTRAINT "InstallerDownloadGrant_customer_venue" CHECK ("customerAccountId" IS NULL OR "venueId" IS NOT NULL)
);
CREATE INDEX "InstallerDownloadGrant_customerAccountId_createdAt_idx" ON "pos"."InstallerDownloadGrant"("customerAccountId", "createdAt");
CREATE INDEX "InstallerDownloadGrant_platformUserId_createdAt_idx" ON "pos"."InstallerDownloadGrant"("platformUserId", "createdAt");
CREATE TABLE "pos"."SecurityAdmission" (
  "key" TEXT PRIMARY KEY, "window" BIGINT NOT NULL, "count" INTEGER NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "SecurityAdmission_updatedAt_idx" ON "pos"."SecurityAdmission"("updatedAt");
