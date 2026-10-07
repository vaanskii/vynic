#!/usr/bin/env python3
"""Qualify MGR06 using newly created synthetic PostgreSQL on loopback only."""
import argparse,pathlib,subprocess,tempfile,os,json,socket,hashlib,shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--postgres-bin',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
args=parser.parse_args()
output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
r=output.parent
backend=pathlib.Path(__file__).resolve().parents[1]
pg=args.postgres_bin.resolve()
cluster=pathlib.Path(tempfile.mkdtemp(prefix='vynic-mgr06-owned-pg-',dir='/tmp'))
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
url=f'postgresql://mgr06_synthetic@127.0.0.1:{port}/disposable_vynic_step47_test_mgr06_20261007?schema=pos'
env=dict(os.environ,DATABASE_URL=url,MGR06_TEST_DATABASE_URL=url,TENANT_INTEGRATION_DATABASE_URL=url,MGR01_TEST_DATABASE_URL=url,MGR02_TEST_DATABASE_URL=url,MGR05_TEST_DATABASE_URL=url,MGR03_TEST_DATABASE_URL=url,MGR06_FIXTURE_OUTPUT=str(r/'mgr06-http-fixture.json'),NODE_ENV='test',PRISMA_HIDE_UPDATE_MESSAGE='true',CHECKPOINT_DISABLE_NOTIFICATIONS='true')
receipt={'scope':'fresh synthetic owned loopback PostgreSQL only','cluster':str(cluster),'steps':[],'started':False}
def run(label,args,timeout=180,run_env=None):
 result=subprocess.run(list(map(str,args)),cwd=backend,env=run_env or env,capture_output=True,text=True,timeout=timeout)
 (r/f'pg-{label}.log').write_text(result.stdout+result.stderr)
 receipt['steps'].append({'label':label,'exitCode':result.returncode,'logSha256':hashlib.sha256((result.stdout+result.stderr).encode()).hexdigest()})
 if result.returncode:raise RuntimeError(f'{label} failed; see pg-{label}.log')
 return result.stdout
try:
 run('init',[pg/'initdb','-D',cluster/'data','-U','mgr06_synthetic','--auth=trust','--no-locale','--encoding=UTF8'])
 run('start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr06_synthetic','disposable_vynic_step47_test_mgr06_20261007'])
 run('migrate',['node','node_modules/prisma/build/index.js','migrate','deploy'])
 run('integration',['node','node_modules/jest/bin/jest.js','--runInBand',f'--cacheDirectory={r}/jest-cache','--runTestsByPath','src/finance/mgr06-corrections.integration.spec.ts','src/finance/finance.integration.spec.ts','--json',f'--outputFile={r}/mgr06-postgres-tests.json'],240)
 # Upgrade a second owned database from all unchanged prior migrations.
 upgrade_name='disposable_mgr06_upgrade_20261007'
 run('upgrade-create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr06_synthetic',upgrade_name])
 upgrade_env=dict(env,DATABASE_URL=f'postgresql://mgr06_synthetic@127.0.0.1:{port}/{upgrade_name}?schema=pos')
 before_prisma=cluster/'before-prisma'
 shutil.copytree(backend/'prisma',before_prisma)
 shutil.rmtree(before_prisma/'migrations'/'20261007170000_finance_entry_corrections')
 run('upgrade-before-migrate',['node','node_modules/prisma/build/index.js','migrate','deploy','--schema',before_prisma/'schema.prisma'],run_env=upgrade_env)
 snapshot=r/'mgr06-upgrade-original.json'
 run('upgrade-seed',['node','tool/mgr06_upgrade_fixture.mjs','before',snapshot],run_env=upgrade_env)
 run('upgrade-migrate',['node','node_modules/prisma/build/index.js','migrate','deploy'],run_env=upgrade_env)
 run('upgrade-preserved',['node','tool/mgr06_upgrade_fixture.mjs','after',snapshot],run_env=upgrade_env)
 run('restart-stop',[pg/'pg_ctl','-D',cluster/'data','-m','fast','-w','stop']);receipt['started']=False
 run('restart-start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('upgrade-preserved-after-restart',['node','tool/mgr06_upgrade_fixture.mjs','after',snapshot],run_env=upgrade_env)
 run('migration-drift',['node','node_modules/prisma/build/index.js','migrate','diff','--from-url',upgrade_env['DATABASE_URL'],'--to-schema-datamodel','prisma/schema.prisma','--exit-code'],run_env=upgrade_env)
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
