#!/usr/bin/env python3
"""One-command POS publication for the existing local HTTPS lab and Windows VM.

Never installs POS, replaces Edge, or transfers release keys to Windows.
"""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import uuid
from types import SimpleNamespace

import local_windows_release_test as lab


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def shared_path(path):
    relative = path.resolve().relative_to(Path.home().resolve())
    return '\\\\Mac\\Home\\' + str(relative).replace('/', '\\')


def select_ip(requested):
    if requested:
        if requested not in lab.LAB_IPS:
            raise ValueError('Use a registered local lab IP: ' + ', '.join(lab.LAB_IPS))
        return requested
    available = []
    for ip in lab.LAB_IPS:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind((ip, 0))
                available.append(ip)
            except OSError:
                pass
    if len(available) != 1:
        raise ValueError('Cannot select one lab network; use --ip 10.10.10.3 or --ip 172.20.10.2 on that LAN')
    return available[0]


def validate_root(root):
    root = root.expanduser().resolve()
    if root == Path.home() or root == lab.REPO or lab.REPO in root.parents:
        raise ValueError('Use the existing dedicated external local release lab')
    shared_path(root)  # This automation uses Parallels Mac Home sharing.
    if not (root/'.vynic-local-release-lab').is_file():
        raise ValueError('Initialize the local release lab first; no existing lab marker found')
    distribution = json.loads((root/'public/distribution.json').read_text())
    if distribution.get('channel') != lab.CHANNEL:
        raise ValueError('Only the local-development distribution is allowed')
    state = json.loads((root/'state.json').read_text())
    if state.get('origin') not in {f'https://{ip}:{state["port"]}' for ip in lab.LAB_IPS}:
        raise ValueError('Unregistered release origin')
    for name in ('sign-pos-release', 'sign-bootstrap', 'verify-local-release'):
        if not (root/'bin'/name).is_file():
            raise ValueError('Missing local signing/verification tools; prepare the lab first')
    return root, state


@contextlib.contextmanager
def publication_lock(root):
    with (root/'publish-pos.lock').open('a') as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('A local POS publication is already running') from error
        yield


def ensure_vm(prlctl, vm):
    machines = json.loads(subprocess.check_output([prlctl, 'list', '-a', '-j'], text=True, timeout=20))
    match = next((m for m in machines if m['name'] == vm or m['uuid'] == vm), None)
    if match is None:
        raise ValueError(f'Windows VM {vm!r} not found; select it with --vm')
    if match['status'] in ('stopped', 'suspended'):
        print('Starting Windows build VM…', flush=True)
        subprocess.run([prlctl, 'start', vm], check=True, timeout=120)
    elif match['status'] != 'running':
        raise ValueError('Resume and sign into the Windows VM before publishing')


def guest(prlctl, vm, script, log, timeout=60):
    # Scripts are local developer build tooling, not downloaded installer runtime.
    # A named Windows mutex prevents overlapping guest builds after interruption.
    command = [prlctl, 'exec', vm, '--current-user', 'powershell.exe',
               '-NoProfile', '-NonInteractive', '-Command', script]
    with log.open('ab') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        started = time.monotonic()
        next_report = started + 15
        try:
            while process.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > timeout:
                    raise TimeoutError(f'Windows build step exceeded {timeout}s; see {log}')
                if time.monotonic() >= next_report:
                    print(f'  Windows build step running ({int(elapsed)}s); log: {log}', flush=True)
                    next_report += 15
                time.sleep(.25)
            if process.returncode:
                raise RuntimeError(f'Windows build step failed (exit {process.returncode}); see {log}')
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            # Only the prlctl client is terminated; never stop POS/Edge/VM.
            raise


def flutter_resolution():
    return r"""
$flutter = Get-Command flutter.bat -ErrorAction SilentlyContinue
if ($flutter) { $flutterPath = $flutter.Source } else {
  $flutterPath = Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
}
if (!(Test-Path -LiteralPath $flutterPath -PathType Leaf)) {
  throw 'Flutter not found. Add Flutter bin to the Windows user PATH.'
}
$env:PATH = (Split-Path -Parent $flutterPath) + ';' + $env:PATH
"""


def sdk_cache_resolution():
    # Firebase's own CMake script validates the SDK version before reusing it.
    # Reuse only previously extracted local build dependencies, never POS binaries.
    return r"""
if (!$env:FIREBASE_CPP_SDK_DIR -or !(Test-Path (Join-Path $env:FIREBASE_CPP_SDK_DIR 'include\firebase\version.h'))) {
  $pattern = Join-Path $env:LOCALAPPDATA 'VynicLocalReleaseBuild\*\apps\operations\build\windows\x64\extracted\firebase_cpp_sdk_windows\include\firebase\version.h'
  $cached = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($cached) {
    $env:FIREBASE_CPP_SDK_DIR = $cached.Directory.Parent.Parent.FullName
    Write-Output ('Reusing local Firebase SDK; CMake will verify its version: '+$env:FIREBASE_CPP_SDK_DIR)
  }
}
"""


def build_script(origin, command_hash, transfer, run_id):
    return r"""$ErrorActionPreference='Stop'
$mutex = New-Object System.Threading.Mutex($false, 'Local\VynicLocalPOSPublisher')
$owned = $false
try {
  try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
  if (!$owned) { throw 'Another local Windows POS build is still running' }
""" + flutter_resolution() + sdk_cache_resolution() + f"""
  $job = Join-Path $env:TEMP {ps_quote('VynicPublish-'+run_id)}
  New-Item -ItemType Directory -Path $job -Force | Out-Null
  $cmd = Join-Path $job 'build-pos.cmd'
  Invoke-WebRequest -UseBasicParsing {ps_quote(origin+'/build-pos.cmd')} -OutFile $cmd
  if ((Get-FileHash -LiteralPath $cmd -Algorithm SHA256).Hash.ToLower() -ne {ps_quote(command_hash)}) {{ throw 'Build command changed; retry publication' }}
  & $cmd
  if ($LASTEXITCODE -ne 0) {{ throw ('POS build failed: '+$LASTEXITCODE) }}
  Copy-Item -LiteralPath (Join-Path $env:USERPROFILE 'Downloads\\vynic-pos.zip') -Destination {ps_quote(transfer)} -Force
  Remove-Item -LiteralPath $job -Recurse -Force
}} finally {{
  if ($owned) {{ $mutex.ReleaseMutex() }}
  $mutex.Dispose()
}}
"""


def accept_bundle(a, incoming, expected):
    # Verify before making it visible to the existing release watcher/signers.
    current = json.loads((a.root/'state.json').read_text())
    for key in ('posVersion', 'posRelease', 'posReceipt'):
        if current[key] != expected[key]:
            raise RuntimeError('Prepared release changed during the build; nothing published')
    lab.pos_receipt(incoming, expected)
    with incoming.open('rb') as f:
        os.fsync(f.fileno())
    os.replace(incoming, a.root/'input/vynic-pos.zip')


def publish_local(a, prlctl, vm):
    with publication_lock(a.root), lab.lab_lock(a.root):
        log = a.root/'logs'/('publish-pos-'+time.strftime('%Y%m%d-%H%M%S')+'.log')
        print(f'[1/5] Checking Windows build tools and local HTTPS. Log: {log}', flush=True)
        ensure_vm(prlctl, vm)
        guest(prlctl, vm, "$ErrorActionPreference='Stop'; " + flutter_resolution() +
              f"\nif (!(Test-Path -LiteralPath {ps_quote(shared_path(a.root/'input'))})) {{ throw 'Enable Parallels Mac Home folder sharing' }}\n& $flutterPath --version; exit $LASTEXITCODE", log)
        lab.start(a, verify_release=False)
        state = json.loads((a.root/'state.json').read_text())
        _, source_hash, _ = lab.prepare_pos_source(a)
        receipt = state.get('posReceipt', {})
        if not state.get('posUpdatePending') and receipt.get('sourceSha256') == source_hash and receipt.get('apiOrigin') == a.api_origin:
            print(f'POS {state["posVersion"]} already contains this source; renewing/verifying the existing release.', flush=True)
            lab.pos_receipt(a.root/'input/vynic-pos.zip', state)
            lab.publish(a)
            lab.verify(a)
            return state
        print('[2/5] Preparing versioned POS source snapshot.', flush=True)
        lab.prepare_pos_update(a)
        state = json.loads((a.root/'state.json').read_text())
        run_id = uuid.uuid4().hex
        incoming = a.root/'input'/f'.pos-{run_id}.incoming'
        print(f'[3/5] Building Windows POS {state["posVersion"]} / release {state["posRelease"]}.', flush=True)
        try:
            guest(prlctl, vm, build_script(a.origin, lab.digest(a.root/'public/build-pos.cmd'),
                                         shared_path(incoming), run_id), log, timeout=1800)
            print('[4/5] Validating Windows ZIP and publishing signed feeds.', flush=True)
            accept_bundle(a, incoming, state)
            if not lab.publish(a):
                raise RuntimeError('Publication did not produce a release')
            print('[5/5] Verifying signed HTTPS metadata and artifact downloads.', flush=True)
            lab.verify(a)
        finally:
            incoming.unlink(missing_ok=True)
        return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=lab.DEFAULT_ROOT)
    parser.add_argument('--ip', choices=lab.LAB_IPS, help='Defaults to the one registered IP present on this Mac')
    parser.add_argument('--vm', default='Windows 11')
    args = parser.parse_args()
    os.umask(0o077)
    root, state = validate_root(args.root)
    ip = select_ip(args.ip)
    prlctl = shutil.which('prlctl') or '/usr/local/bin/prlctl'
    if not Path(prlctl).is_file():
        raise ValueError('Parallels Desktop with prlctl is required on this Mac')
    a = SimpleNamespace(root=root, ip=ip, port=state['port'],
                        origin=f'https://{ip}:{state["port"]}', api_origin=f'http://{ip}:3000')
    result = publish_local(a, prlctl, args.vm)
    print(f'READY: POS {result["posVersion"]} / release {result["posRelease"]} published at {a.origin}', flush=True)
    print('Windows POS → პროგრამის შესახებ → შემოწმება → განახლება ახლა. Nothing was installed automatically.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f'Local POS publication stopped: {error or "cancelled"}. Retry the same command; do not install an unverified bundle.', file=sys.stderr)
        sys.exit(1)
