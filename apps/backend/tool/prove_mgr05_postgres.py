#!/usr/bin/env python3
"""Qualify MGR05 using newly created synthetic PostgreSQL on loopback only."""
import argparse,pathlib,subprocess,tempfile,os,json,socket,hashlib,shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--postgres-bin',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
args=parser.parse_args()
output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
r=output.parent
backend=pathlib.Path(__file__).resolve().parents[1]
pg=args.postgres_bin.resolve()
cluster=pathlib.Path(tempfile.mkdtemp(prefix='vynic-mgr05-owned-pg-',dir='/tmp'))
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
url=f'postgresql://mgr05_synthetic@127.0.0.1:{port}/disposable_mgr05_20261007?schema=pos'
env=dict(os.environ,DATABASE_URL=url,MGR05_TEST_DATABASE_URL=url,MGR02_TEST_DATABASE_URL=url,MGR05_NATIVE_FIXTURE=str(r/'native-http-fixture.json'),NODE_ENV='test',PRISMA_HIDE_UPDATE_MESSAGE='true',CHECKPOINT_DISABLE_NOTIFICATIONS='true')
receipt={'scope':'fresh synthetic owned loopback PostgreSQL only','cluster':str(cluster),'steps':[],'started':False}
def run(label,args,timeout=180,extra_env=None):
 result=subprocess.run(list(map(str,args)),cwd=backend,env={**env,**(extra_env or {})},capture_output=True,text=True,timeout=timeout)
 (r/f'pg-{label}.log').write_text(result.stdout+result.stderr)
 receipt['steps'].append({'label':label,'exitCode':result.returncode,'logSha256':hashlib.sha256((result.stdout+result.stderr).encode()).hexdigest()})
 if result.returncode:raise RuntimeError(f'{label} failed; see pg-{label}.log')
 return result.stdout
try:
 run('init',[pg/'initdb','-D',cluster/'data','-U','mgr05_synthetic','--auth=trust','--no-locale','--encoding=UTF8'])
 run('start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr05_synthetic','disposable_mgr05_20261007'])
 run('migrate',['node','node_modules/prisma/build/index.js','migrate','deploy'])
 # Replay exactly the previous schema, preserve populated legacy rows, then
 # deploy the additive edit migration. Both databases belong to this cluster.
 previous=cluster/'previous-prisma';previous.mkdir()
 migration_name='20261007170000_manager_order_edit'
 (previous/'schema.prisma').write_text('\n'.join(line for line in (backend/'prisma/schema.prisma').read_text().splitlines() if not line.strip().startswith(('managerEditProjection ', 'resultProjection ')))+'\n')
 shutil.copytree(backend/'prisma/migrations',previous/'migrations',ignore=shutil.ignore_patterns(migration_name))
 upgrade_db='disposable_mgr05_upgrade_20261007'
 upgrade_url=f'postgresql://mgr05_synthetic@127.0.0.1:{port}/{upgrade_db}?schema=pos'
 run('upgrade-create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr05_synthetic',upgrade_db])
 run('upgrade-previous',['node','node_modules/prisma/build/index.js','migrate','deploy','--schema',previous/'schema.prisma'],extra_env={'DATABASE_URL':upgrade_url})
 seed=cluster/'seed-previous.sql'
 seed.write_text("""
 INSERT INTO pos."Organization" (id,name,"updatedAt") VALUES ('mgr05-owned-org','Synthetic upgrade',CURRENT_TIMESTAMP);
 INSERT INTO pos."Venue" (id,"organizationId",name,timezone,currency,"updatedAt") VALUES ('mgr05-owned-venue','mgr05-owned-org','Synthetic upgrade','UTC','GEL',CURRENT_TIMESTAMP);
 INSERT INTO pos."Order" (id,"venueId","posOrderId",status,"totalAmount","waiterName","updatedAt") VALUES ('mgr05-owned-order','mgr05-owned-venue',7,'confirmed',31.25,'Synthetic',CURRENT_TIMESTAMP);
 INSERT INTO pos."OrderItem" (id,"orderId",name,quantity,price) VALUES ('mgr05-owned-line','mgr05-owned-order','Retained line',5,6.25);
 INSERT INTO pos."EdgeCommand" (id,"venueId",type,payload,"idempotencyKey","updatedAt") VALUES ('mgr05-owned-command','mgr05-owned-venue','NOOP','{}','owned-upgrade',CURRENT_TIMESTAMP);
 """)
 psql=[pg/'psql','-h','127.0.0.1','-p',port,'-U','mgr05_synthetic','-d',upgrade_db,'-v','ON_ERROR_STOP=1']
 run('upgrade-seed',psql+['-f',seed])
 run('upgrade-final',['node','node_modules/prisma/build/index.js','migrate','deploy'],extra_env={'DATABASE_URL':upgrade_url})
 check=cluster/'check-upgrade.sql'
 check.write_text("""
 DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pos."Order" WHERE id='mgr05-owned-order' AND "totalAmount"=31.25 AND "managerEditProjection" IS NULL) THEN RAISE EXCEPTION 'Legacy order changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pos."OrderItem" WHERE id='mgr05-owned-line' AND quantity=5 AND price=6.25) THEN RAISE EXCEPTION 'Legacy line changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pos."EdgeCommand" WHERE id='mgr05-owned-command' AND type='NOOP' AND "resultProjection" IS NULL) THEN RAISE EXCEPTION 'Legacy command changed'; END IF;
 END $$;
 """)
 run('upgrade-retained',psql+['-f',check])
 receipt['populatedPreviousSchemaUpgrade']='PASS'

 run('integration',['node','node_modules/jest/bin/jest.js','--runInBand',f'--cacheDirectory={r}/jest-cache','--runTestsByPath','src/mobile/services/mgr05-order-edit.integration.spec.ts','src/mobile/services/mgr02-table-repair.integration.spec.ts','--json',f'--outputFile={r}/mgr05-postgres-tests.json'],240)
 receipt['status']='PASS'
except Exception as error:
 receipt['status']='FAILED';receipt['error']=str(error);raise
finally:
 if receipt['started']:
  run('stop',[pg/'pg_ctl','-D',cluster/'data','-m','fast','-w','stop']);receipt['ownedClusterStopped']=True
 output.write_text(json.dumps(receipt,indent=2)+'\n')
 shutil.rmtree(cluster)
 receipt['ownedClusterRemoved']=True
 output.write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps(receipt))
