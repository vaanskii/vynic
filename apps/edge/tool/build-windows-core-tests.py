#!/usr/bin/env python3
"""Build normal-user Windows core tests with an explicit least-privilege manifest.

No production executable is modified. Temporary COFF resources are owned by this
invocation and removed even when compilation fails. Existing resources are never
overwritten. Run the resulting tests as a normal interactive Windows user.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('setup_build', ROOT / 'tool/build-setup.py')
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)
TARGETS = {
    'setup-tests.exe': 'internal/setup',
    'updater-tests.exe': 'internal/updater',
    'setup-cli-tests.exe': 'cmd/setup',
}


def build(go, output):
    output.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, 'GOOS': 'windows', 'GOARCH': 'amd64', 'CGO_ENABLED': '0'}
    receipt = {'goVersion': subprocess.check_output([go, 'version'], text=True).strip(),
               'executionLevel': 'asInvoker', 'uiAccess': False, 'binaries': {},
               'coverage': 'Core tests, not real product installation/enrollment'}
    for name, package in TARGETS.items():
        folder = ROOT / package
        resource = folder / 'qa_test_manifest_windows_amd64.syso'
        if list(folder.glob('*.syso')):
            raise RuntimeError(f'Existing resource in {package}; preserve and inspect it')
        target = output / name
        if target.exists():
            raise RuntimeError(f'Output already exists: {target}')
        with resource.open('xb') as f:
            f.write(SETUP.pe_resource({24: SETUP.MANIFEST}))
        try:
            subprocess.run([go, 'test', '-c', '-trimpath', '-o', str(target), './' + package],
                           cwd=ROOT, env=env, check=True)
            pe = SETUP.inspect(target)
            if pe['subsystem'] != 3 or pe['resources'].get((24, 1, 1033)) != SETUP.MANIFEST:
                raise RuntimeError('Test executable lacks the exact console/asInvoker manifest')
            raw = target.read_bytes()
            receipt['binaries'][name] = {
                'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'package': package,
                'sourceSha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sorted(folder.glob('*.go'))},
            }
        finally:
            resource.unlink()
    (output / 'build-provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--go', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.go, args.out.resolve()), indent=2))
