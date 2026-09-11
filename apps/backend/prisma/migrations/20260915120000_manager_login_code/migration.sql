-- Add a public, stable login identity without changing operational records.
ALTER TABLE "pos"."Venue" ADD COLUMN "loginCode" TEXT;
WITH codes AS (
  SELECT "id", row_number() OVER (ORDER BY "id") AS ordinal FROM "pos"."Venue"
)
UPDATE "pos"."Venue" v SET "loginCode" = CASE
  WHEN v."id" = '00000000-0000-4000-8000-000000000002' THEN 'vankisi'
  ELSE 'venue-' || lpad(c.ordinal::text, 12, '0') END
FROM codes c WHERE c."id" = v."id";
ALTER TABLE "pos"."Venue" ALTER COLUMN "loginCode" SET NOT NULL;
ALTER TABLE "pos"."Venue" ALTER COLUMN "loginCode" SET DEFAULT ('venue-' || substr(md5(random()::text), 1, 12));
CREATE UNIQUE INDEX "Venue_loginCode_key" ON "pos"."Venue"("loginCode");
ALTER TABLE "pos"."Venue" ADD CONSTRAINT "Venue_loginCode_format" CHECK ("loginCode" ~ '^[a-z0-9][a-z0-9-]{2,31}$');
