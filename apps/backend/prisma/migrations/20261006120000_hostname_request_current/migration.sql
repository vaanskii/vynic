-- Additive: the address a Venue had when its owner asked for another one.
-- Earlier requests keep NULL; no hostname or domain row is rewritten.
ALTER TABLE "pos"."WebsiteHostnameRequest" ADD COLUMN "currentHostname" TEXT;
