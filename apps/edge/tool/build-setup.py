#!/usr/bin/env python3
"""Cross-build the small Windows GUI bootstrapper with pinned public distribution config.
Writes an amd64 COFF manifest resource without requiring a Windows SDK/windres.
Production Authenticode signing is a separate release-pipeline operation.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import struct
import subprocess
from windows_distribution import validate as validate_distribution

MANIFEST = b'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<assemblyIdentity version="1.0.0.0" processorArchitecture="amd64" name="Vynic.Setup" type="win32"/>
<dependency><dependentAssembly><assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="amd64" publicKeyToken="6595b64144ccf1df" language="*"/></dependentAssembly></dependency>
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
<requestedExecutionLevel level="asInvoker" uiAccess="false"/>
</requestedPrivileges></security></trustInfo>
<compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application>
<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
</application></compatibility>
</assembly>'''


from windows_pe import resource as pe_resource, version_info, inspect, icon_resources


def resource(payload, version='1.0.8.0', product='Vynic Setup', filename='VynicSetup.exe'):
    icon = Path(__file__).resolve().parents[2] / 'operations/windows/runner/resources/app_icon.ico'
    return pe_resource({24:payload,16:version_info(product,filename,version), **icon_resources(icon.read_bytes())})


def inspect_pe(path, version='1.0.8.0'):
    result=inspect(Path(path))
    assert result['subsystem']==2, 'not GUI subsystem'
    assert result['resources'][(24,1,1033)]==MANIFEST.replace(b'1.0.0.0',version.encode()), 'manifest mismatch'
    ver=result['resources'][(16,1,1033)]
    for text in ['CompanyName','Vynic','FileDescription','Vynic Setup','OriginalFilename','VynicSetup.exe']:
        assert (text+'\0').encode('utf-16le') in ver, 'version metadata missing'
    assert (14,1,1033) in result['resources'], 'application icon missing'
    result['iconImages'] = sum(key[0] == 3 for key in result['resources'])
    assert result['iconImages'] > 0
    del result['resources']
    result['executionLevel']='asInvoker'
    result['product']='Vynic Setup'
    result['authenticode']='not signed; external signing and Defender qualification required'
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--distribution', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--go', default='go')
    p.add_argument('--version', default='1.0.8.0')
    p.add_argument('--production', action='store_true', help='Require a public stable/beta feed and unexpired production trust configuration')
    a = p.parse_args()
    raw = a.distribution.read_bytes()
    try:
        validate_distribution(raw, production=a.production)
    except ValueError as error:
        p.error(str(error))
    root = Path(__file__).resolve().parents[1]
    syso = root / 'cmd/setup/manifest_windows_amd64.syso'
    if syso.exists():
        p.error('manifest resource already exists; preserve it and inspect')
    syso.write_bytes(resource(MANIFEST.replace(b'1.0.0.0',a.version.encode()),a.version))
    try:
        subprocess.run([a.go, 'build', '-trimpath', '-ldflags',
                        '-H=windowsgui -X main.distributionBase64=' + base64.b64encode(raw).decode() + ' -X main.setupVersion=' + a.version,
                        '-o', str(a.out.resolve()), './cmd/setup'], cwd=root,
                       env={**os.environ, 'GOOS': 'windows', 'GOARCH': 'amd64', 'CGO_ENABLED': '0'}, check=True)
        print(json.dumps(inspect_pe(a.out,a.version), indent=2))
    finally:
        syso.unlink()


if __name__ == '__main__':
    main()
