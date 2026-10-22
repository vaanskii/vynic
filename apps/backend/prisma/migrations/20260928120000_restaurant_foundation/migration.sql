CREATE TYPE "pos"."MenuAuthority" AS ENUM ('POS', 'CLOUD');
ALTER TABLE "pos"."Venue" ADD COLUMN "menuAuthority" "pos"."MenuAuthority" NOT NULL DEFAULT 'POS', ADD COLUMN "catalogRevision" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "pos"."MenuItem" ADD COLUMN "enabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "pos"."Device" ADD COLUMN "foundationBootstrap" JSONB;
