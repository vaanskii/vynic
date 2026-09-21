#!/usr/bin/env python3
"""Build Windows Edge with stable native product/version resources."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
from windows_pe import resource,version_info,inspect


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--out',required=True,type=Path)
    p.add_argument('--version',default='1.0.0.0')
    p.add_argument('--go',default='go')
    a=p.parse_args()
    root=Path(__file__).resolve().parents[1]
    spec=importlib.util.spec_from_file_location('setup_build',Path(__file__).with_name('build-setup.py'))
    setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)
    manifest=setup.MANIFEST.replace(b'Vynic.Setup',b'Vynic.Edge').replace(b'1.0.0.0',a.version.encode())
    syso=root/'cmd/edge/manifest_windows_amd64.syso'
    if syso.exists():p.error('existing resource must be preserved')
    syso.write_bytes(resource({24:manifest,16:version_info('Vynic Edge','VynicEdge.exe',a.version)}))
    try:
        subprocess.run([a.go,'build','-trimpath','-o',str(a.out.resolve()),'./cmd/edge'],cwd=root,
            env={**os.environ,'GOOS':'windows','GOARCH':'amd64','CGO_ENABLED':'0'},check=True)
        result=inspect(a.out);del result['resources'];print(json.dumps(result,indent=2))
    finally:syso.unlink()

if __name__=='__main__':main()
