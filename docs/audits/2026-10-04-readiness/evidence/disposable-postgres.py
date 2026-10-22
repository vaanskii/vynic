"""Audit-only fresh migration, HTTP isolation and synthetic dump/restore proof.
Creates its own cluster in a new /tmp directory; never uses an existing database.
No production commands, fixtures, credentials, migration edits or dependency installs.
"""
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[4]
BACKEND = REPO / 'apps/backend'
OUT = Path(__file__).resolve().parent
PG = Path('/opt/homebrew/opt/postgresql@17/bin')
ROOT = Path(tempfile.mkdtemp(prefix='vynic-readiness-owned-pg-', dir='/tmp'))
DATA = ROOT / 'data'
PORT = str(random.randrange(54000, 59000))
USER = 'readiness_audit'
DATABASE = 'disposable_sec02_readiness_20261004'
URL = f'postgresql://{USER}@127.0.0.1:{PORT}/{DATABASE}?schema=pos'
env = {**os.environ, 'DATABASE_URL': URL, 'NODE_ENV': 'test', 'SEC02_TEST_DATABASE_URL': URL}
result = {'cluster': str(ROOT), 'scope': 'Fresh synthetic cluster only; no existing data, no media or production key restore', 'steps': []}
started = False

def run(label, cmd, *, data=None):
    r = subprocess.run([str(x) for x in cmd], cwd=BACKEND, env=env, input=data, capture_output=True, text=True)
    (OUT / f'pg-{label}.log').write_text(r.stdout + r.stderr)
    result['steps'].append({'name': label, 'exitCode': r.returncode})
    if r.returncode:
        raise RuntimeError(f'{label} failed; see pg-{label}.log')
    return r.stdout

def sql(database, query):
    return run('query-' + database, [PG/'psql', '-h', '127.0.0.1', '-p', PORT, '-U', USER, '-d', database, '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-c', query])

try:
    run('init', [PG/'initdb', '-D', DATA, '-U', USER, '--auth=trust', '--no-locale', '--encoding=UTF8'])
    run('start', [PG/'pg_ctl', '-D', DATA, '-l', ROOT/'server.log', '-o', f'-h 127.0.0.1 -p {PORT} -k {ROOT}', '-w', 'start'])
    started = True
    run('create', [PG/'createdb', '-h', '127.0.0.1', '-p', PORT, '-U', USER, DATABASE])
    run('migrate', [BACKEND/'node_modules/.bin/prisma', 'migrate', 'deploy'])
    run('migrate-repeat', [BACKEND/'node_modules/.bin/prisma', 'migrate', 'deploy'])
    rows = sql(DATABASE, 'SELECT migration_name,checksum FROM pos._prisma_migrations WHERE finished_at IS NOT NULL ORDER BY migration_name')
    expected = {p.parent.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (BACKEND/'prisma/migrations').glob('*/migration.sql')}
    actual = dict(row.split('|') for row in rows.strip().splitlines())
    assert actual == expected, 'Applied migration hashes differ from repository'
    result['migrationCount'] = len(actual)
    result['allMigrationChecksumsMatch'] = True
    run('http-sec02', ['node', BACKEND/'node_modules/jest/bin/jest.js', '--runInBand', '--cacheDirectory=/tmp/vynic-readiness-jest', '--runTestsByPath', 'src/website/user/guest-booking-ownership.integration.spec.ts', '--json', '--outputFile=' + str(OUT/'postgres-http-tests.json')])
    sql(DATABASE, "CREATE TABLE public.audit_restore_probe(id integer PRIMARY KEY, note text NOT NULL); INSERT INTO public.audit_restore_probe VALUES(1, 'synthetic durable marker');")
    dump = ROOT/'synthetic.dump'
    run('dump', [PG/'pg_dump', '-h','127.0.0.1','-p',PORT,'-U',USER,'-d',DATABASE,'-Fc','-f',dump])
    restored = 'disposable_readiness_restored_20261004'
    run('create-restore', [PG/'createdb','-h','127.0.0.1','-p',PORT,'-U',USER,restored])
    run('restore', [PG/'pg_restore','-h','127.0.0.1','-p',PORT,'-U',USER,'-d',restored,'--no-owner',dump])
    assert sql(restored,'SELECT note FROM public.audit_restore_probe WHERE id=1').strip() == 'synthetic durable marker'
    restored_rows = sql(restored, 'SELECT migration_name,checksum FROM pos._prisma_migrations WHERE finished_at IS NOT NULL ORDER BY migration_name')
    assert rows == restored_rows
    result['restoreMarkerAndMigrationLedgerMatch'] = True
    result['status'] = 'PASS'
except Exception as e:
    result['status'] = 'FAILED_OR_ENV_BLOCKED'
    result['error'] = str(e)
    raise
finally:
    if started:
        run('stop', [PG/'pg_ctl','-D',DATA,'-m','fast','-w','stop'])
        result['ownedClusterStopped'] = True
    (OUT/'postgres-proof.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
