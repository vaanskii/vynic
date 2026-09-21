-- Disposable database only, after all migrations preceding Phase 0.
INSERT INTO pos."Organization" (id, name, "updatedAt") VALUES ('phase0-backfill', 'Phase 0 migration fixture', now());
INSERT INTO pos."Venue" (id, "organizationId", name, timezone, currency, "updatedAt")
SELECT 'phase0-' || name, 'phase0-backfill', name, 'Asia/Tbilisi', 'GEL', now()
FROM unnest(ARRAY['zero','one','disabled','multiple','historical']) name;
INSERT INTO pos."Device" (id,"venueId","installationId","displayName",platform,"credentialHash",status,"updatedAt") VALUES
('phase0-one-device','phase0-one','phase0-install-1','Single POS','WINDOWS','fixture','ACTIVE',now()),
('phase0-disabled-device','phase0-disabled','phase0-install-2','Disabled POS','WINDOWS','fixture','DISABLED',now()),
('phase0-multi-a','phase0-multiple','phase0-install-3','Multiple A','WINDOWS','fixture','ACTIVE',now()),
('phase0-multi-b','phase0-multiple','phase0-install-4','Multiple B','WINDOWS','fixture','ACTIVE',now()),
('phase0-history-a','phase0-historical','phase0-install-5','History A','WINDOWS','fixture','ACTIVE',now()),
('phase0-history-b','phase0-historical','phase0-install-6','History B','WINDOWS','fixture','REVOKED',now());
INSERT INTO pos."EdgeCommand" (id,"venueId",type,payload,"idempotencyKey",status,"attemptCount","claimedByDeviceId","updatedAt") VALUES
('phase0-uncertain','phase0-multiple','ORDER_CANCEL','{}','phase0-uncertain','CLAIMED',1,'phase0-multi-a',now()),
('phase0-safe-retry','phase0-one','ORDER_CANCEL','{}','phase0-safe-retry','CLAIMED',1,'phase0-one-device',now()),
('phase0-uncertain-pending','phase0-multiple','ORDER_CANCEL','{}','phase0-uncertain-pending','PENDING',1,NULL,now());
