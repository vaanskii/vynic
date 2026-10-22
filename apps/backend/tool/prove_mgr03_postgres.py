#!/usr/bin/env python3
"""MGR03 guarded HTTP/native Edge proof on a fresh owned synthetic loopback database."""
import argparse, pathlib, subprocess, tempfile, os, json, socket, hashlib, shutil
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--postgres-bin',type=pathlib.Path,required=True)
p.add_argument('--flutter',type=pathlib.Path,required=True)
p.add_argument('--node',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();out=a.output.resolve();out.parent.mkdir(parents=True,exist_ok=True);r=out.parent;backend=pathlib.Path(__file__).resolve().parents[1];operations=backend.parent/'operations';pg=a.postgres_bin.resolve()
if not str(r).startswith(('/tmp/vynic-mgr03-','/private/tmp/vynic-mgr03-')):raise RuntimeError('Owned MGR03 receipts directory required')
cluster=pathlib.Path(tempfile.mkdtemp(prefix='vynic-mgr03-owned-pg-',dir='/tmp'))
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
url=f'postgresql://mgr03_synthetic@127.0.0.1:{port}/disposable_mgr03_20261007?schema=pos'
env={**os.environ,'PATH':str(a.node.resolve().parent)+os.pathsep+os.environ['PATH'],'DATABASE_URL':url,'MGR03_TEST_DATABASE_URL':url,'MGR03_NATIVE_FIXTURE':str(r/'native-http-fixture.json'),'MGR03_NATIVE_RECEIPTS':str(r),'MGR03_FLUTTER':str(a.flutter.resolve()),'NODE_ENV':'test','PRISMA_HIDE_UPDATE_MESSAGE':'true','CHECKPOINT_DISABLE_NOTIFICATIONS':'true'}
receipt={'scope':'fresh owned synthetic loopback PostgreSQL and native Hive only','steps':[],'started':False,'status':'RUNNING'}
def run(label,cmd,cwd=backend,timeout=180,extra=None):
 result=subprocess.run(list(map(str,cmd)),cwd=cwd,env={**env,**(extra or {})},capture_output=True,text=True,timeout=timeout)
 log=r/f'pg-{label}.log';log.write_text(result.stdout+result.stderr);receipt['steps'].append({'label':label,'exitCode':result.returncode,'logSha256':hashlib.sha256(log.read_bytes()).hexdigest()});out.write_text(json.dumps(receipt,indent=2)+'\n')
 if result.returncode:raise RuntimeError(f'{label} failed; see {log}')
 return result.stdout
try:
 run('native-baseline',[a.flutter,'test','--no-pub','--reporter','expanded','test/live/mgr03_http_edge_worker_test.dart'],cwd=operations,extra={'MGR03_NATIVE_RUN':str(r),'MGR03_NATIVE_STAGE':'baseline'})
 run('prisma-generate',[a.node,'node_modules/prisma/build/index.js','generate'])
 run('init',[pg/'initdb','-D',cluster/'data','-U','mgr03_synthetic','--auth=trust','--no-locale','--encoding=UTF8'])
 run('start',[pg/'pg_ctl','-D',cluster/'data','-l',cluster/'server.log','-o',f'-h 127.0.0.1 -p {port} -k {cluster}','-w','start']);receipt['started']=True
 run('create',[pg/'createdb','-h','127.0.0.1','-p',port,'-U','mgr03_synthetic','disposable_mgr03_20261007'])
 run('migrate',[a.node,'node_modules/prisma/build/index.js','migrate','deploy'])
 run('integration',[a.node,'node_modules/jest/bin/jest.js','--runInBand',f'--cacheDirectory={r}/jest-cache','--runTestsByPath','src/mobile/services/mgr03-operation.integration.spec.ts','--json',f'--outputFile={r}/mgr03-postgres-tests.json'],timeout=600)
 receipt['status']='PASS'
except Exception as e:
 receipt['status']='FAILED';receipt['error']=str(e);raise
finally:
 if receipt['started']:
  run('stop',[pg/'pg_ctl','-D',cluster/'data','-m','fast','-w','stop']);receipt['ownedClusterStopped']=True
 shutil.rmtree(cluster);receipt['ownedClusterRemoved']=True;out.write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
