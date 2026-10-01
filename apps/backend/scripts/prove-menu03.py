#!/usr/bin/env python3
"""MENU03: isolated PostgreSQL fresh/upgrade, HTTP replay, DB/process and POS restart.

PGHOST=127.0.0.1 PGPORT=<owned port> PGUSER=<test user> python3 scripts/prove-menu03.py \
  --tag <8 hex> --proof-dir <new directory> --cluster <owned cluster> \
  --flutter <SDK>/bin/flutter [--keep]

Only absent disposable_menu03_<tag>_* databases are created, then cleaned unless
--keep. The cluster must be a MENU03 temp cluster whose port/user match this run.
Credentials are saved only in mode-0600 temporary fixture files, never in proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parents[1]
MIGRATIONS = BACKEND / 'prisma/migrations'
NEW = '20261013120000_menu03_exact_mutation_result'
PRISMA = BACKEND / 'node_modules/.bin/prisma'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tag', required=True)
parser.add_argument('--proof-dir', required=True, type=Path)
parser.add_argument('--cluster', required=True, type=Path)
parser.add_argument('--flutter', required=True, type=Path)
parser.add_argument('--keep', action='store_true')
args = parser.parse_args()
if not re.fullmatch('[0-9a-f]{8}', args.tag): raise SystemExit('8 hex tag required')
host = os.environ.get('PGHOST', '127.0.0.1'); port = os.environ['PGPORT']; user = os.environ['PGUSER']
if host != '127.0.0.1' or not str(args.cluster).startswith('/private/tmp/vynic-menu03-pg-'):
    raise SystemExit('Owned loopback MENU03 cluster required')
if args.proof_dir.exists(): raise SystemExit('New proof directory required')
args.proof_dir.mkdir(parents=True)
proof = args.proof_dir.resolve()
conn = ['-h', host, '-p', port, '-U', user]
created = []; server = None; logs = []
summary = {'tag': args.tag, 'databases': [], 'steps': [], 'commands': []}
def run(cmd, *, env=None, cwd=BACKEND, label, check=True):
    summary['commands'].append({'label': label, 'argv': [str(x) for x in cmd]})
    r = subprocess.run([str(x) for x in cmd], cwd=cwd, env={**os.environ, **(env or {})}, capture_output=True, text=True)
    path = proof / (label + '.log'); path.write_text(r.stdout + r.stderr); logs.append(path)
    if check and r.returncode: raise RuntimeError(f'{label}: exit {r.returncode}; see {path}')
    return r
def sql(db, query):
    return subprocess.check_output(['psql', *conn, '-d', db, '-X', '-v', 'ON_ERROR_STOP=1', '-At', '-c', query], text=True).strip()
def url(db): return f'postgresql://{user}@{host}:{port}/{db}'
def create(purpose):
    name = f'disposable_menu03_{args.tag}_{purpose}'
    if sql('postgres', f"SELECT count(*) FROM pg_database WHERE datname='{name}'") != '0': raise RuntimeError('Refusing existing database ' + name)
    summary['databases'].append({'name': name, 'absentBefore': True, 'verificationOwned': True})
    (proof / 'ownership.json').write_text(json.dumps(summary['databases'], indent=2))
    run(['createdb', *conn, name], label='create-' + purpose); created.append(name); return name
def deploy(db, root=BACKEND, label='deploy'):
    run([PRISMA, 'migrate', 'deploy', '--schema', root / 'prisma/schema.prisma'], env={'DATABASE_URL': url(db)}, cwd=root, label=label)
def check_schema(db, label):
    status = run([PRISMA, 'migrate', 'status'], env={'DATABASE_URL': url(db)}, label=label+'-status')
    diff = run([PRISMA, 'migrate', 'diff', '--from-url', url(db), '--to-schema-datamodel', 'prisma/schema.prisma', '--exit-code'], env={'DATABASE_URL': url(db)}, label=label+'-diff')
    rows = sql(db, 'SELECT migration_name, checksum FROM _prisma_migrations WHERE rolled_back_at IS NULL ORDER BY migration_name').splitlines()
    mismatches = [r.split('|')[0] for r in rows if r.split('|')[1] != hashlib.sha256((MIGRATIONS / r.split('|')[0] / 'migration.sql').read_bytes()).hexdigest()]
    if mismatches: raise RuntimeError('Migration checksums changed')
    return {'migrationCount': len(rows), 'checksumMismatches': mismatches, 'statusExit': status.returncode, 'schemaDiffExit': diff.returncode, 'schemaDiffEmpty': diff.returncode == 0}
def start(db, fixture, seed):
    global server
    log = (proof / f'server-{len(logs)}.log'); logs.append(log)
    handle = log.open('w')
    server = subprocess.Popen(['node', '-r', 'ts-node/register/transpile-only', 'scripts/serve-menu03-local.ts', '--confirm-local'], cwd=BACKEND, stdout=handle, stderr=subprocess.STDOUT, env={**os.environ, 'MENU03_TEST_DATABASE_URL': url(db), 'MENU03_HTTP_FIXTURE': str(fixture), 'MENU03_SEED': seed})
    handle.close(); deadline = time.monotonic()+45
    while time.monotonic() < deadline:
        if server.poll() is not None: raise RuntimeError('HTTP server exited: '+str(log))
        if fixture.exists():
            f = json.loads(fixture.read_text())
            if f.get('backendPid') == server.pid: return f
        time.sleep(.05)
    raise TimeoutError('HTTP startup timed out')
def stop():
    global server
    if server and server.poll() is None:
        server.terminate(); server.wait(timeout=20)
    server = None
def http(fixture, body, venue=0):
    v = fixture['venues'][venue]
    req = urllib.request.Request(fixture['baseUrl']+'/edge/menu/mutations', data=json.dumps(body).encode(), headers={'Content-Type':'application/json', 'X-POS-Sync-Key': v['credential']}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=15) as r: return r.status, json.load(r)
    except urllib.error.HTTPError as e: return e.code, json.load(e)
def accepted(fixture, body):
    status, result = http(fixture, body)
    if status != 200: raise RuntimeError(f'Unexpected HTTP {status} {result}')
    return result
def outcome(body): return {k:v for k,v in body.items() if k != 'duplicate'}
def mutation(kind, entity, patch, revision=0):
    return {'mutationId':str(uuid.uuid4()), 'entityType':kind, 'entityId':entity, 'operation':'UPSERT', 'expectedRevision':revision, 'patch':patch}
def flutter(fixture_path, directory, stage):
    command = [args.flutter, 'test', '--no-pub', '--reporter', 'expanded', 'test/live/menu03_ack_loss_test.dart']
    log = proof / f'pos-{stage}.log'; logs.append(log)
    env = {**os.environ, 'FLUTTER_SUPPRESS_ANALYTICS':'true', 'MENU03_HTTP_FIXTURE':str(fixture_path), 'MENU03_HIVE_DIR':str(directory), 'MENU03_POS_STAGE':stage}
    with log.open('w') as handle:
        if stage == 'reader':
            r = subprocess.run(command, cwd=REPO/'apps/operations', stdout=handle, stderr=subprocess.STDOUT, env=env, timeout=90)
            if r.returncode: raise RuntimeError('POS reader failed: '+str(log))
            return {'exit':r.returncode, **json.loads((directory/'reader.json').read_text())}
        writer = subprocess.Popen(command, cwd=REPO/'apps/operations', stdout=handle, stderr=subprocess.STDOUT, env=env)
        try:
            deadline=time.monotonic()+60
            ready=directory/'writer.json'
            while not ready.exists():
                if writer.poll() is not None: raise RuntimeError('POS writer exited: '+str(log))
                if time.monotonic()>deadline: raise TimeoutError('POS checkpoint timeout')
                time.sleep(.025)
            saved=json.loads(ready.read_text()); pid=int(saved['writerPid']); ancestor=pid
            for _ in range(20):
                if ancestor==writer.pid: break
                ancestor=int(subprocess.check_output(['ps','-o','ppid=','-p',str(ancestor)],text=True).strip())
                if ancestor<=1: raise RuntimeError('Native PID is not our child')
            else: raise RuntimeError('Invalid child ancestry')
            os.kill(pid, signal.SIGKILL); code=writer.wait(timeout=30)
            if code==0: raise RuntimeError('Killed writer reported success')
            return {'signal':'SIGKILL','exit':code,**saved}
        finally:
            if writer.poll() is None: writer.terminate(); writer.wait(timeout=10)

temp_chain = None; hive = None
try:
    actual = sql('postgres', 'SHOW port')
    if actual != port or sql('postgres', 'SELECT current_user') != user: raise RuntimeError('Cluster identity mismatch')
    reported_cluster = sql('postgres', 'SHOW data_directory')
    if Path(reported_cluster).resolve() != args.cluster.resolve(): raise RuntimeError('Different cluster')
    summary['postgresVersion'] = sql('postgres', 'SELECT version()')
    upgrade=create('upgrade'); fresh=create('fresh')
    temp_chain=Path(tempfile.mkdtemp(prefix='menu03_previous_chain_'))
    (temp_chain/'prisma/migrations').mkdir(parents=True)
    shutil.copy(BACKEND/'prisma/schema.prisma', temp_chain/'prisma/schema.prisma')
    shutil.copy(MIGRATIONS/'migration_lock.toml', temp_chain/'prisma/migrations')
    for m in sorted(MIGRATIONS.iterdir()):
        if m.is_dir() and m.name != NEW: shutil.copytree(m,temp_chain/'prisma/migrations'/m.name)
    deploy(upgrade,temp_chain,'previous-deploy')
    # Seed old schema through actual application identity services; only the old
    # mutation INSERT uses explicit previous columns, since the new client expects
    # acceptedResult on returned mutation rows. Never synthesize a historical result.
    legacy_file=proof/'legacy-private-fixture.json'
    seed_code=r'''
const {writeFileSync}=require('node:fs');const {randomUUID}=require('node:crypto');
const {menu03App,seedMenu03}=require('./test/menu03.fixture.ts');
const {requestHash,normalizeMutation}=require('./src/menu-catalog/menu-mutation.ts');
(async()=>{const {app,db}=await menu03App(process.env.MENU03_TEST_DATABASE_URL);try{
const f=await seedMenu03(db,app);const m={mutationId:randomUUID(),entityType:'CATEGORY',entityId:randomUUID(),operation:'UPSERT',expectedRevision:0,patch:{nameKa:'Legacy',nameEn:'Legacy'}};
await db.$executeRawUnsafe('INSERT INTO pos."MenuCatalogMutation" ("venueId","mutationId","entityType","entityId","operation","expectedRevision","resultRevision","seq","actorType","actorId","source","requestHash","changes") VALUES ($1,$2,\'CATEGORY\',$3,\'UPSERT\',0,1,1,\'DEVICE\',$4,\'POS\',$5,\'{}\'::jsonb)', f.venues[0].venueId,m.mutationId,m.entityId,'synthetic-old-device',requestHash(normalizeMutation(m)));
writeFileSync(process.env.MENU03_HTTP_FIXTURE,JSON.stringify({...f,legacyRequest:m}),{mode:0o600});
}finally{await app.close();await db.$disconnect();}})().catch(e=>{console.error(e);process.exitCode=1;});
'''
    run(['node','-r','ts-node/register/transpile-only','-e',seed_code], env={'MENU03_TEST_DATABASE_URL':url(upgrade),'MENU03_HTTP_FIXTURE':str(legacy_file)},label='seed-legacy')
    old_hash=sql(upgrade, 'SELECT md5(string_agg(to_jsonb(m)::text,\'|\' ORDER BY "mutationId")) FROM pos."MenuCatalogMutation" m')
    deploy(upgrade,label='upgrade-deploy'); deploy(fresh,label='fresh-deploy')
    new_hash=sql(upgrade, 'SELECT md5(string_agg((to_jsonb(m)-\'acceptedResult\')::text,\'|\' ORDER BY "mutationId")) FROM pos."MenuCatalogMutation" m')
    if old_hash != new_hash: raise RuntimeError('Legacy mutation changed')
    summary['migration']={'previousTip':sorted(p.name for p in MIGRATIONS.iterdir() if p.is_dir() and p.name != NEW)[-1], 'newTip':NEW, 'oldRowHashBefore':old_hash,'oldRowHashAfter':new_hash, 'legacyNullRows':int(sql(upgrade,'SELECT count(*) FROM pos."MenuCatalogMutation" WHERE "acceptedResult" IS NULL')), 'upgrade':check_schema(upgrade,'upgrade'), 'fresh':check_schema(fresh,'fresh')}
    run([PRISMA,'validate'],env={'DATABASE_URL':url(fresh)},label='prisma-validate')
    fixture_file=proof/'http-private-fixture.json'; f=start(fresh,fixture_file,'1'); first_pid=f['backendPid']
    cases=[]; golden=[]
    for kind in ['CATEGORY','SUBCATEGORY','ITEM','VARIANT']:
        parent=str(uuid.uuid4()); parent_item=str(uuid.uuid4()); entity=str(uuid.uuid4())
        if kind!='CATEGORY': accepted(f,mutation('CATEGORY',parent,{'nameKa':'Parent','nameEn':'Parent'}))
        if kind=='VARIANT': accepted(f,mutation('ITEM',parent_item,{'categoryId':parent,'nameKa':'Parent item','nameEn':'Parent item','price':10}))
        patch={'nameKa':'Initial','nameEn':'Initial'} if kind=='CATEGORY' else {'categoryId':parent,'nameKa':'Initial','nameEn':'Initial'} if kind=='SUBCATEGORY' else {'categoryId':parent,'nameKa':'Initial','nameEn':'Initial','price':10} if kind=='ITEM' else {'menuItemId':parent_item,'size':.15,'price':10}
        accepted(f,mutation(kind,entity,patch)); m1=mutation(kind,entity,{'price':12} if kind=='VARIANT' else {'nameEn':'First edit'},1)
        original=accepted(f,m1); immediate=accepted(f,m1)
        m2=accepted(f,mutation(kind,entity,{'price':20} if kind=='VARIANT' else {'nameEn':'Second edit'},2)); after_edit=accepted(f,m1)
        deletion={'mutationId':str(uuid.uuid4()),'entityType':kind,'entityId':entity,'operation':'DELETE','expectedRevision':3}
        deleted=accepted(f,deletion); after_delete=accepted(f,m1)
        accepted(f,mutation('CATEGORY',str(uuid.uuid4()),{'nameKa':'Unrelated','nameEn':'Unrelated'})); delete_retry=accepted(f,deletion)
        reuse_status,reuse=http(f,{**m1,'patch':{'price':99} if kind=='VARIANT' else {'nameEn':'Changed'}})
        if not all(outcome(r)==outcome(original) for r in [immediate,after_edit,after_delete]) or outcome(delete_retry)!=outcome(deleted) or reuse_status!=409 or reuse['code']!='MUTATION_ID_REUSED': raise RuntimeError('Exact HTTP proof failed '+kind)
        cases.append({'kind':kind,'original':original,'immediate':immediate,'laterEdit':m2,'afterEdit':after_edit,'deleted':deleted,'afterDelete':after_delete,'deleteRetry':delete_retry,'reuse':{'status':reuse_status,'body':reuse}})
        golden.extend([(m1,original),(deletion,deleted)])
    summary['httpCases']=cases
    hive=Path(tempfile.mkdtemp(prefix='vynic_menu03_process_',dir='/private/tmp'))
    writer=flutter(fixture_file,hive,'writer'); summary['posWriter']=writer
    m2=accepted(f,mutation('ITEM',f['ids']['item'],{'price':13},2)); summary['posLaterMutation']=m2
    # All HTTP services/connections are stopped before restarting only this cluster.
    stop(); run(['pg_ctl','-D',args.cluster,'-m','fast','-w','restart','-l',proof/'postgres-restart.log'],label='postgres-restart')
    f=start(fresh,fixture_file,'0')
    if f['backendPid']==first_pid: raise RuntimeError('Backend must be another process')
    summary['restart']={'backendPidBefore':first_pid,'backendPidAfter':f['backendPid'],'postgresRestart':True,'cases':[]}
    count_before=int(sql(fresh,'SELECT count(*) FROM pos."MenuCatalogMutation"'))
    for body,original in golden:
        retry=accepted(f,body)
        if outcome(retry)!=outcome(original): raise RuntimeError('Restart outcome changed')
        summary['restart']['cases'].append({'mutationId':body['mutationId'],'entityType':body['entityType'],'operation':body['operation'],'exact':True})
    if int(sql(fresh,'SELECT count(*) FROM pos."MenuCatalogMutation"')) != count_before: raise RuntimeError('Replay wrote mutations')
    summary['posReader']=flutter(fixture_file,hive,'reader')
    if int(sql(fresh,f'SELECT count(*) FROM pos."MenuCatalogMutation" WHERE "mutationId"=\'{writer["mutationIds"][0]}\''))!=1: raise RuntimeError('M1 duplicated')
    # Bounded history sample, measuring individual accepted-result storage only.
    timings=[]
    for i in range(100):
        body=mutation('VARIANT',f['ids']['variant'],{'price':10+i/100},i+1)
        started=time.perf_counter(); accepted(f,body); timings.append((time.perf_counter()-started)*1000)
    storage=sql(fresh, '''SELECT json_agg(x) FROM (SELECT "entityType",count(*) mutations, round(avg(pg_column_size("acceptedResult"))) result_bytes_avg, min(pg_column_size("acceptedResult")) result_bytes_min, max(pg_column_size("acceptedResult")) result_bytes_max, round(avg(pg_column_size(m))) row_bytes_avg FROM pos."MenuCatalogMutation" m GROUP BY "entityType" ORDER BY "entityType") x''')
    summary['storage']={'byKind':json.loads(storage),'additionalHistoryMutations':100,'httpMutationMs':{'p50':sorted(timings)[49],'p95':sorted(timings)[94],'max':max(timings)},'wholeCatalogStored':False,'retentionChanged':False}
    stop(); legacy=start(upgrade,legacy_file,'0'); status,result=http(legacy,legacy['legacyRequest'])
    changed_status,changed=http(legacy,{**legacy['legacyRequest'],'patch':{'nameEn':'Changed'}})
    if status!=409 or result['code']!='MUTATION_RESULT_UNAVAILABLE' or changed_status!=409 or changed['code']!='MUTATION_ID_REUSED': raise RuntimeError('Legacy policy failed')
    summary['legacyHttp']={'status':status,'body':result,'changedStatus':changed_status,'changedCode':changed['code'],'unchanged':sql(upgrade,'SELECT md5(string_agg((to_jsonb(m)-\'acceptedResult\')::text,\'|\' ORDER BY "mutationId")) FROM pos."MenuCatalogMutation" m')==old_hash}
    if not summary['legacyHttp']['unchanged']: raise RuntimeError('Legacy row rewritten')
    stop(); summary['status']='PASS'
finally:
    stop()
    if temp_chain: shutil.rmtree(temp_chain)
    if hive: shutil.rmtree(hive)
    summary['tempHiveRemoved']=bool(hive)
    for p in proof.glob('*private-fixture.json'): p.unlink()
    summary['privateCredentialsRemoved']=True
    if not args.keep:
        for db in reversed(created): run(['dropdb',*conn,db],label='drop-'+db)
    summary['databasesRetained']=args.keep
    summary['logs']=[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in logs if p.exists()]
    (proof/'result.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({'status':summary.get('status','FAILED'),'proof':str(proof/'result.json'),'databases':created}))
