#!/usr/bin/env python3
"""Qualify Manager sync repairs using newly created synthetic PostgreSQL on loopback only."""
import argparse,pathlib,subprocess,tempfile,os,json,socket,hashlib,shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--postgres-bin',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
parser.add_argument('--sale-wire',type=pathlib.Path)
parser.add_argument('--runtime-dir',type=pathlib.Path)
parser.add_argument('--runtime-port',type=int)
args=parser.parse_args()
output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
r=output.parent
backend=pathlib.Path(__file__).resolve().parents[1]
pg=args.postgres_bin.resolve()
cluster=pathlib.Path(tempfile.mkdtemp(prefix='vynic-manager-sync-owned-pg-',dir='/tmp'))
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
url=f'postgresql://manager_sync_synthetic@127.0.0.1:{port}/disposable_manager_sync_20261017?schema=pos'
env=dict(os.environ,DATABASE_URL=url,MGR04_TEST_DATABASE_URL=url,TENANT_INTEGRATION_DATABASE_URL=url,MGR04_FIXTURE_OUTPUT=str(r/'manager-sync-http-fixture.json'),NODE_ENV='test',PRISMA_HIDE_UPDATE_MESSAGE='true',CHECKPOINT_DISABLE_NOTIFICATIONS='true')
env.pop('POS_RETAINED_SALES_WIRE_OUTPUT',None)
if args.sale_wire: env['POS_RETAINED_SALES_WIRE_OUTPUT']=str(args.sale_wire.resolve(strict=True))
if args.runtime_dir: env['MGR04_NATIVE_RUNTIME_DIR']=str(args.runtime_dir.resolve())
if args.runtime_port: env['MGR04_QA_PORT']=str(args.runtime_port)
receipt={'scope':'fresh synthetic owned loopback PostgreSQL only','cluster':str(cluster),'steps':[],'started':False}
def run(label,args,timeout=180):
 result=subprocess.run(list(map(str,args)),cwd=backend,env=env,capture_output=True,text=True,timeout=timeout)
 (r/f'pg-{label}.log').write_text(result.stdout+result.stderr)
 receipt['steps'].append({'label':label,'exitCode':result.returncode,'logSha256':hashlib.sha256((result.stdout+result.stderr).encode()).hexdigest()})
 if result.returncode:raise RuntimeError(f'{label} failed; see pg-{label}.log')
 return result.stdout
try:
 run('init',[pg/'initdb','-D',cluster/'data','-U','manager_sync_synthetic','--auth=trust','--no-locale','--encoding=UTF8'])
 run('start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','manager_sync_synthetic','disposable_manager_sync_20261017'])
 run('migrate',['node','node_modules/prisma/build/index.js','migrate','deploy'])
 run('integration',['node','node_modules/jest/bin/jest.js','--runInBand',f'--cacheDirectory={r}/jest-cache','--runTestsByPath','src/mobile/services/mgr04-freshness.integration.spec.ts','src/pos/sync/snapshot/sale-ledger-sync.integration.spec.ts','--json',f'--outputFile={r}/manager-sync-postgres-tests.json'],1200 if args.runtime_dir else 240)
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
