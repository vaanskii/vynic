from __future__ import annotations
import datetime,hashlib,json,os,pathlib,struct,subprocess,sys

BASE=pathlib.Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl/software-completion')
SOURCE=BASE/'final-cohort'
RECEIPT=BASE/'verification/final-cohort-source.json'
OUT=BASE/'verification/windows-software-go-build'
EXPECTED='193e4800e5d0733a30bc6c8d4ac993590219363941e69a787bba5ac3681c8f68'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def guard(files):
 for rel,meta in files.items():
  p=SOURCE/rel
  assert not p.is_symlink() and p.stat().st_size==meta['bytes'] and sha(p)==meta['sha256'],rel
assert sha(RECEIPT)==EXPECTED
frozen=json.loads(RECEIPT.read_text());assert frozen['fileCount']==1109 and frozen['beforeCopyAfterEqual'] and len(frozen['files'])==1109
assert not OUT.exists();OUT.mkdir()
guard(frozen['files'])
packages={'printeragent':'./internal/printeragent','printerdaemon':'./internal/printerdaemon','printerprovisioning':'./internal/printerprovisioning','printer-agent-command':'./cmd/printer-agent'}
result={'schema':1,'startedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceReceiptSHA256':EXPECTED,'sourceFiles':1109,'sourceRoot':str(SOURCE),'compiler':subprocess.check_output(['go','version'],text=True).strip(),'status':'compiling','artifacts':{},'executed':False,'VMExecution':'NOT RUN: automatic approval review rejected current continuation preflight; no VM command issued by this compiler','limits':'Compile-only cached official SDK/modules; no source/runtime/proof/credential changes, no SCM/product/physical calls'}
for arch,machine in [('arm64',0xaa64),('amd64',0x8664)]:
 root=OUT/arch;root.mkdir()
 env=dict(os.environ,GOOS='windows',GOARCH=arch,CGO_ENABLED='0',GOPROXY='off',GOTOOLCHAIN='local')
 for name,pkg in list(packages.items())+[('printer-agent',None)]:
  target=root/(name+('.exe' if pkg is None else '.test.exe'))
  cmd=['go','build','-mod=readonly','-o',str(target),'./cmd/printer-agent'] if pkg is None else ['go','test','-mod=readonly','-c','-o',str(target),pkg]
  print('COMPILE',arch,name,flush=True)
  started=datetime.datetime.now(datetime.timezone.utc)
  p=subprocess.run(cmd,cwd=SOURCE/'apps/edge',env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  (root/(name+'.stdout.log')).write_text(p.stdout);(root/(name+'.stderr.log')).write_text(p.stderr)
  row={'command':cmd,'environmentOverrides':{k:env[k] for k in ['GOOS','GOARCH','CGO_ENABLED','GOPROXY','GOTOOLCHAIN']},'exitCode':p.returncode,'elapsedSeconds':(datetime.datetime.now(datetime.timezone.utc)-started).total_seconds(),'path':str(target),'sourceReceiptSHA256':EXPECTED}
  if p.returncode!=0:
   print(p.stderr,flush=True);result['status']='FAILED';result['artifacts'][arch+'/'+name]=row
   (OUT/'compiler-receipt.json').write_text(json.dumps(result,indent=2)+'\n');sys.exit(p.returncode)
  raw=target.read_bytes();offset=struct.unpack_from('<I',raw,0x3c)[0];actual=struct.unpack_from('<H',raw,offset+4)[0]
  assert raw[:2]==b'MZ' and raw[offset:offset+4]==b'PE\x00\x00' and actual==machine
  row.update({'sha256':sha(target),'bytes':len(raw),'PEMachine':hex(actual),'architecture':arch,'executed':False,'buildInfo':subprocess.check_output(['go','version','-m',str(target)],text=True),'stdoutSHA256':sha(root/(name+'.stdout.log')),'stderrSHA256':sha(root/(name+'.stderr.log'))})
  result['artifacts'][arch+'/'+name]=row
  print('DONE',arch,name,row['sha256'],row['bytes'],flush=True)
  guard(frozen['files'])
result.update({'status':'PASS_COMPILE_ONLY','completedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceBeforeAfterUnchanged':True,'artifactCount':10,'requiredWindowsRuntimeEnvironment':{'VYNIC_PRINTER_AGENT_BINARY':'Extracted matching-architecture printer-agent.exe; daemon process fixture must not skip'},'requiredWorkingDirectories':{name:str(SOURCE/'apps/edge'/pkg.removeprefix('./')) for name,pkg in packages.items()}})
p=OUT/'compiler-receipt.json';p.write_text(json.dumps(result,indent=2)+'\n');print('RECEIPT',str(p),sha(p),flush=True)
