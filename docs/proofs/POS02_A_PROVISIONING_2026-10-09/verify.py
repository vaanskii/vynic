#!/usr/bin/env python3
"""Read-only verification of this sealed POS-02.A proof and its exact source."""
import hashlib,json,pathlib
packet=pathlib.Path(__file__).resolve().parent
repo=packet.parents[2]
for name,root in [('ARTIFACTS.json',packet),('source-manifest.json',repo)]:
 for path,want in json.loads((packet/name).read_text()).items():
  file=root/path
  if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=want:
   raise SystemExit('Proof drift: '+str(file))
for name in ['backend-final.json','deletion-matrix.json']:
 result=json.loads((packet/name).read_text())
 assert result['success'] and result['numFailedTests']==0 and result['numPendingTests']==0,name
for name in ['go-regression.jsonl','go-race.jsonl','TestProductionBackendExport.jsonl','TestProductionBackendVerify.jsonl']:
 events=[json.loads(line) for line in (packet/name).read_text().splitlines()]
 assert not any(e['Action']=='fail' for e in events),name
 assert any(e['Action']=='pass' and 'Test' in e for e in events),name
win=json.loads((packet/'windows-result.json').read_text(encoding='utf-8-sig'))
assert win['exitCode']==0 and not win['printerIO'] and not win['serviceInstalled']
for name in ['typescript.log','eslint-production.log','eslint-provisioning-including-tests.log','go-vet.log','gofmt.log','diff-check.log']:
 assert not (packet/name).read_text().strip(),name
result=json.loads((packet/'proof.json').read_text())
assert result['status']=='DONE' and result['overallPOS02']=='NOT_DONE'
print('POS-02.A source, artifacts and final execution results verified')
