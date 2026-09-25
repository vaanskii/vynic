-- 20261005120000 declared the Venue reference inline, which gave it
-- ON UPDATE NO ACTION; schema.prisma (like every other Venue relation)
-- expects ON UPDATE CASCADE. Recreate the same-named constraint to match.
-- Delete behavior (CASCADE) and all rows are unchanged.
ALTER TABLE "pos"."WebsiteHostnameRequest" DROP CONSTRAINT "WebsiteHostnameRequest_venueId_fkey";
ALTER TABLE "pos"."WebsiteHostnameRequest" ADD CONSTRAINT "WebsiteHostnameRequest_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;
