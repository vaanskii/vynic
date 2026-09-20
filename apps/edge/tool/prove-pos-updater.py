#!/usr/bin/env python3
"""Run real separate-Hive-process restart proof without Windows or production data."""
import argparse, json, os, subprocess, tempfile
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--dart',default='dart');p.add_argument('--output');args=p.parse_args()
root=Path(__file__).resolve().parents[3];operations=root/'apps/operations'
with tempfile.TemporaryDirectory(prefix='vynic-pos-update-proof-') as directory:
    results=[]
    for action in ['seed','new-release','rollback-release']:
        run=subprocess.run([args.dart,'run','tool/pos_update_hive_proof.dart',directory,action],cwd=operations,text=True,capture_output=True,check=True)
        results.append(json.loads(run.stdout.strip().splitlines()[-1]))
    expected={k:v for k,v in results[0].items() if k!='pid'}
    assert all({k:v for k,v in r.items() if k!='pid'}==expected for r in results)
    assert len({r['pid'] for r in results})==3
    report={'proof':'Windows POS updater data recovery on macOS','independentPids':[r['pid'] for r in results],
            'checks':['open Order/Table are READY','flushed Hive survives abrupt process exit','new release reopens same durable UUIDs and occupancy','rollback release reopens same data without restoring it','durable pending Cloud outbox remains'],
            'state':expected,'windowsArtifactExecuted':False}
    text=json.dumps(report,indent=2,ensure_ascii=False)
    if args.output:Path(args.output).write_text(text+'\n')
    print(text)
