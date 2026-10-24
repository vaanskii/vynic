#!/usr/bin/env python3
"""Explicit release-engineering operation; never invoked by Setup or Edge.
Use a current-user Windows certificate store/HSM-backed code-signing certificate.
Sign payload binaries before ZIP packaging and Ed25519/SHA-256 manifest generation;
build and sign Setup afterward. No certificates, credentials or uploads are created.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit
from windows_pe import inspect, version_strings

PRODUCTS = {'VynicSetup.exe': 'Vynic Setup', 'VynicEdge.exe': 'Vynic Edge', 'vynic_pos.exe': 'Vynic POS'}
STAGES = {'all': set(PRODUCTS), 'payload': {'VynicEdge.exe', 'vynic_pos.exe'}, 'setup': {'VynicSetup.exe'}}


def validate_inputs(files, signtool, thumbprint, timestamp, stage='all', verify_only=False):
    if not signtool.is_absolute() or signtool.name.lower() != 'signtool.exe' or not signtool.is_file():
        raise ValueError('Provide the absolute Windows SDK signtool.exe path')
    if not re.fullmatch('[0-9a-fA-F]{40}', thumbprint):
        raise ValueError('Provide the external current-user code-signing certificate SHA-1 thumbprint')
    if not verify_only:
        u = urlsplit(timestamp or '')
        if u.scheme != 'https' or not u.hostname or u.username is not None or u.fragment:
            raise ValueError('An HTTPS RFC3161 timestamp service is required')
    expected_files = STAGES[stage]
    if {p.name for p in files} != expected_files or len(files) != len(expected_files):
        raise ValueError('Supply exactly these stage binaries: ' + ', '.join(sorted(expected_files)))
    for p in files:
        if not p.is_absolute() or not p.is_file() or p.is_symlink():
            raise ValueError('Fixed absolute regular binary paths required')
        pe = inspect(p)
        fields = version_strings(pe['resources'].get((16, 1, 1033), b''))
        expected = {'CompanyName': 'Vynic', 'ProductName': PRODUCTS[p.name],
                    'FileDescription': PRODUCTS[p.name], 'OriginalFilename': p.name}
        if any(fields.get(k) != v for k, v in expected.items()):
            raise ValueError(f'{p.name}: mismatched PE product identity')
        if not fields.get('FileVersion') or not fields.get('ProductVersion'):
            raise ValueError('Missing PE version')


def check_signature(details, thumbprint):
    if (not isinstance(details, dict) or details.get('status') != 'Valid'
            or details.get('type') != 'Authenticode'
            or not isinstance(details.get('thumbprint'), str)
            or details['thumbprint'].upper() != thumbprint.upper()
            or not details.get('subject') or not details.get('timestampThumbprint')):
        raise ValueError('Expected embedded publisher signature and trusted timestamp were not verified')
    return details


def verify_signature(file, signtool, thumbprint, powershell):
    # /tw yields warning exit 2 for an absent timestamp. check=True refuses it.
    # No catalog fallback: verify the embedded signature on the distributable.
    subprocess.run([str(signtool), 'verify', '/pa', '/all', '/tw', '/v', str(file)], check=True)
    # Read-only Windows certificate inspection in release tooling, never in Setup
    # or Edge. Pass the path as data; no interpolation or execution-policy bypass.
    script = """
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$signature = Get-AuthenticodeSignature -LiteralPath $env:VYNIC_RELEASE_VERIFY_FILE
[ordered]@{
  status = [string]$signature.Status
  type = [string]$signature.SignatureType
  thumbprint = $signature.SignerCertificate.Thumbprint
  subject = $signature.SignerCertificate.Subject
  timestampThumbprint = $signature.TimeStamperCertificate.Thumbprint
} | ConvertTo-Json -Compress
"""
    result = subprocess.run([str(powershell), '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
                            env={**os.environ, 'VYNIC_RELEASE_VERIFY_FILE': str(file)},
                            check=True, capture_output=True, encoding='utf-8')
    return check_signature(json.loads(result.stdout.lstrip('\ufeff')), thumbprint)


def process_files(files, signtool, thumbprint, timestamp, powershell, verify_only=False):
    report = []
    for file in files:
        if not verify_only:
            subprocess.run([str(signtool), 'sign', '/s', 'My', '/sha1', thumbprint, '/fd', 'SHA256',
                            '/tr', timestamp, '/td', 'SHA256', '/d', PRODUCTS[file.name], str(file)], check=True)
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        details = verify_signature(file, signtool, thumbprint, powershell)
        if hashlib.sha256(file.read_bytes()).hexdigest() != digest:
            raise ValueError('Binary changed during publisher verification: ' + file.name)
        report.append({'file': str(file), 'product': PRODUCTS[file.name], 'sha256': digest,
                       'certificateThumbprint': details['thumbprint'].upper(),
                       'publisherSubject': details['subject'],
                       'timestampCertificateThumbprint': details['timestampThumbprint'],
                       'operation': 'verify' if verify_only else 'sign-and-verify'})
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--signtool', type=Path, required=True)
    p.add_argument('--thumbprint', required=True)
    p.add_argument('--timestamp-url', help='Approved HTTPS RFC3161 service; required when signing')
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--stage', choices=STAGES, default='all', help='Sign payload first, then build and sign Setup')
    p.add_argument('--verify-only', action='store_true', help='Verify existing bytes without accessing a signing key')
    p.add_argument('files', type=Path, nargs='+')
    a = p.parse_args()
    if os.name != 'nt':
        p.error('Authenticode signing requires the Windows release host')
    validate_inputs(a.files, a.signtool, a.thumbprint, a.timestamp_url, a.stage, a.verify_only)
    powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    if not powershell.is_file():
        p.error('Windows PowerShell certificate inspection is required')
    if a.report.exists() or a.report.is_symlink():
        p.error('Use a new report path; existing release evidence is preserved')
    if not a.report.parent.is_dir():
        p.error('Report directory must already exist')
    report = process_files(a.files, a.signtool, a.thumbprint, a.timestamp_url, powershell, a.verify_only)
    with a.report.open('x', encoding='utf-8') as output:
        output.write(json.dumps(report, indent=2) + '\n')
    print('Selected binaries verified against the expected publisher and timestamp. '
          'Use these exact bytes; this does not publish or establish SmartScreen reputation.')


if __name__ == '__main__':
    main()
