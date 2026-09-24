#!/usr/bin/env python3
"""Replay the real upgrade on an isolated cluster; never accepts a database URL."""
from pathlib import Path
import subprocess
import uuid

name = 'vynic_commercial_upgrade_' + uuid.uuid4().hex[:10]
connection = ['-h', '127.0.0.1', '-p', '55437']
root = Path(__file__).resolve().parents[1]
def sql(text=None, file=None):
    args = ['psql', *connection, '-d', name, '-X', '-v', 'ON_ERROR_STOP=1', '-At']
    result = subprocess.run(args + (['-f', str(file)] if file else ['-c', text]), text=True, capture_output=True, check=True)
    return result.stdout.strip()
subprocess.run(['createdb', *connection, name], check=True)
try:
    migrations = sorted((root / 'prisma/migrations').glob('*/migration.sql'))
    boundary = '20261002120000_remove_non_fiscal_close_from_plans'
    for migration in migrations:
        if migration.parent.name >= boundary: break
        sql(file=migration)
    sql('''
    INSERT INTO pos."Organization" (id,name,"updatedAt") VALUES ('upgrade-org','Upgrade',now());
    INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,"updatedAt") VALUES
      ('upgrade-active','upgrade-org','Active','Asia/Tbilisi','GEL',now()),
      ('upgrade-trial','upgrade-org','Trial','Asia/Tbilisi','GEL',now()),
      ('upgrade-legacy','upgrade-org','Legacy','Asia/Tbilisi','GEL',now());
    INSERT INTO pos."VenueSubscription" ("venueId",status,"trialEndsAt","updatedAt") VALUES
      ('upgrade-active','ACTIVE',NULL,now()),('upgrade-trial','TRIAL',now()-interval '1 day',now());
    INSERT INTO pos."VenuePlanAssignment" ("venueId","planId","updatedAt")
      SELECT v.id,p.id,now() FROM pos."Venue" v CROSS JOIN pos."Plan" p WHERE v.id LIKE 'upgrade-%' AND p.key='POS_WEBSITE_MANAGER';
    INSERT INTO pos."VenueFeatureOverride" ("venueId","featureId",effect,"updatedAt")
      SELECT 'upgrade-active',id,'ENABLED',now() FROM pos."Feature" WHERE key='NON_FISCAL_CLOSE';
    INSERT INTO pos."VenueDomain" (id,"venueId",hostname,"updatedAt") VALUES ('upgrade-domain','upgrade-active','upgrade.test',now());
    INSERT INTO pos."CustomerAccount" (id,email,"displayName","passwordHash","updatedAt") VALUES ('upgrade-owner','upgrade@test.invalid','Owner','unchanged-hash',now());
    INSERT INTO pos."OrganizationMembership" ("customerAccountId","organizationId") VALUES ('upgrade-owner','upgrade-org');
    ''')
    for migration in migrations:
        if migration.parent.name >= boundary: sql(file=migration)
    assert sql('SELECT "legacyCommercialAccess" FROM pos."Venue" WHERE id=\'upgrade-legacy\'') == 't'
    assert sql('SELECT count(*) FROM pos."Venue" WHERE id IN (\'upgrade-active\',\'upgrade-trial\') AND "legacyCommercialAccess"') == '0'
    assert sql('SELECT status FROM pos."VenueSubscription" WHERE "venueId"=\'upgrade-active\'') == 'ACTIVE'
    assert sql('SELECT status FROM pos."VenueSubscription" WHERE "venueId"=\'upgrade-trial\'') == 'TRIAL'
    assert sql('SELECT count(*) FROM pos."VenuePlanAssignment" WHERE "venueId" LIKE \'upgrade-%\' AND "agreedPriceMinor" IS NULL') == '3'
    assert sql('SELECT count(*) FROM pos."PlanFeature" pf JOIN pos."Feature" f ON f.id=pf."featureId" WHERE f.key=\'NON_FISCAL_CLOSE\'') == '0'
    assert sql('SELECT count(*) FROM pos."VenueFeatureOverride" WHERE "venueId"=\'upgrade-active\' AND effect=\'ENABLED\'') == '1'
    assert sql('SELECT hostname FROM pos."VenueDomain" WHERE id=\'upgrade-domain\'') == 'upgrade.test'
    assert sql('SELECT count(*) FROM pos."OrganizationMembership" WHERE "customerAccountId"=\'upgrade-owner\'') == '1'
    assert sql('SELECT "passwordHash" FROM pos."CustomerAccount" WHERE id=\'upgrade-owner\'') == 'unchanged-hash'
    sql('INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,"updatedAt") VALUES (\'upgrade-new\',\'upgrade-org\',\'New\',\'Asia/Tbilisi\',\'GEL\',now())')
    assert sql('SELECT "legacyCommercialAccess" OR "cloudMenuEditingEnabled" FROM pos."Venue" WHERE id=\'upgrade-new\'') == 'f'
    sql('INSERT INTO pos."VenueSubscription" ("venueId","updatedAt") VALUES (\'upgrade-new\',now())')
    assert sql('SELECT status FROM pos."VenueSubscription" WHERE "venueId"=\'upgrade-new\'') == 'NO_PLAN'
    print('PASS: real migration upgrade preserves active/trial/legacy assignments, domains, owners, explicit policy; new defaults deny access.')
finally:
    subprocess.run(['dropdb', *connection, name], check=True)
