"""Reproduce the additive migration against real pre-migration pilot rows.
Creates a new disposable database only, never drops or modifies an existing one.
Usage: PG_BIN=/path/to/postgres/bin python3 scripts/prove-onboarding-backfill.py
"""
import os
from pathlib import Path
import subprocess

bin_dir = Path(os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin"))
name = "vynic_owner_backfill_disposable"
connection = ["-h", "127.0.0.1", "-p", "55439", "-d", name]
subprocess.run([str(bin_dir / "createdb"), "-h", "127.0.0.1", "-p", "55439", name], check=True)

def sql(source):
    subprocess.run([str(bin_dir / "psql"), *connection, "-X", "-v", "ON_ERROR_STOP=1"],
                   input=source, text=True, check=True, stdout=subprocess.DEVNULL)

migrations = Path(__file__).resolve().parent.parent / "prisma/migrations"
tip = "20260927120000_organization_owner_invitations"
for migration in sorted(migrations.glob("*/migration.sql")):
    if migration.parent.name < tip:
        sql(migration.read_text())
sql("""
INSERT INTO pos."Organization" ("id","name","updatedAt") VALUES
 ('backfill-org-a','Pilot organization A',now()), ('backfill-org-b','Pilot organization B',now());
INSERT INTO pos."CustomerAccount" ("id","organizationId","email","displayName","passwordHash","updatedAt") VALUES
 ('backfill-owner-a','backfill-org-a','pilot-a@test.invalid','Pilot A','preserve-hash-a',now()),
 ('backfill-owner-b','backfill-org-b','pilot-b@test.invalid','Pilot B','preserve-hash-b',now());
INSERT INTO pos."Venue" ("id","organizationId","name","timezone","currency","updatedAt") VALUES
 ('backfill-venue','backfill-org-a','Pilot restaurant','Asia/Tbilisi','GEL',now());
INSERT INTO pos."VenueWebsiteConfig" ("venueId","mode","status","draft","revision","updatedAt") VALUES
 ('backfill-venue','CUSTOM','DRAFT','{"preserve": true}',3,now());
INSERT INTO pos."OnboardingPolicy" ("id","enabled","trialDays","updatedAt") VALUES ('default',false,21,now());
""")
sql((migrations / tip / "migration.sql").read_text())
sql("""
DO $$
BEGIN
 IF (SELECT count(*) FROM pos."OrganizationMembership") <> 2 THEN RAISE EXCEPTION 'Backfill count'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pos."OrganizationMembership" WHERE "customerAccountId"='backfill-owner-a' AND "organizationId"='backfill-org-a' AND "role"='OWNER') THEN RAISE EXCEPTION 'Ownership changed'; END IF;
 IF (SELECT "passwordHash" FROM pos."CustomerAccount" WHERE "id"='backfill-owner-a') <> 'preserve-hash-a' THEN RAISE EXCEPTION 'Password changed'; END IF;
 IF (SELECT "organizationId" FROM pos."CustomerAccount" WHERE "id"='backfill-owner-b') <> 'backfill-org-b' THEN RAISE EXCEPTION 'Provenance changed'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pos."VenueWebsiteConfig" WHERE "venueId"='backfill-venue' AND mode='CUSTOM' AND revision=3 AND draft='{"preserve":true}'::jsonb) THEN RAISE EXCEPTION 'Website changed'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pos."OnboardingPolicy" WHERE id='default' AND "defaultWebsiteMode"='NONE' AND "trialDays"=21) THEN RAISE EXCEPTION 'Unsafe default'; END IF;
END $$;
""")
print("PASS: pre-migration pilot accounts backfilled; passwords, Organization/Venue ownership, CUSTOM draft and policy preserved")
