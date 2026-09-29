#!/usr/bin/env python3
"""WEB-02 real PostgreSQL upgrade proof (docs/WEB02_SAFE_PUBLICATION_MIGRATION.md).

Builds pre-foundation fixtures (published only, draft only, divergent, empty;
SAAS, CUSTOM, entitlement withheld) on the pre-`20261010120000` schema with the
repository's own migrations, backs them up, and proves on separate databases:

  original  backup restore -> original 60-migration chain  (defect reproduced)
  upgrade   backup restore -> current chain                (fresh-restore path)
  seed      fixture database upgraded in place              (backup -> upgrade)
  posthoc   backup restore -> original chain -> current chain (already migrated)
  fresh     empty database -> current chain                 (fresh install)

Only databases named disposable_web02_<tag>_* that were absent before this run
are created, and only those are dropped. Never point it at a normal database.

  PGHOST=127.0.0.1 PGPORT=... PGUSER=... \\
    python3 scripts/prove-web02-upgrade.py --tag <8 hex> --proof-dir <dir> [--keep]
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parents[1]
MIGRATIONS = BACKEND / 'prisma' / 'migrations'
WEB02 = ['20261010110000_web02_capture_public_info_evidence',
         '20261012120000_web02_restore_public_info_authority']
FOUNDATION = '20261010120000_shared_website_foundation'
PRISMA = str(BACKEND / 'node_modules' / '.bin' / 'prisma')

args = argparse.ArgumentParser()
args.add_argument('--tag', required=True)
args.add_argument('--proof-dir', required=True)
args.add_argument('--keep', action='store_true')
opts = args.parse_args()
if not re.fullmatch(r'[0-9a-f]{8}', opts.tag):
    sys.exit('--tag must be 8 lowercase hex characters')
host = os.environ.get('PGHOST', '127.0.0.1')
port = os.environ['PGPORT']
user = os.environ['PGUSER']
if host != '127.0.0.1':
    sys.exit('Only a loopback PostgreSQL is permitted')
proof = Path(opts.proof_dir)
proof.mkdir(parents=True, exist_ok=True)
conn = ['-h', host, '-p', port, '-U', user]
summary = {'tag': opts.tag, 'started_at': datetime.now(timezone.utc).isoformat(),
           'databases': [], 'steps': []}
created = []


def name(purpose):
    return f'disposable_web02_{opts.tag}_{purpose}'


def url(db):
    return f'postgresql://{user}@{host}:{port}/{db}'


def run(cmd, env=None, cwd=BACKEND, check=True, log=None):
    result = subprocess.run(cmd, cwd=cwd, env={**os.environ, **(env or {})},
                            capture_output=True, text=True)
    if log:
        (proof / log).write_text(result.stdout + result.stderr)
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(f'failed: {" ".join(cmd[:4])} ...')
    return result


def sql(db, query):
    return run(['psql', *conn, '-d', db, '-X', '-v', 'ON_ERROR_STOP=1', '-At',
                '-c', query]).stdout.strip()


def exists(db):
    return sql('postgres', f"SELECT count(*) FROM pg_database WHERE datname='{db}'") != '0'


def create(purpose):
    db = name(purpose)
    if exists(db):
        raise SystemExit(f'{db} already exists; refusing to reuse it')
    run(['createdb', *conn, db])
    created.append(db)
    summary['databases'].append({'name': db, 'absent_before': True, 'created': True})
    return db


def step(label, **data):
    summary['steps'].append({'step': label, **data})
    print(f'[web02] {label}', flush=True)


def chain(label, names):
    root = Path(tempfile.mkdtemp(prefix=f'web02-{label}-'))
    (root / 'prisma' / 'migrations').mkdir(parents=True)
    shutil.copy(BACKEND / 'prisma' / 'schema.prisma', root / 'prisma')
    shutil.copy(MIGRATIONS / 'migration_lock.toml', root / 'prisma' / 'migrations')
    for m in names:
        shutil.copytree(MIGRATIONS / m, root / 'prisma' / 'migrations' / m)
    return root


def deploy(db, root=None, log=None):
    schema = (root or BACKEND) / 'prisma' / 'schema.prisma'
    run([PRISMA, 'migrate', 'deploy', '--schema', str(schema)],
        env={'DATABASE_URL': url(db)}, cwd=root or BACKEND, log=log)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checksums(db):
    rows = sql(db, 'SELECT migration_name, checksum FROM _prisma_migrations '
                   'WHERE rolled_back_at IS NULL ORDER BY migration_name').splitlines()
    mismatched = [r.split('|')[0] for r in rows
                  if r.split('|')[1] != sha256(MIGRATIONS / r.split('|')[0] / 'migration.sql')]
    return {'applied': len(rows), 'mismatched': mismatched}


def schema_diff(db):
    result = run([PRISMA, 'migrate', 'diff', '--from-url', url(db),
                  '--to-schema-datamodel', 'prisma/schema.prisma', '--exit-code'],
                 env={'DATABASE_URL': url(db)}, check=False)
    return {'exit_code': result.returncode, 'empty': result.returncode == 0,
            'output': result.stdout.strip()[-400:]}


def state_hash(db):
    return sql(db, '''SELECT md5(coalesce(string_agg(t, '|' ORDER BY t), '')) FROM (
        SELECT to_jsonb(p)::text t FROM pos."VenuePublicProfile" p
        UNION ALL SELECT to_jsonb(r)::text FROM pos."VenuePublicInfoReview" r
        UNION ALL SELECT to_jsonb(a)::text FROM pos."PlatformAuditEvent" a) s''')


def profile_hash(db):
    return sql(db, '''SELECT md5(coalesce(string_agg(to_jsonb(p)::text, '|'
        ORDER BY p."venueId"), '')) FROM pos."VenuePublicProfile" p''')


def jest(spec, env, label):
    out = proof / f'jest-{label}.json'
    run(['npx', 'jest', spec, '--runInBand', '--json', f'--outputFile={out}'],
        env={**env, 'WEB02_PROOF_DIR': str(proof)}, check=False, log=f'jest-{label}.log')
    report = json.loads(out.read_text())
    totals = {k: report[k] for k in ('numTotalTests', 'numPassedTests',
                                     'numFailedTests', 'numPendingTests', 'numTodoTests')}
    step(f'jest {label}', **totals)
    if totals['numFailedTests'] or totals['numPendingTests'] or totals['numTodoTests'] \
            or not totals['numPassedTests']:
        raise SystemExit(f'jest {label} did not pass cleanly: {totals}')
    return totals


def cli(db, *argv, check=True):
    return run(['npx', 'ts-node', '-T', 'scripts/web02-public-info.ts', *argv],
               env={'DATABASE_URL': url(db)}, check=check)


try:
    everything = sorted(p.name for p in MIGRATIONS.iterdir() if p.is_dir())
    original = [m for m in everything if m not in WEB02]
    pre = [m for m in everything if m < '20261010110000']
    # No historical migration differs from the committed HEAD bytes.
    edited = []
    for m in original:
        head = subprocess.run(['git', 'show', f'HEAD:apps/backend/prisma/migrations/{m}/migration.sql'],
                              cwd=REPO, capture_output=True).stdout
        if hashlib.sha256(head).hexdigest() != sha256(MIGRATIONS / m / 'migration.sql'):
            edited.append(m)
    step('migration chains', total=len(everything), original=len(original), pre=len(pre),
         web02=[m for m in WEB02 if m in everything], historical_edited=edited,
         foundation_sha256=sha256(MIGRATIONS / FOUNDATION / 'migration.sql'))
    if edited or len(original) != 60 or any(m not in everything for m in WEB02):
        raise SystemExit('unexpected migration chain')
    pre_root, original_root = chain('pre', pre), chain('original', original)
    temporary = [pre_root, original_root]

    for purpose in ('seed', 'original', 'upgrade', 'posthoc', 'fresh', 'shadow'):
        if exists(name(purpose)):
            raise SystemExit(f'{name(purpose)} already exists; refusing to run')
    step('all target names absent before creation')

    seed = create('seed')
    deploy(seed, pre_root, log='deploy-seed-pre.log')
    fixture_sql = proof / 'pre-foundation-fixtures.sql'
    fixture_sql.write_text(run(['npx', 'ts-node', '-T', 'test/web02-public-info.fixture.ts']).stdout)
    run(['psql', *conn, '-d', seed, '-X', '-v', 'ON_ERROR_STOP=1', '-q', '-f', str(fixture_sql)])
    (proof / 'pre-upgrade-state.json').write_text(sql(seed, '''SELECT json_agg(json_build_object(
        'venue', "venueId", 'mode', mode, 'status', status, 'revision', revision,
        'publishedRevision', "publishedRevision",
        'draft', (SELECT jsonb_object_agg(k, v) FROM jsonb_each(draft) e(k, v)
                  WHERE k IN ('workingHours','contactEmail','mapUrl','socials','gallery')),
        'published', (SELECT jsonb_object_agg(k, v) FROM jsonb_each(published) e(k, v)
                  WHERE k IN ('workingHours','contactEmail','mapUrl','socials','gallery')))
        ORDER BY "venueId") FROM pos."VenueWebsiteConfig" WHERE "venueId" LIKE 'web02-%' '''))
    backup = proof / 'pre-upgrade-backup.dump'
    run(['pg_dump', *conn, '-Fc', '-f', str(backup), seed])
    step('pre-foundation fixtures and backup', applied=len(pre),
         venues=int(sql(seed, "SELECT count(*) FROM pos.\"Venue\" WHERE id LIKE 'web02-%'")),
         backup_sha256=sha256(backup),
         profile_table_before=sql(seed, "SELECT to_regclass('pos.\"VenuePublicProfile\"') IS NOT NULL"))

    def restored(purpose):
        db = create(purpose)
        run(['pg_restore', *conn, '-d', db, '--no-owner', str(backup)])
        return db

    # 1. Original chain: the defect, reproduced from the backup.
    orig = restored('original')
    deploy(orig, original_root, log='deploy-original.log')
    step('original chain applied', checksums=checksums(orig))
    jest('website/core/public-info-upgrade.reproduction.integration.spec.ts',
         {'WEB02_REPRODUCTION_DATABASE_URL': url(orig)}, 'reproduction')

    # 2. Already migrated: original chain, then the current chain.
    posthoc = restored('posthoc')
    deploy(posthoc, original_root, log='deploy-posthoc-original.log')
    live_before = profile_hash(posthoc)
    deploy(posthoc, log='deploy-posthoc-current.log')
    hashed = state_hash(posthoc)
    report = cli(posthoc, 'report')
    (proof / 'cli-posthoc-report.json').write_text(report.stdout)
    step('already-migrated upgrade + CLI report', checksums=checksums(posthoc),
         live_unchanged_by_current_chain=profile_hash(posthoc) == live_before,
         review_rows=sql(posthoc, 'SELECT count(*) FROM pos."VenuePublicInfoReview"'),
         schema_diff=schema_diff(posthoc),
         cli_report_read_only=state_hash(posthoc) == hashed,
         requiring_decision=json.loads(report.stdout)['requiringDecision'])
    jest('website/core/public-info-already-migrated.integration.spec.ts',
         {'WEB02_POSTHOC_DATABASE_URL': url(posthoc)}, 'posthoc')
    sql(posthoc, '''INSERT INTO pos."PlatformUser" (id, email, "displayName", "passwordHash", "updatedAt")
                    VALUES ('web02-cli-operator', 'cli-operator@web02.test', 'WEB-02 CLI', 'unused', now())''')
    decided = cli(posthoc, 'decide', 'web02-venue-disabled', 'confirm-live', '--actor',
                  'cli-operator@web02.test', '--note', 'Owner confirmed via operator CLI')
    refused = cli(posthoc, 'decide', 'web02-venue-disabled', 'confirm-live', '--actor',
                  'unknown@web02.test', '--note', 'x', check=False)
    step('CLI decision', state=json.loads(decided.stdout)['state'],
         audit=sql(posthoc, "SELECT action FROM pos.\"PlatformAuditEvent\" WHERE \"platformUserId\"='web02-cli-operator'"),
         unknown_actor_exit=refused.returncode, unknown_actor_error=refused.stderr.strip()[-80:])

    # 3. Current chain from the restored backup, and in place on the seed.
    upgrade = restored('upgrade')
    deploy(upgrade, log='deploy-upgrade.log')
    hashed = state_hash(upgrade)
    report = cli(upgrade, 'report', '--values')
    (proof / 'cli-upgrade-report.json').write_text(report.stdout)
    step('restored backup upgraded + CLI report', checksums=checksums(upgrade),
         schema_diff=schema_diff(upgrade), cli_report_read_only=state_hash(upgrade) == hashed,
         requiring_decision=json.loads(report.stdout)['requiringDecision'])
    jest('website/core/public-info-upgrade.integration.spec.ts',
         {'WEB02_UPGRADE_DATABASE_URL': url(upgrade), 'WEB02_PROOF_LABEL': 'restored'}, 'restored')
    deploy(seed, log='deploy-seed-current.log')
    step('seed upgraded in place', checksums=checksums(seed), schema_diff=schema_diff(seed))
    jest('website/core/public-info-upgrade.integration.spec.ts',
         {'WEB02_UPGRADE_DATABASE_URL': url(seed), 'WEB02_PROOF_LABEL': 'inplace'}, 'inplace')
    same = {kind: json.loads((proof / f'restored-{kind}.json').read_text())
            == json.loads((proof / f'inplace-{kind}.json').read_text())
            for kind in ('database', 'public')}
    step('restore path equals in-place path', **same)
    if not all(same.values()):
        raise SystemExit('restored and in-place upgrades differ')

    # 4. Fresh install from zero, and the migration history against the schema.
    fresh = create('fresh')
    deploy(fresh, log='deploy-fresh.log')
    shadow = create('shadow')
    history = run([PRISMA, 'migrate', 'diff', '--from-migrations', 'prisma/migrations',
                   '--to-schema-datamodel', 'prisma/schema.prisma', '--shadow-database-url',
                   url(shadow), '--exit-code'], env={'DATABASE_URL': url(fresh)}, check=False)
    status = run([PRISMA, 'migrate', 'status'], env={'DATABASE_URL': url(fresh)}, check=False)
    step('fresh install', checksums=checksums(fresh), schema_diff=schema_diff(fresh),
         history_diff_empty=history.returncode == 0,
         migrate_status_exit=status.returncode,
         migrate_status=status.stdout.strip().splitlines()[-1],
         review_rows=sql(fresh, 'SELECT count(*) FROM pos."VenuePublicInfoReview"'),
         profile_rows=sql(fresh, 'SELECT count(*) FROM pos."VenuePublicProfile"'))
    for db in (orig, posthoc, upgrade, seed, fresh):
        if checksums(db)['mismatched']:
            raise SystemExit(f'checksum mismatch in {db}')
    summary['result'] = 'PASS'
finally:
    for root in locals().get('temporary', []):
        shutil.rmtree(root, ignore_errors=True)
    if not opts.keep:
        for db in reversed(created):
            run(['dropdb', *conn, db], check=False)
            gone = not exists(db)
            for entry in summary['databases']:
                if entry['name'] == db:
                    entry.update(dropped=True, absent_after=gone)
    summary['finished_at'] = datetime.now(timezone.utc).isoformat()
    (proof / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({'result': summary.get('result', 'FAIL'),
                      'databases': summary['databases']}, indent=2))
