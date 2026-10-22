#!/usr/bin/env python3
"""Verify additive lifecycle upgrade on a disposable loopback cluster only."""
from pathlib import Path
import subprocess
import uuid
root = Path(__file__).resolve().parents[1]
name = 'vynic_subscription_upgrade_' + uuid.uuid4().hex[:10]
connection = ['-h', '127.0.0.1', '-p', '55437']
def sql(query=None, file=None):
    return subprocess.check_output(['psql', *connection, '-d', name, '-X', '-v', 'ON_ERROR_STOP=1', '-At', *(['-f', str(file)] if file else ['-c', query])], text=True).strip()
subprocess.run(['createdb', *connection, name], check=True)
try:
    migrations = sorted((root / 'prisma/migrations').glob('*/migration.sql'))
    for migration in migrations:
        if migration.parent.name == '20261004120000_subscription_lifecycle': break
        sql(file=migration)
    sql('''INSERT INTO pos."Organization" (id,name,"updatedAt") VALUES ('org','Historical',now());
    INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,"updatedAt") VALUES
    ('active','org','Active','Asia/Tbilisi','GEL',now()), ('trial','org','Trial','Asia/Tbilisi','GEL',now()), ('missing','org','Missing','Asia/Tbilisi','GEL',now());
    INSERT INTO pos."VenueSubscription" ("venueId",status,"trialEndsAt","currentPeriodEndsAt","updatedAt") VALUES
    ('active','ACTIVE',NULL,'2026-10-25',now()),('trial','TRIAL','2026-10-08',NULL,now());
    INSERT INTO pos."VenuePlanAssignment" ("venueId","planId","agreedPriceMinor","agreedCurrency","agreedBillingPeriod","updatedAt") SELECT 'active',id,5000,'GEL','MONTH',now() FROM pos."Plan" WHERE key='WEBSITE_ONLY';
    INSERT INTO pos."VenuePlanAssignment" ("venueId","planId","updatedAt") SELECT 'trial',id,now() FROM pos."Plan" WHERE key='WEBSITE_ONLY';''')
    sql(file=root / 'prisma/migrations/20261004120000_subscription_lifecycle/migration.sql')
    assert sql('SELECT status FROM pos."VenueSubscription" WHERE "venueId"=\'active\'') == 'ACTIVE'
    assert sql('SELECT "agreedPriceMinor" FROM pos."VenuePlanAssignment" WHERE "venueId"=\'active\'') == '5000'
    assert sql('SELECT count(*) FROM pos."VenuePlanAssignment" WHERE "venueId"=\'trial\' AND "agreedPriceMinor" IS NULL') == '1'
    assert sql('SELECT count(*) FROM pos."VenueSubscription" WHERE "venueId" IN (\'active\', \'trial\') AND NOT "billingManaged" AND "currentPeriodStart" IS NULL AND "billingAnchorAt" IS NULL AND NOT "cancelAtPeriodEnd" AND "pendingPlanId" IS NULL') == '2'
    assert sql('SELECT count(*) FROM pos."VenueSubscription" WHERE "venueId"=\'missing\'') == '0'
    assert sql('SELECT "currentPeriodEndsAt"::date FROM pos."VenueSubscription" WHERE "venueId"=\'active\'') == '2026-10-25'
    assert sql('SELECT "trialEndsAt"::date FROM pos."VenueSubscription" WHERE "venueId"=\'trial\'') == '2026-10-08'
    print('PASS: existing status, dated terms, known/unknown prices and missing rows preserved; no invented billing anchors.')
finally:
    subprocess.run(['dropdb', *connection, name], check=True)
