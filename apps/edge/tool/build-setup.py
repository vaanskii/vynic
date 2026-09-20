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
from urllib.parse import urlparse

MANIFEST = b'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<assemblyIdentity version="1.0.0.0" processorArchitecture="amd64" name="Vynic.Setup" type="win32"/>
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
<requestedExecutionLevel level="asInvoker" uiAccess="false"/>
</requestedPrivileges></security></trustInfo>
<compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application>
<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
</application></compatibility>
</assembly>'''


def resource(payload):
    directory = struct.pack('<IIHHHH', 0, 0, 0, 0, 0, 1)
    data = (directory + struct.pack('<II', 24, 0x80000000 | 24)
            + directory + struct.pack('<II', 1, 0x80000000 | 48)
            + directory + struct.pack('<II', 1033, 72)
            + struct.pack('<IIII', 88, len(payload), 0, 0) + payload)
    header = struct.pack('<HHIIIHH', 0x8664, 1, 0, 60 + len(data) + 10, 1, 0, 0)
    section = struct.pack('<8sIIIIIIHHI', b'.rsrc', 0, 0, len(data), 60,
                          60 + len(data), 0, 1, 0, 0x40000040)
    reloc = struct.pack('<IIH', 72, 0, 3)  # IMAGE_REL_AMD64_ADDR32NB
    symbol = struct.pack('<8sIhHBB', b'.rsrc', 0, 1, 0, 3, 0)
    return header + section + data + reloc + symbol + struct.pack('<I', 4)


def inspect_pe(path):
    image = Path(path).read_bytes()
    pe = struct.unpack_from('<I', image, 60)[0]
    assert image[pe:pe + 4] == b'PE\0\0', 'not PE'
    machine, count = struct.unpack_from('<HH', image, pe + 4)
    optional_size = struct.unpack_from('<H', image, pe + 20)[0]
    optional = pe + 24
    assert machine == 0x8664 and struct.unpack_from('<H', image, optional)[0] == 0x20b
    assert struct.unpack_from('<H', image, optional + 68)[0] == 2, 'not GUI subsystem'
    resource_rva, resource_size = struct.unpack_from('<II', image, optional + 112 + 16)
    assert resource_rva and resource_size, 'missing embedded manifest'
    sections = optional + optional_size
    for n in range(count):
        section = sections + n * 40
        virtual_size, rva, raw_size, offset = struct.unpack_from('<IIII', image, section + 8)
        if rva <= resource_rva < rva + max(virtual_size, raw_size):
            data = image[offset + resource_rva - rva:offset + raw_size]
            assert struct.unpack_from('<II', data, 16) == (24, 0x80000018)
            manifest_rva, size = struct.unpack_from('<II', data, 72)
            manifest = image[offset + manifest_rva - rva:offset + manifest_rva - rva + size]
            assert manifest == MANIFEST, 'resource relocation or manifest mismatch'
            return {'machine': 'windows/amd64', 'subsystem': 'GUI',
                    'executionLevel': 'asInvoker', 'bytes': len(image),
                    'authenticode': 'separate signing/Windows verification required'}
    raise AssertionError('resource section missing')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--distribution', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--go', default='go')
    a = p.parse_args()
    raw = a.distribution.read_bytes()
    d = json.loads(raw)
    if not d.get('bootstrapURL', '').startswith('https://') or not d.get('keys') or not d.get('channel'):
        p.error('distribution requires HTTPS bootstrapURL, channel and public keys')
    if set(d) != {'bootstrapURL', 'channel', 'keys'}:
        p.error('unexpected distribution fields; do not include secrets')
    endpoint = urlparse(d['bootstrapURL'])
    if not endpoint.netloc or endpoint.username or endpoint.fragment:
        p.error('bootstrap endpoint must have a host and no embedded credentials/fragment')
    for key_id, key in d['keys'].items():
        if not key_id or set(key) != {'public', 'expires'}:
            p.error('trusted keys contain only public and expires; never supply private keys')
        try:
            public = base64.b64decode(key['public'], validate=True)
        except (ValueError, TypeError):
            p.error('trusted public key must be base64')
        if len(public) != 32:
            p.error('Ed25519 public key must be 32 bytes')
    root = Path(__file__).resolve().parents[1]
    syso = root / 'cmd/setup/manifest_windows_amd64.syso'
    if syso.exists():
        p.error('manifest resource already exists; preserve it and inspect')
    syso.write_bytes(resource(MANIFEST))
    try:
        subprocess.run([a.go, 'build', '-trimpath', '-ldflags',
                        '-s -w -H=windowsgui -X main.distributionBase64=' + base64.b64encode(raw).decode(),
                        '-o', str(a.out.resolve()), './cmd/setup'], cwd=root,
                       env={**os.environ, 'GOOS': 'windows', 'GOARCH': 'amd64', 'CGO_ENABLED': '0'}, check=True)
        print(json.dumps(inspect_pe(a.out), indent=2))
    finally:
        syso.unlink()


if __name__ == '__main__':
    main()
