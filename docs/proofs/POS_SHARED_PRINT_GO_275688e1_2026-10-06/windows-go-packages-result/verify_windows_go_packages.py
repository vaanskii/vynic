from __future__ import annotations
import datetime, hashlib, json, pathlib, re, sys

TASK = pathlib.Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl')
PROOF = pathlib.Path('/Users/vaanskii/Developer/vynic/docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06')
STAGE = PROOF / 'windows-go-packages-stage'
RESULT = PROOF / 'windows-go-packages-result'
NAMES = ['store','server','printqueue','printhost','printcluster','printeligibility','printtransport']

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def load(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def meta(p):
    return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}

raw=RESULT/'windows-go-packages.json'
receipt=load(raw)
assert receipt['status']=='PASS', receipt
assert receipt['nativeWindows'] and receipt['sourceFiles']==163
assert receipt['sourceBefore'] and receipt['sourceAfter'] and receipt['binaryBefore'] and receipt['binaryAfter']
assert receipt['printJobsBefore']==receipt['printJobsAfter']==0
assert all(receipt[k]==0 for k in ['documentsSubmitted','validRAWCalls','serviceRegistrations','driverInstalls','productStarts','machineRestarts','VMSettingsChanges','persistentCredentialChanges'])
assert set(receipt['packages'])==set(NAMES)
stage=load(STAGE/'stage-receipt.json')
snapshot=load(STAGE/'go-final-source-snapshot.json')
compiler=load(STAGE/'go-final-windows-package-tests.json')
assert sha(STAGE/'go-final-source-snapshot.json')=='d694adbe1410f005d6285396f81a7126cdc7b9fb9f44b08a01f7f3c5e523330a'
assert sha(STAGE/'go-final-windows-package-tests.json')=='57441bd7550ab4e0056ce34b36579ca56222ee5e58588bce9a7552963c79a404'
assert sha(STAGE/'stage-receipt.json')=='6df33960c0f019889995f69bcd327e5288e73c662cf59e98db81c91a55680f3f'
for name,m in stage['artifacts'].items():
    p=STAGE/name
    assert sha(p)==m['sha256'] and p.stat().st_size==m['bytes'], name
for rel,m in snapshot['files'].items():
    p=TASK/'go-final-validation'/rel
    assert sha(p)==m['sha256'] and p.stat().st_size==m['bytes'],rel
source_symbols={}
for rel,m in snapshot['files'].items():
    if rel.endswith('_test.go'):
        source=(TASK/'go-final-validation'/rel).read_text()
        for match in re.finditer(r'^func (Test\w+)\([^\n]*\*testing\.T[^\n]*\)',source,re.M):
            source_symbols.setdefault(match[1],[]).append({'path':rel,'line':source[:match.start()].count('\n')+1,'sha256':m['sha256'],'windowsExcluded':source.startswith('//go:build !windows')})
results={}
counts={'topLevelPass':0,'passRecords':0,'skipRecords':0,'failRecords':0}
all_test_records=[]
for name in NAMES:
    info=receipt['packages'][name]
    assert info['exitCode']==0 and info['status']=='PASS'
    assert info['binarySHA256']==compiler['artifacts'][name]['sha256'],name
    assert info['workingDirectory'].replace('\\','/').endswith('/source/apps/edge/internal/'+name), name
    stdout=RESULT/(name+'.stdout.log');stderr=RESULT/(name+'.stderr.log')
    assert sha(stdout)==info['stdoutSHA256'] and sha(stderr)==info['stderrSHA256'],name
    text=stdout.read_text(encoding='utf-8-sig')
    assert re.search(r'^PASS\s*$',text,re.M),name
    records=[]
    for line_num,line in enumerate(text.splitlines(),1):
        match=re.match(r'^\s*--- (PASS|FAIL|SKIP): (\S+) \(([0-9.]+)s\)',line)
        if not match:
            continue
        state,test,elapsed=match.groups()
        top=test.split('/')[0]
        refs=[r for r in source_symbols.get(top,[]) if '/internal/'+name+'/' in r['path']]
        assert len(refs)==1,(name,test,refs)
        assert not refs[0]['windowsExcluded'],(name,test)
        records.append({'status':state.lower(),'test':test,'topLevel':'/' not in test,'elapsedSeconds':float(elapsed),'logLine':line_num,'source':refs[0]})
    assert records and all(r['status']!='fail' for r in records),name
    skips=[r for r in records if r['status']=='skip']
    allowed={'store':{'TestOperationalCrashWorker','TestCrashWorker'},'server':{'TestOperationalProofProcess'},'printcluster':{'TestRaftProcessFixture'}}.get(name,set())
    for r in skips:
        assert r['test'] in allowed,(name,r)
    summary={'topLevelPass':sum(r['status']=='pass' and r['topLevel'] for r in records),'passRecords':sum(r['status']=='pass' for r in records),'skipRecords':len(skips),'failRecords':sum(r['status']=='fail' for r in records)}
    for k,v in summary.items(): counts[k]+=v
    results[name]={'status':'passed','exitCode':0,'elapsedMs':info['elapsedMs'],'testBinary':compiler['artifacts'][name]['sha256'],'workingDirectory':info['workingDirectory'],'stdout':meta(stdout),'stderr':meta(stderr),'counts':summary,'records':records}
    all_test_records.extend((name,r) for r in records)
# Real helper verification must be executed, not skipped due to absent binary pins.
transport=results['printtransport']['records']
assert any(r['test']=='TestWindowsActualHelperReadOnlyAndInvalidRequests' and r['status']=='pass' for r in transport)
assert any(r['test']=='TestWindowsParentDeathTerminatesChildAndFreshGuardAcquires' and r['status']=='pass' for r in transport)
# The Windows process test uses Go's os.Process.Kill => TerminateProcess; do not call it literal SIGKILL.
cluster=results['printcluster']['records']
assert any(r['test']=='TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery' and r['status']=='pass' for r in cluster)
for relay_count in [2,3,4]:
    assert any(r['test'].endswith('identical_job_actual_'+str(relay_count)+'_process_POS_relays') and r['status']=='pass' for r in cluster)
launch=load(TASK/'printer-validation/windows-go-packages-launch.json')
assert launch['prlctlExitCode']==0
excluded=[]
for symbol,refs in source_symbols.items():
    for ref in refs:
        if ref['windowsExcluded']:
            excluded.append({'test':symbol,'source':ref,'observed':'not-run','reason':'Build constraint !windows; not compiled into Windows executable'})
output=RESULT/'verified-windows-go-packages.json'
assert not output.exists(),'Do not overwrite a sealed verification receipt'
verified={
 'schema':1,'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'passed',
 'cohort':'Frozen V2 163-file source snapshot, seven cached amd64 executables on native Windows VM; future software-completion source excluded',
 'guestReceipt':meta(raw),'stageReceipt':meta(STAGE/'stage-receipt.json'),'compilerReceipt':meta(STAGE/'go-final-windows-package-tests.json'),'sourceReceipt':meta(STAGE/'go-final-source-snapshot.json'),
 'sourceSnapshotHostAfterUnchanged':True,'sourceFiles':163,'packages':results,'counts':counts,'excludedByBuildTags':excluded,
 'prlctlLog':meta(TASK/'printer-validation/windows-go-packages-prlctl.log'),'launchReceipt':meta(TASK/'printer-validation/windows-go-packages-launch.json'),
 'nativeHelper':{'sha256':'b720e1eedc77ab574d769865e39f71506a5f3ebc9d93ab5166bc3f112203019d','originalProofReadOnly':str(PROOF/'windows-result-v2/vynic_print_helper.exe'),'scope':'Queue inventory plus malformed/empty requests; no document-capable submission fixture'},
 'safetyCounters':{k:receipt[k] for k in ['printJobsBefore','printJobsAfter','documentsSubmitted','validRAWCalls','serviceRegistrations','driverInstalls','productStarts','machineRestarts','VMSettingsChanges','persistentCredentialChanges']},
 'platformLabels':{'processKill':'Windows os.Process.Kill uses TerminateProcess; test function/log retains historical SIGKILL name','restart':'Actual synthetic Raft process kill/cold rejoin and read-only helper parent death; no actual registered service restart or OS reboot','replicas':'Separate local Windows OS processes on one Windows VM using synthetic loopback; not independent physical POS machines','race':'These cached Windows binaries are not race-instrumented; previous macOS normal/race receipts remain separate','paper':'ACCEPTED/SUBMITTED are software outcomes; no paper DELIVERED proof'},
 'limits':receipt['limitations'],
 'matrixBaseline':meta(TASK/'printer-validation/acceptance-matrix-v8-baseline.json'),
 'history':'Older packets and matrix v8 baseline retained unchanged; this new observed Windows package packet is separate evidence for parent final report'
}
output.write_text(json.dumps(verified,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'verifiedReceipt':str(output),'sha256':sha(output),'counts':counts,'packageCounts':{n:r['counts'] for n,r in results.items()},'excludedUnixTests':len(excluded),'zeroJobs':True},indent=2))
