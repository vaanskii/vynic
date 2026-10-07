#!/usr/bin/env python3
"""Qualify MGR02 using newly created synthetic PostgreSQL on loopback only."""
import argparse,pathlib,subprocess,tempfile,os,json,socket,hashlib,shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--postgres-bin',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
args=parser.parse_args()
output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
r=output.parent
backend=pathlib.Path(__file__).resolve().parents[1]
pg=args.postgres_bin.resolve()
cluster=pathlib.Path(tempfile.mkdtemp(prefix='vynic-mgr02-owned-pg-',dir='/tmp'))
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
url=f'postgresql://mgr02_synthetic@127.0.0.1:{port}/disposable_mgr02_20261007?schema=pos'
env=dict(os.environ,DATABASE_URL=url,MGR02_TEST_DATABASE_URL=url,NODE_ENV='test',PRISMA_HIDE_UPDATE_MESSAGE='true',CHECKPOINT_DISABLE_NOTIFICATIONS='true')
receipt={'scope':'fresh synthetic owned loopback PostgreSQL only','cluster':str(cluster),'steps':[],'started':False}
def run(label,args,timeout=180):
 result=subprocess.run(list(map(str,args)),cwd=backend,env=env,capture_output=True,text=True,timeout=timeout)
 (r/f'pg-{label}.log').write_text(result.stdout+result.stderr)
 receipt['steps'].append({'label':label,'exitCode':result.returncode,'logSha256':hashlib.sha256((result.stdout+result.stderr).encode()).hexdigest()})
 if result.returncode:raise RuntimeError(f'{label} failed; see pg-{label}.log')
 return result.stdout
try:
 run('init',[pg/'initdb','-D',cluster/'data','-U','mgr02_synthetic','--auth=trust','--no-locale','--encoding=UTF8'])
 run('start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr02_synthetic','disposable_mgr02_20261007'])
 run('migrate',['node','node_modules/prisma/build/index.js','migrate','deploy'])
 run('integration',['node','node_modules/jest/bin/jest.js','--runInBand',f'--cacheDirectory={r}/jest-cache','--runTestsByPath','src/mobile/services/mgr02-table-repair.integration.spec.ts','--json',f'--outputFile={r}/mgr02-postgres-tests.json'],240)
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
