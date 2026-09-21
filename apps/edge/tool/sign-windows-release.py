#!/usr/bin/env python3
"""Explicit release-engineering operation; never invoked by Setup or Edge.
Use a current-user Windows certificate store/HSM-backed code-signing certificate.
Sign binaries before ZIP packaging and Ed25519/SHA-256 manifest generation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit
from windows_pe import inspect,version_strings

PRODUCTS={'VynicSetup.exe':'Vynic Setup','VynicEdge.exe':'Vynic Edge','vynic_pos.exe':'Vynic POS'}


def validate_inputs(files, signtool, thumbprint, timestamp):
    if not signtool.is_absolute() or signtool.name.lower()!='signtool.exe' or not signtool.is_file():
        raise ValueError('Provide the absolute Windows SDK signtool.exe path')
    if not re.fullmatch('[0-9a-fA-F]{40}',thumbprint):
        raise ValueError('Provide the external current-user code-signing certificate SHA-1 thumbprint')
    u=urlsplit(timestamp)
    if u.scheme!='https' or not u.hostname or u.username or u.fragment:
        raise ValueError('An HTTPS RFC3161 timestamp service is required')
    if {p.name for p in files}!=set(PRODUCTS) or len(files)!=3:
        raise ValueError('Supply exactly VynicSetup.exe, VynicEdge.exe and vynic_pos.exe')
    for p in files:
        if not p.is_absolute() or not p.is_file() or p.is_symlink():raise ValueError('Fixed absolute regular binary paths required')
        pe=inspect(p)
        version=pe['resources'].get((16,1,1033),b'')
        fields=version_strings(version)
        expected={'CompanyName':'Vynic','ProductName':PRODUCTS[p.name],
                  'FileDescription':PRODUCTS[p.name],'OriginalFilename':p.name}
        if any(fields.get(k)!=v for k,v in expected.items()):raise ValueError(f'{p.name}: mismatched PE product identity')
        if not fields.get('FileVersion') or not fields.get('ProductVersion'):raise ValueError('Missing PE version')



def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--signtool',type=Path,required=True)
    p.add_argument('--thumbprint',required=True)
    p.add_argument('--timestamp-url',required=True)
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('files',type=Path,nargs=3)
    a=p.parse_args()
    if os.name!='nt':p.error('Authenticode signing requires the Windows release host')
    validate_inputs(a.files,a.signtool,a.thumbprint,a.timestamp_url)
    report=[]
    for file in a.files:
        subprocess.run([str(a.signtool),'sign','/s','My','/sha1',a.thumbprint,'/fd','SHA256','/tr',a.timestamp_url,'/td','SHA256','/d',PRODUCTS[file.name],str(file)],check=True)
        subprocess.run([str(a.signtool),'verify','/pa','/all','/v',str(file)],check=True)
        report.append({'file':str(file),'product':PRODUCTS[file.name],'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'certificateThumbprint':a.thumbprint.upper()})
    a.report.write_text(json.dumps(report,indent=2)+'\n')
    print('All three binaries signed and verified. Package these exact bytes, then sign the release manifests.')

if __name__=='__main__':main()
