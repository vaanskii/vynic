from __future__ import annotations
import datetime,hashlib,json,pathlib,shutil,zipfile
BASE=pathlib.Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl/software-completion')
SOURCE=BASE/'final-cohort'
BUILD=BASE/'verification/windows-software-go-build'
STAGE=BASE/'verification/windows-software-go-stage'
SNAPSHOT=BASE/'verification/final-cohort-source.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def meta(p):return {'sha256':sha(p),'bytes':p.stat().st_size}
snapshot=json.loads(SNAPSHOT.read_text());compiler=json.loads((BUILD/'compiler-receipt.json').read_text())
assert sha(SNAPSHOT)=='193e4800e5d0733a30bc6c8d4ac993590219363941e69a787bba5ac3681c8f68'
assert sha(BUILD/'compiler-receipt.json')=='8bfc2090a539154f579e7d5199e4e4aa1f720d9c330fdc90f7ce67461e0fa1e6'
assert snapshot['fileCount']==1109 and len(snapshot['files'])==1109
assert compiler['status']=='PASS_COMPILE_ONLY' and len(compiler['artifacts'])==10 and compiler['sourceBeforeAfterUnchanged'] and not compiler['executed']
assert not STAGE.exists();STAGE.mkdir()
for rel,m in snapshot['files'].items():assert meta(SOURCE/rel)==m,rel
with zipfile.ZipFile(STAGE/'source1109.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for rel in sorted(snapshot['files']):z.write(SOURCE/rel,rel)
for arch in ['arm64','amd64']:
 with zipfile.ZipFile(STAGE/(arch+'-packages-cli.zip'),'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for name,row in sorted(compiler['artifacts'].items()):
   if not name.startswith(arch+'/'):continue
   p=pathlib.Path(row['path']);assert meta(p)=={'sha256':row['sha256'],'bytes':row['bytes']};z.write(p,p.name)
shutil.copyfile(SNAPSHOT,STAGE/'final-cohort-source.json')
shutil.copyfile(BUILD/'compiler-receipt.json',STAGE/'compiler-receipt.json')
(STAGE/'binary-manifest.json').write_text(json.dumps({'schema':1,'sourceReceiptSHA256':sha(SNAPSHOT),'artifacts':{k:{'filename':pathlib.Path(v['path']).name,'architecture':v['architecture'],'sha256':v['sha256'],'bytes':v['bytes'],'PEMachine':v['PEMachine']} for k,v in compiler['artifacts'].items()}},indent=2)+'\n')
(STAGE/'source-manifest.json').write_text(json.dumps({'schema':1,'sourceReceiptSHA256':sha(SNAPSHOT),'count':1109,'files':snapshot['files']},indent=2)+'\n')
(STAGE/'runtime-instructions.json').write_text(json.dumps({'schema':1,'status':'NOT_RUN_APPROVAL_BLOCKED','sourceReceiptSHA256':sha(SNAPSHOT),'requiredApproval':'Parent must obtain accepted current scoped authorization before any guest command; no alternate VM invocation','preferredArchitecture':'arm64 native test executables plus actual foreground CLI; amd64 compile/bundle retained separately','packageWorkingDirectories':{'printeragent.test.exe':'source/apps/edge/internal/printeragent','printerdaemon.test.exe':'source/apps/edge/internal/printerdaemon','printerprovisioning.test.exe':'source/apps/edge/internal/printerprovisioning','printer-agent-command.test.exe':'source/apps/edge/cmd/printer-agent'},'arguments':['-test.v','-test.timeout=10m'],'requiredProcessEnvironment':{'VYNIC_PRINTER_AGENT_BINARY':'Matching architecture extracted printer-agent.exe (verify SHA before execution)','GOPROXY':'off','GOTOOLCHAIN':'local'},'fixtureRequirements':'No guest Go SDK/build needed. Tests create their own task-only temporary SQLite/certs; supplied real CLI mandatory on Windows, never skip. Foreground shutdown-file marker triggers retained ordinary drain. Installer tests inject fake backend, no real SCM create/start/install.','freshness':'New task-only current-user LOCALAPPDATA directory; verify exact1109 files/five architecture-specific PE images before/after and zero spooler jobs before/after each package.','limits':['Do not install/register/start SCM service, change VM/settings/credentials/driver, start POS, send physical or valid real RAW jobs.','Foreground executable lifecycle in synthetic test roots is not registered service or OS restart.','Architecture/build/source hashes are separate from runtime qualification.']},indent=2)+'\n')
for rel,m in snapshot['files'].items():assert meta(SOURCE/rel)==m,rel
with zipfile.ZipFile(STAGE/'source1109.zip') as z:
 assert sorted(z.namelist())==sorted(snapshot['files'])
 for n,m in snapshot['files'].items():assert hashlib.sha256(z.read(n)).hexdigest()==m['sha256'],n
for arch in ['arm64','amd64']:
 with zipfile.ZipFile(STAGE/(arch+'-packages-cli.zip')) as z:
  rows=[v for k,v in compiler['artifacts'].items() if k.startswith(arch+'/')];assert len(z.namelist())==5
  for v in rows:assert hashlib.sha256(z.read(pathlib.Path(v['path']).name)).hexdigest()==v['sha256']
artifacts={p.name:meta(p) for p in sorted(STAGE.iterdir())}
receipt={'schema':1,'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PASS_COMPILE_AND_STAGE_ONLY','sourceReceiptSHA256':sha(SNAPSHOT),'compilerReceiptSHA256':sha(BUILD/'compiler-receipt.json'),'sourceFiles':1109,'PEArtifacts':10,'archiveEntriesVerified':True,'sourceBeforeAfterUnchanged':True,'VMCommandsIssued':0,'WindowsExecution':'NOT_RUN_APPROVAL_BLOCKED','physicalJobs':0,'SCMRegistrations':0,'machineRestarts':0,'originalOrPriorPacketEdits':0,'artifacts':artifacts,'limits':'Ready for parent-reviewed authorization, not Windows runtime/physical qualification. Prior native7-package packet and matrixV8 unchanged.','metadataNote':'Daemon owner compiled earlier same-byte source from software-completion/source; these binaries explicitly use final-cohort snapshot paths and may have different Go build IDs/file path embeddings. This packet pins only its exact1109 final inputs.'}
p=STAGE/'stage-receipt.json';p.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'stage':str(STAGE),'stageReceiptSHA256':sha(p),'sourceZipSHA256':sha(STAGE/'source1109.zip'),'arm64BinaryZipSHA256':sha(STAGE/'arm64-packages-cli.zip'),'amd64BinaryZipSHA256':sha(STAGE/'amd64-packages-cli.zip'),'sourceCount':1109,'compileOnlyPECount':10,'guestExecuted':False},indent=2))
