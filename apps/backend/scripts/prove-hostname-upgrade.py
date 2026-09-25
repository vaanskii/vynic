#!/usr/bin/env python3
"""Apply every migration and verify published identity survives the additive upgrade."""
from pathlib import Path
import subprocess
import uuid
root = Path(__file__).resolve().parents[1]
name = 'vynic_hostname_upgrade_' + uuid.uuid4().hex[:10]
connection = ['-h', '127.0.0.1', '-p', '55447']
def sql(query=None, file=None):
    return subprocess.check_output(['psql', *connection, '-d', name, '-X', '-v', 'ON_ERROR_STOP=1', '-At', *(['-f', str(file)] if file else ['-c', query])], text=True).strip()
subprocess.run(['createdb', *connection, name], check=True)
try:
    tip = root / 'prisma/migrations/20261005120000_website_hostname_requests/migration.sql'
    for migration in sorted((root / 'prisma/migrations').glob('*/migration.sql')):
        if migration != tip:
            sql(file=migration)
    sql('''INSERT INTO pos."Organization" (id,name,"updatedAt") VALUES ('hostname-upgrade-org','Upgrade',now());
    INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,"updatedAt") VALUES ('hostname-upgrade','hostname-upgrade-org','Changed Display Name','Asia/Tbilisi','GEL',now());
    INSERT INTO pos."VenueWebsiteConfig" ("venueId",mode,status,slug,draft,revision,published,"publishedRevision","publishedAt","updatedAt") VALUES ('hostname-upgrade','SAAS','PUBLISHED','existing-address','{"slug":"unapproved-draft","heroTitle":"Retain me"}',1,'{"slug":"existing-address"}',1,now(),now());''')
    sql(file=tip)
    assert sql('SELECT draft->>\'slug\' || \':\' || (draft->>\'heroTitle\') || \':\' || revision::text FROM pos."VenueWebsiteConfig" WHERE "venueId"=\'hostname-upgrade\'') == 'existing-address:Retain me:2'
    assert sql('''SELECT "assignedSlug" || ':' || slug || ':' || status::text FROM pos."VenueWebsiteConfig" WHERE "venueId"='hostname-upgrade' ''') == 'existing-address:existing-address:PUBLISHED'
    sql('''INSERT INTO pos."WebsiteHostnameRequest" (id,"venueId","requestedBy",hostname,slug) VALUES ('pending-1','hostname-upgrade','fixture','desired.example','desired');''')
    result = subprocess.run(['psql', *connection, '-d', name, '-X', '-v', 'ON_ERROR_STOP=1', '-c', '''INSERT INTO pos."WebsiteHostnameRequest" (id,"venueId","requestedBy",hostname,slug) VALUES ('pending-2','hostname-upgrade','fixture','other.example','other')'''], capture_output=True, text=True)
    assert result.returncode != 0 and 'WebsiteHostnameRequest_one_pending' in result.stderr
    print('PASS: published hostname preserved; publication constraint retained; second pending row rejected by PostgreSQL.')
finally:
    subprocess.run(['dropdb', *connection, name], check=True)
