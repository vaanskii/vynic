#!/usr/bin/env python3
"""Reproducible development-only Windows release lab. Never serves private inputs."""
import argparse
import base64
import contextlib
import datetime as dt
import fcntl
import functools
import hashlib
import http.server
import importlib.util
import ipaddress
import json
import os
import re
import stat
from pathlib import Path
import shutil
import signal
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.parse
import zipfile

REPO = Path(__file__).resolve().parents[3]
EDGE = REPO / 'apps/edge'
sys.dont_write_bytecode = True
CHANNEL = 'local-development'
KEY_ID = 'vynic-local-development-only'
DEFAULT_ROOT = Path.home() / 'VynicLocalReleases'
LAB_IPS = ('10.10.10.3', '172.20.10.2')


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_bytes(data.encode() if isinstance(data, str) else data)
    tmp.replace(path)


def json_write(path, value):
    write(path, json.dumps(value, indent=2) + '\n')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def tree_hash(paths):
    h = hashlib.sha256()
    for root in paths:
        for p in sorted(root.rglob('*')) if root.is_dir() else [root]:
            if not p.is_file() or '.git' in p.parts or p.suffix == '.syso':
                continue
            h.update(str(p.relative_to(REPO)).encode())
            h.update(p.read_bytes())
    return h.hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_pe(raw):
    if len(raw) < 64 or raw[:2] != b'MZ':
        raise ValueError('A real Windows amd64 executable is required')
    off = struct.unpack_from('<I', raw, 60)[0]
    if off + 26 > len(raw) or raw[off:off+4] != b'PE\0\0' or struct.unpack_from('<H', raw, off+4)[0] != 0x8664:
        raise ValueError('Not a Windows amd64 PE executable')


def checked_zip_names(entries, windows_separators=False):
    """Validate the Windows namespace before any archive is read or rewritten."""
    if len(entries) > 20000:
        raise ValueError('Too many ZIP entries')
    seen = set()
    result = []
    total = 0
    for entry in entries:
        raw = entry.orig_filename
        name = raw.replace(chr(92), '/') if windows_separators else raw
        name = name[:-1] if name.endswith('/') else name
        parts = name.split('/')
        mode = entry.external_attr >> 16
        if (not name or any(c in name for c in '\\:<>"|?*') or
                any(ord(c) < 32 for c in name) or
                any(not part or part in ('.', '..') or part.rstrip(' .') != part or
                    re.fullmatch(r'CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]', part.split('.')[0], re.I)
                    for part in parts) or
                stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR) or
                entry.external_attr & 0x400 or entry.flag_bits & 1):
            raise ValueError('Unsafe ZIP path or entry type')
        key = name.casefold()
        if key in seen:
            raise ValueError('Duplicate ZIP path')
        seen.add(key)
        total += entry.file_size
        if total > 1536 * 1024 * 1024:
            raise ValueError('POS ZIP exceeds expanded limit')
        result.append(name + ('/' if raw.endswith(('/', chr(92))) else ''))
    files = {n.casefold() for n in result if not n.endswith('/')}
    for name in result:
        parts = name.rstrip('/').casefold().split('/')
        if any('/'.join(parts[:i]) in files for i in range(1, len(parts))):
            raise ValueError('ZIP file/directory collision')
    return result


def repack_pos(path, state):
    """Explicit local packaging repair; release validators still reject backslashes."""
    temporary = path.with_suffix('.canonical.tmp')
    try:
        with zipfile.ZipFile(path) as source:
            names = checked_zip_names(source.infolist(), windows_separators=True)
            with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as target:
                for entry, name in zip(source.infolist(), names):
                    info = zipfile.ZipInfo(name, entry.date_time)
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = entry.external_attr
                    info.create_system = entry.create_system
                    with source.open(entry) as src, target.open(info, 'w') as dst:
                        shutil.copyfileobj(src, dst)
        pos_receipt(temporary, state)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def pos_receipt(path, state):
    # This local lab accepts only its real Windows source build, not synthetic
    # fixtures, Manager bundles or an old unrelated POS binary.
    with zipfile.ZipFile(path) as z:
        names = set(checked_zip_names(z.infolist()))
        required = {'vynic_pos.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'local-build.json'}
        if not required <= names or not any(n.startswith('data/flutter_assets/') for n in names):
            raise ValueError('Incomplete POS release; use the generated Windows build command')
        info = json.loads(z.read('local-build.json'))
        if info != state['posReceipt']:
            raise ValueError('POS build does not match the prepared current source/version; download the current build-pos.cmd and copy its resulting ZIP. Expected '+json.dumps(state['posReceipt'])+'; received '+json.dumps(info))
        if z.getinfo('vynic_pos.exe').file_size < 65536 or z.getinfo('flutter_windows.dll').file_size < 1024*1024:
            raise ValueError('Synthetic/incomplete Windows binaries refused')
        require_pe(z.read('vynic_pos.exe')[:65536])
        require_pe(z.read('flutter_windows.dll')[:65536])
    return info


def tools(a):
    go = a.go or shutil.which('go')
    if not go and Path('/tmp/vynic-phase1-tools/go/bin/go').is_file():
        go = '/tmp/vynic-phase1-tools/go/bin/go'
    if not go:
        raise RuntimeError('Go 1.26+ required; supply --go /path/to/go')
    openssl = shutil.which('openssl')
    if Path('/opt/homebrew/opt/openssl@3/bin/openssl').is_file():
        openssl = '/opt/homebrew/opt/openssl@3/bin/openssl'
    mkcert = shutil.which('mkcert')
    if not openssl or not mkcert:
        raise RuntimeError('Install mkcert and OpenSSL with Ed25519 support first')
    return go, openssl, mkcert


def environment(a):
    env = dict(os.environ)
    env['GOCACHE'] = str(a.root / 'cache/go-build')
    env['GOPATH'] = env.get('GOPATH', '/tmp/vynic-phase1-tools/gopath' if Path('/tmp/vynic-phase1-tools/gopath').is_dir() else str(a.root/'cache/go'))
    return env


def zip_tree(source, target):
    tmp = target.with_suffix('.tmp')
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(source.rglob('*')):
            if p.is_symlink():
                raise ValueError('Source symlink refused: ' + str(p))
            if p.is_file():
                if p.name.startswith('.env') or p.suffix.lower() in {'.pem', '.key', '.p12', '.pfx', '.jks'}:
                    raise ValueError('Secret-shaped file in public source: ' + str(p))
                info = zipfile.ZipInfo(p.relative_to(source).as_posix(), (2020,1,1,0,0,0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100600 << 16
                z.writestr(info, p.read_bytes())
    tmp.replace(target)


def prepare(a):
    saved = a.root/'state.json'
    if saved.exists():
        state = json.loads(saved.read_text())
        if state.get('posUpdate'):
            if a.api_origin != state['posReceipt']['apiOrigin']:
                raise ValueError('Use prepare-pos-update to change the POS API build configuration')
            write_pos_command(a,state)
            if not state.get('posUpdatePending') or (a.root/'input/vynic-pos.zip').exists():
                publish(a)
            else:
                print('Waiting for the prepared Windows POS update ZIP; use publish after copying it')
            return state
    go, openssl, mkcert = tools(a)
    private, public, inputs = a.root/'private', a.root/'public', a.root/'input'
    for d in [private, public, inputs, a.root/'bin', a.root/'work', a.root/'logs']:
        d.mkdir(parents=True, exist_ok=True)
    ca = Path(run([mkcert, '-CAROOT'], capture_output=True, text=True).stdout.strip())/'rootCA.pem'
    if not ca.is_file():
        raise RuntimeError('mkcert -install must be completed first')
    cert, tlskey = private/'lan.pem', private/'lan-key.pem'
    cert_origin = private/'certificate-origin.txt'
    if not cert.is_file() or not tlskey.is_file() or not cert_origin.is_file() or cert_origin.read_text() != ','.join(sorted(set(LAB_IPS + (a.ip,)))):
        run([mkcert, '-cert-file', cert, '-key-file', tlskey, *sorted(set(LAB_IPS + (a.ip,))), 'localhost', '127.0.0.1'])
        write(cert_origin, ','.join(sorted(set(LAB_IPS + (a.ip,)))))
    tlskey.chmod(0o600)
    shutil.copyfile(ca, public/'rootCA.pem')
    key = private/'release-ed25519.pem'
    if not key.exists():
        run([openssl, 'genpkey', '-algorithm', 'ED25519', '-out', key])
    key.chmod(0o600)
    der = run([openssl, 'pkey', '-in', key, '-pubout', '-outform', 'DER'], capture_output=True).stdout
    if len(der) != 44 or der[:12].hex() != '302a300506032b6570032100':
        raise RuntimeError('Unexpected Ed25519 public key encoding')
    public_key = base64.b64encode(der[12:]).decode()
    distribution_path = public/'distribution.json'
    if distribution_path.exists():
        distribution = json.loads(distribution_path.read_text())
        old = distribution['keys'][KEY_ID]
        if old['public'] != public_key or distribution['bootstrapURL'] != a.origin+'/bootstrap.json':
            raise RuntimeError('Existing lab identity/origin differs; use a new --root')
    else:
        expires = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=180)).isoformat().replace('+00:00','Z')
        distribution = {'bootstrapURL': a.origin+'/bootstrap.json', 'channel': CHANNEL,
                        'keys': {KEY_ID: {'public': public_key, 'expires': expires}}}
        json_write(distribution_path, distribution)
    env = environment(a)
    edge_hash = tree_hash([EDGE/'go.mod', EDGE/'go.sum', EDGE/'cmd', EDGE/'internal', REPO/'packages/contracts/generated/go'])
    cache = a.root/'work/build-cache.json'
    prior = json.loads(cache.read_text()) if cache.exists() else {}
    targets = {'edge': a.root/'work/VynicEdge.exe', 'sign-pos-release': a.root/'bin/sign-pos-release',
               'sign-bootstrap': a.root/'bin/sign-bootstrap', 'verify-local-release': a.root/'bin/verify-local-release'}
    for name, dest in targets.items():
        if prior.get('edgeSource') != edge_hash or not dest.exists():
            build_env = {**env, **({'GOOS':'windows','GOARCH':'amd64','CGO_ENABLED':'0'} if name == 'edge' else {})}
            if name == 'edge':
                run([sys.executable, EDGE/'tool/build-edge-windows.py', '--out', dest, '--go', go], env=build_env)
            else:
                run([go, 'build', '-trimpath', '-o', dest, './cmd/'+name], cwd=EDGE, env=build_env)
    edge_zip = a.root/'work/edge.zip'
    if prior.get('edgeSource') != edge_hash or not edge_zip.exists():
        with zipfile.ZipFile(edge_zip, 'w', zipfile.ZIP_DEFLATED) as z:
            z.write(targets['edge'], 'VynicEdge.exe')
    artifact_dir = public/'artifacts';artifact_dir.mkdir(exist_ok=True)
    edge_name = 'edge-'+digest(edge_zip)+'.zip'
    if not (artifact_dir/edge_name).exists():
        shutil.copyfile(edge_zip, artifact_dir/edge_name)
    setup_path = public/'VynicSetup.exe'
    setup_cache = hashlib.sha256((edge_hash+distribution_path.read_text()).encode()).hexdigest()
    if prior.get('setup') != setup_cache or not setup_path.exists():
        run([sys.executable, EDGE/'tool/build-setup.py', '--distribution', distribution_path, '--out', setup_path, '--go', go], env=env)
    embedded = base64.b64encode(distribution_path.read_bytes())
    if embedded not in setup_path.read_bytes():
        raise RuntimeError('Built Setup does not contain the exact local distribution')
    version, source_hash, source_name = prepare_pos_source(a)
    state = {'origin':a.origin, 'ip':a.ip, 'port':a.port, 'ca':str(ca), 'edgeArtifact':edge_name,
             'edgeVersion':'1.0.0','edgeRelease':1,'posVersion':version,'posRelease':1,
             'posReceipt':{'product':'vynic-pos','version':version,'sourceSha256':source_hash,'environment':'development','apiOrigin':a.api_origin}}
    previous_state = a.root/'state.json'
    if previous_state.exists():
        previous = json.loads(previous_state.read_text())
        if (public/'bootstrap.json').exists() and (previous['edgeArtifact']!=edge_name or previous['posReceipt']!=state['posReceipt']):
            raise RuntimeError('Published lab baseline is immutable; changed Edge/POS source requires a new --root')
        # Existing installed test hosts pin Edge hashes. Never silently change a
        # baseline/repair artifact under the same release number.
        if previous['edgeArtifact'] != edge_name:
            state['edgeRelease'] = previous['edgeRelease']+1
        else:
            state['edgeRelease'] = previous['edgeRelease']
    json_write(previous_state,state)
    expiry = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=7)).isoformat().replace('+00:00','Z')
    json_write(a.root/'work/edge-descriptor.json', {'product':'vynic-edge','version':state['edgeVersion'],
        'release':state['edgeRelease'],'os':'windows','arch':'amd64','channel':CHANNEL,
        'url':a.origin+'/artifacts/'+edge_name,'size':edge_zip.stat().st_size,'sha256':digest(edge_zip),
        'expires':expiry,'updaterProtocol':1,'hiveSchema':9,'edgeSchema':2,'dataPolicy':'edge2-no-migration'})
    write(a.root/'work/SIGNING_PENDING.txt','Edge is authenticated by the signed bootstrap contract. Its descriptor is ready; bootstrap signing requires the real Windows POS envelope. No incomplete bootstrap or fake POS is published.\n')
    write_pos_command(a,state)
    json_write(cache, {'edgeSource':edge_hash,'setup':setup_cache})
    publish(a)
    return state


def prepare_pos_source(a):
    public = a.root/'public'
    # Export a credential-free product-specific source snapshot, including its
    # relative generated Dart contract dependency. Existing source is not edited.
    source = a.root/'work/source'
    if source.exists():
        shutil.rmtree(source)
    module = load_module('vynic_product', REPO/'apps/operations/tool/product.py')
    module.prepare('pos', source/'apps/operations')
    shutil.copytree(REPO/'packages/contracts/generated/edge_dart', source/'packages/contracts/generated/edge_dart', ignore=shutil.ignore_patterns('.dart_tool','build','.packages'))
    version_line = next(x for x in (source/'apps/operations/pubspec.yaml').read_text().splitlines() if x.startswith('version:'))
    version = version_line.split(':',1)[1].strip().split('+')[0]
    source_zip = a.root/'work/pos-source.zip'
    zip_tree(source, source_zip)
    source_hash = digest(source_zip)
    source_name = 'pos-source-'+source_hash+'.zip'
    source_target = public/source_name
    if not source_target.exists():
        shutil.copyfile(source_zip, source_target)
    return version, source_hash, source_name


def write_pos_command(a,state):
    public = a.root/'public'
    inputs = a.root/'input'
    version = state['posVersion']
    source_hash = state['posReceipt']['sourceSha256']
    source_name = 'pos-source-'+source_hash+'.zip'
    receipt_text = base64.b64encode(json.dumps(state['posReceipt'], separators=(',',':')).encode()).decode()
    cmd = f'''@echo off
setlocal
where flutter >nul 2>nul || (echo Install Flutter and Visual Studio Desktop development with C++ first. & exit /b 1)
set "LAB=%LOCALAPPDATA%\\VynicLocalReleaseBuild\\{source_hash[:16]}"
if not exist "%LAB%" mkdir "%LAB%"
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing '{a.origin}/{source_name}' -OutFile (Join-Path $env:LAB 'source.zip'); if ((Get-FileHash (Join-Path $env:LAB 'source.zip') -Algorithm SHA256).Hash.ToLower() -ne '{source_hash}') {{throw 'Source checksum mismatch'}}; Expand-Archive -LiteralPath (Join-Path $env:LAB 'source.zip') -DestinationPath $env:LAB -Force"
if errorlevel 1 exit /b 1
cd /d "%LAB%\\apps\\operations"
call flutter pub get
if errorlevel 1 exit /b 1
call flutter build windows --release --dart-define=VYNIC_ENV=development --dart-define=VYNIC_LOCAL_WINDOWS_LAB=true --dart-define=VYNIC_API_URL={a.api_origin} --build-name={version} --build-number={state.get("posRelease", 1)}
if errorlevel 1 exit /b 1
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $r=Join-Path $env:LAB 'apps\\operations\\build\\windows\\x64\\runner\\Release'; if (!(Test-Path (Join-Path $r 'vynic_pos.exe'))) {{throw 'POS executable missing'}}; [IO.File]::WriteAllBytes((Join-Path $r 'local-build.json'),[Convert]::FromBase64String('{receipt_text}')); Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem; $out=Join-Path $env:USERPROFILE 'Downloads\\vynic-pos.zip'; $tmp=$out+'.tmp'; if (Test-Path $tmp) {{Remove-Item -LiteralPath $tmp}}; $z=[IO.Compression.ZipFile]::Open($tmp,[IO.Compression.ZipArchiveMode]::Create); try {{ Get-ChildItem -LiteralPath $r -Recurse -Force | ForEach-Object {{ if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {{throw 'Reparse point refused'}}; if (!$_.PSIsContainer) {{ $name=$_.FullName.Substring($r.Length+1).Replace([char]92,[char]47); [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$_.FullName,$name,[IO.Compression.CompressionLevel]::Optimal) | Out-Null }} }} }} finally {{$z.Dispose()}}; Move-Item -LiteralPath $tmp -Destination $out -Force"
if errorlevel 1 exit /b 1
echo Copy %USERPROFILE%\\Downloads\\vynic-pos.zip to this Mac: {inputs/'vynic-pos.zip'}
'''
    write(public/'build-pos.cmd',cmd.replace('\n','\r\n'))


def prepare_pos_update(a):
    state = json.loads((a.root/'state.json').read_text())
    if not (a.root/'public/bootstrap.json').exists():
        raise ValueError('Prepare the initial lab first')
    _, source_hash, _ = prepare_pos_source(a)
    if not state.get('posUpdatePending'):
        parts = state['posVersion'].split('.')
        parts[-1] = str(int(parts[-1])+1)
        state['posVersion'] = '.'.join(parts)
        state['posRelease'] += 1
    state['posReceipt'] = {'product':'vynic-pos','version':state['posVersion'],
        'sourceSha256':source_hash,'environment':'development','apiOrigin':a.api_origin}
    state['posUpdatePending'] = True
    state['posUpdate'] = True
    json_write(a.root/'state.json',state)
    write_pos_command(a,state)
    json_write(a.root/'public/status.json',{'state':'WAITING_FOR_REAL_WINDOWS_POS',
        'bootstrapPublished':True,'pendingVersion':state['posVersion'],'apiOrigin':a.api_origin})
    print('Windows rebuild required; existing signed baseline remains available until the new ZIP arrives')

def validate_publication_identity(root, version, release, artifact):
    """An issued version identifies immutable bytes, including manual ZIP uploads.

    Local metadata is only a collision guard here; the existing signers and
    HTTPS verifier still enforce release authenticity and compatibility.
    """
    public = root/'public'
    previous = public/'pos/releases'/f'{version}.json'
    if previous.exists():
        manifest = json.loads(base64.b64decode(json.loads(previous.read_bytes())['payload'], validate=True))
        if (manifest['version'] != version or manifest['release'] != release or
                manifest['sha256'] != digest(artifact) or manifest['size'] != artifact.stat().st_size):
            raise ValueError('Published POS version is immutable; prepare a new POS update/version before publishing changed binaries')
    feed = public/'pos/manifest.json'
    if feed.exists():
        manifest = json.loads(base64.b64decode(json.loads(feed.read_bytes())['payload'], validate=True))
        current = tuple(map(int, manifest['version'].split('.')))
        proposed = tuple(map(int, version.split('.')))
        if (proposed < current or release < manifest['release'] or
                (proposed == current) != (release == manifest['release'])):
            raise ValueError('POS publication would reset the feed; both version and release must increase together')
        if proposed == current and (manifest['sha256'] != digest(artifact) or manifest['size'] != artifact.stat().st_size):
            raise ValueError('Published POS version is immutable; prepare a new POS update/version before publishing changed binaries')


def publish(a):
    state = json.loads((a.root/'state.json').read_text())
    public = a.root/'public'
    pos = a.root/'input/vynic-pos.zip'
    if not pos.exists():
        json_write(public/'status.json', {'state':'WAITING_FOR_REAL_WINDOWS_POS','bootstrapPublished':False,'sourceVersion':state['posVersion']})
        page = '<h1>Vynic local Windows release lab</h1><p>HTTPS ready. Waiting for the real Windows POS build; bootstrap.json is not published yet.</p><p>Use build-pos.cmd on Windows with Flutter and Visual Studio Desktop C++. Copy its ZIP to the Mac input directory. Publishing is automatic.</p><p>Installer/update testing only: the POS build uses the separate local API origin http://10.10.10.3:3000. This release server does not start NestJS; online enrollment needs a development backend.</p>'
        for file in ['rootCA.pem','VynicSetup.exe','build-pos.cmd','distribution.json','status.json']:
            page += f'<p><a href="/{file}">{file}</a></p>'
        write(public/'index.html',page)
        print('WAITING_FOR_REAL_WINDOWS_POS: copy the generated Windows ZIP to '+str(pos))
        return False
    pos_receipt(pos,state)
    validate_publication_identity(a.root, state['posVersion'], state['posRelease'], pos)
    expires = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=7)).isoformat().replace('+00:00','Z')
    version = state['posVersion']
    pos_name = 'pos-'+digest(pos)+'.zip'
    target = public/'artifacts'/pos_name
    if not target.exists():
        shutil.copyfile(pos,target)
    work = a.root/'work'
    common = {'os':'windows','arch':'amd64','channel':CHANNEL,'expires':expires,'updaterProtocol':1,'hiveSchema':9,'edgeSchema':2}
    metadata = {**common,'product':'vynic-pos','version':version,'release':state['posRelease'],'url':state['origin']+'/artifacts/'+pos_name,'dataPolicy':'hive9-no-migration'}
    json_write(work/'pos-metadata.json',metadata)
    pos_signed = run([a.root/'bin/sign-pos-release','--manifest',work/'pos-metadata.json','--artifact',pos,'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID],capture_output=True).stdout
    edge = {**common,'product':'vynic-edge','version':state['edgeVersion'],'release':state['edgeRelease'],'url':state['origin']+'/artifacts/'+state['edgeArtifact'],'dataPolicy':'edge2-no-migration'}
    b = {'product':'vynic-bootstrap','protocol':1,'posBinaryLayout':2,'release':state['edgeRelease'],'os':'windows','arch':'amd64','channel':CHANNEL,'expires':expires,'edge':edge,'pos':json.loads(pos_signed),'posFeed':state['origin']+'/pos/manifest.json','repairBase':state['origin']+'/repair','posReleaseBase':state['origin']+'/pos/releases'}
    json_write(work/'bootstrap-metadata.json',b)
    bootstrap = run([a.root/'bin/sign-bootstrap','--manifest',work/'bootstrap-metadata.json','--edge-artifact',public/'artifacts'/state['edgeArtifact'],'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID,'--distribution',public/'distribution.json'],capture_output=True).stdout
    write(public/'pos/releases'/f'{version}.json',pos_signed)
    write(public/'pos/manifest.json',pos_signed)
    repair_path = public/'repair'/f"{state['edgeRelease']}.json"
    if not state.get('posUpdate') or not repair_path.exists():
        write(repair_path,bootstrap)
    write(public/'bootstrap.json',bootstrap)
    json_write(public/'status.json',{'state':'READY','bootstrapPublished':True,'version':version})
    write(public/'index.html','<h1>Vynic local release lab ready</h1><p>Select the network this Mac is connected to:</p>'+''.join('<p><a href="https://'+ip+':'+str(state['port'])+'/networks/'+ip+'/">'+ip+' — Setup and signed releases</a></p>' for ip in LAB_IPS))
    renew_lab_metadata(a)
    state['posUpdatePending'] = False
    json_write(a.root/'state.json',state)
    publish_networks(a)
    print('Signed real Windows POS and Edge bootstrap published')
    return True


def renew_lab_metadata(a):
    """Renew expiry only; reject changed bytes for an already signed artifact."""
    expires = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=7)).isoformat().replace('+00:00','Z')
    public = a.root/'public'
    work = a.root/'work'
    def payload(raw):
        return json.loads(base64.b64decode(json.loads(raw)['payload'], validate=True))
    def artifact(m):
        path = public/'artifacts'/Path(urllib.parse.urlsplit(m['url']).path).name
        if digest(path) != m['sha256'] or path.stat().st_size != m['size']:
            raise ValueError('Previously signed artifact changed; refusing metadata renewal')
        return path
    def pos(raw):
        m = payload(raw)
        path = artifact(m)
        m['expires'] = expires
        json_write(work/'renew-pos.json',m)
        return run([a.root/'bin/sign-pos-release','--manifest',work/'renew-pos.json','--artifact',path,'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID],capture_output=True).stdout
    for path in (public/'pos/releases').glob('*.json'):
        write(path,pos(path.read_bytes()))
    for path in (public/'repair').glob('*.json'):
        b = payload(path.read_bytes())
        edge_path = artifact(b['edge'])
        b['expires'] = expires
        b['edge']['expires'] = expires
        b['pos'] = json.loads(pos(json.dumps(b['pos'])))
        json_write(work/'renew-bootstrap.json',b)
        signed = run([a.root/'bin/sign-bootstrap','--manifest',work/'renew-bootstrap.json','--edge-artifact',edge_path,'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID,'--distribution',public/'distribution.json'],capture_output=True).stdout
        write(path,signed)


def publish_networks(a, build_setup=False):
    """Same trusted lab key/artifacts; independently signed URLs for each LAN.

    Never rewrite production feeds or change the immutable primary lab origin.
    Existing installed clients require an explicit local network selection.
    """
    state = json.loads((a.root/'state.json').read_text())
    public = a.root/'public'
    base_distribution = json.loads((public/'distribution.json').read_text())
    if base_distribution['channel'] != CHANNEL:
        raise ValueError('Network profiles are development-only')
    if build_setup:
        mkcert = shutil.which('mkcert')
        run([mkcert, '-cert-file', a.root/'private/lan.pem', '-key-file', a.root/'private/lan-key.pem', *LAB_IPS, 'localhost', '127.0.0.1'])
        write(a.root/'private/certificate-origin.txt', ','.join(sorted(LAB_IPS)))
    for ip in LAB_IPS:
        origin = f'https://{ip}:{state["port"]}'
        profile = public/'networks'/ip
        profile_origin = origin+'/networks/'+ip
        distribution = {**base_distribution, 'bootstrapURL': profile_origin+'/bootstrap.json'}
        json_write(profile/'distribution.json', distribution)
        def sign_pos(raw):
            m = json.loads(raw) if isinstance(raw, (bytes,str)) else dict(raw)
            m = json.loads(base64.b64decode(m['payload'], validate=True))
            artifact = public/'artifacts'/Path(urllib.parse.urlsplit(m['url']).path).name
            m['url'] = origin+'/artifacts/'+artifact.name
            json_write(a.root/'work/network-pos.json',m)
            return run([a.root/'bin/sign-pos-release','--manifest',a.root/'work/network-pos.json','--artifact',artifact,'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID],capture_output=True).stdout
        def sign_bootstrap(raw):
            b = json.loads(raw)
            b = json.loads(base64.b64decode(b['payload'], validate=True))
            b['pos'] = json.loads(sign_pos(b['pos']))
            edge = b['edge']; artifact = public/'artifacts'/Path(urllib.parse.urlsplit(edge['url']).path).name
            edge['url'] = origin+'/artifacts/'+artifact.name
            b['posFeed']=profile_origin+'/pos/manifest.json'
            b['repairBase']=profile_origin+'/repair'
            b['posReleaseBase']=profile_origin+'/pos/releases'
            json_write(a.root/'work/network-bootstrap.json',b)
            return run([a.root/'bin/sign-bootstrap','--manifest',a.root/'work/network-bootstrap.json','--edge-artifact',artifact,'--private-key',a.root/'private/release-ed25519.pem','--key-id',KEY_ID,'--distribution',profile/'distribution.json'],capture_output=True).stdout
        for path in (public/'pos/releases').glob('*.json'):
            write(profile/'pos/releases'/path.name,sign_pos(path.read_bytes()))
        write(profile/'pos/manifest.json',sign_pos((public/'pos/manifest.json').read_bytes()))
        for path in (public/'repair').glob('*.json'):
            write(profile/'repair'/path.name,sign_bootstrap(path.read_bytes()))
        write(profile/'bootstrap.json',sign_bootstrap((public/'bootstrap.json').read_bytes()))
        if build_setup:
            go = a.go or shutil.which('go') or '/tmp/vynic-phase1-tools/go/bin/go'
            run([sys.executable, EDGE/'tool/build-setup.py','--distribution',profile/'distribution.json','--out',profile/'VynicSetup.exe','--go',go,'--version','1.0.7.0'],env=environment(a))
        write(profile/'index.html','<h1>Vynic development lab</h1><p>'+ip+'</p><p><a href="bootstrap.json">Signed bootstrap</a></p><p><a href="VynicSetup.exe">VynicSetup.exe</a></p>')
    write(public/'networks/index.html', '<h1>Vynic development networks</h1>'+''.join('<p><a href="https://'+ip+':'+str(state['port'])+'/networks/'+ip+'/">'+ip+'</a></p>' for ip in LAB_IPS))
    print('Published signed network profiles: '+', '.join(LAB_IPS))


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self,path):
        resolved = Path(super().translate_path(path)).resolve()
        root = Path(self.directory).resolve()
        if resolved != root and root not in resolved.parents:
            return str(root/'not-found')
        return str(resolved)
    def list_directory(self,path):
        self.send_error(403,'Directory listing disabled');return None
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        super().end_headers()


def network_profile(a):
    state = json.loads((a.root/'state.json').read_text())
    if a.origin == state['origin']:
        return a.root/'public', a.origin
    profile = a.root/'public/networks'/a.ip
    if a.ip not in LAB_IPS or not (profile/'distribution.json').is_file():
        raise ValueError('Generate the registered LAN profiles with networks first')
    return profile, a.origin+'/networks/'+a.ip


def verify(a):
    state=json.loads((a.root/'state.json').read_text())
    context=ssl.create_default_context(cafile=state['ca'])
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
    profile, profile_origin = network_profile(a)
    for name in ['status.json','rootCA.pem','build-pos.cmd','artifacts/'+state['edgeArtifact']]:
        with opener.open(a.origin+'/'+name,timeout=30) as r:
            content=r.read()
        if content != (a.root/'public'/name).read_bytes():
            raise RuntimeError('HTTPS content mismatch: '+name)
    for name in ['distribution.json', 'VynicSetup.exe']:
        with opener.open(profile_origin+'/'+name, timeout=30) as r:
            if r.read() != (profile/name).read_bytes():
                raise RuntimeError('HTTPS network profile mismatch: '+name)
    if (profile/'bootstrap.json').exists():
        run([a.root/'bin/verify-local-release','--distribution',profile/'distribution.json','--ca',state['ca']])
    else:
        print('TLS, local distribution embedded in Setup, Edge ZIP and download URLs verified; bootstrap/POS verification awaits real Windows POS')


def serve(a):
    state=json.loads((a.root/'state.json').read_text())
    server=http.server.ThreadingHTTPServer(('0.0.0.0',state['port']),functools.partial(Handler,directory=str(a.root/'public')))
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(a.root/'private/lan.pem',a.root/'private/lan-key.pem')
    server.socket=context.wrap_socket(server.socket,server_side=True)
    def watch():
        observed=None;stable=0;published=None
        while True:
            time.sleep(5)
            path=a.root/'input/vynic-pos.zip'
            if not path.exists():continue
            current=(path.stat().st_size,path.stat().st_mtime_ns)
            stable=stable+1 if current==observed else 0;observed=current
            if stable<2 or current==published:continue
            try:
                with lab_lock(a.root):
                    if publish(a):verify(a)
                published=current
            except Exception as e:
                print('POS publish/verification refused: '+str(e),flush=True)
                published=current
    threading.Thread(target=watch,daemon=True).start()
    print('HTTPS serving only '+str(a.root/'public')+' on '+state['origin'],flush=True)
    server.serve_forever()


@contextlib.contextmanager
def lab_lock(root):
    with (root/'lab.lock').open('a') as f:
        fcntl.flock(f,fcntl.LOCK_EX);yield


def verify_https_server(a):
    state=json.loads((a.root/'state.json').read_text())
    context=ssl.create_default_context(cafile=state['ca'])
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
    with opener.open(a.origin+'/rootCA.pem',timeout=30) as response:
        if response.read() != (a.root/'public/rootCA.pem').read_bytes():
            raise RuntimeError('HTTPS server does not match this lab')


def start(a, verify_release=True):
    check = verify if verify_release else verify_https_server
    state=json.loads((a.root/'state.json').read_text())
    pidpath=a.root/'server.pid'
    if pidpath.exists():
        pid=int(pidpath.read_text())
        try:os.kill(pid,0)
        except ProcessLookupError:pidpath.unlink()
        else:
            check(a);return
    log=(a.root/'logs/https.log').open('ab')
    p=subprocess.Popen([sys.executable,'-u',__file__,'serve','--root',str(a.root),'--ip',a.ip,'--port',str(a.port)],stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True)
    log.close();write(pidpath,str(p.pid))
    for _ in range(30):
        if p.poll() is not None:
            pidpath.unlink(missing_ok=True);raise RuntimeError('HTTPS server failed; inspect logs/https.log')
        try:check(a);return
        except (OSError,urllib.error.URLError):time.sleep(.3)
    raise RuntimeError('HTTPS startup timed out; inspect logs/https.log')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',nargs='?',choices=['run','prepare','publish','start','verify','serve','prepare-pos-update','networks'],default='run')
    p.add_argument('--root',type=Path,default=DEFAULT_ROOT)
    p.add_argument('--ip',default='10.10.10.3');p.add_argument('--port',type=int,default=8443)
    p.add_argument('--api-origin',help='Separate test NestJS origin; registered LAN IPs default to HTTP port 3000; this tool does not start a backend')
    p.add_argument('--go')
    a=p.parse_args();a.root=a.root.expanduser().resolve()
    if a.root==REPO or REPO in a.root.parents or a.root==Path('/') or a.root==Path.home():p.error('Use a dedicated directory outside the repository/home root')
    if not ipaddress.ip_address(a.ip).is_private:p.error('Only a private LAN IP is allowed')
    a.origin=f'https://{a.ip}:{a.port}'
    if a.api_origin is None:
        if a.ip not in LAB_IPS:
            p.error('Supply an explicit private HTTPS --api-origin for an unregistered LAN')
        a.api_origin = f'http://{a.ip}:3000'
    api = urllib.parse.urlsplit(a.api_origin)
    try:
        local_api = api.hostname=='localhost' or ipaddress.ip_address(api.hostname).is_private
    except ValueError:
        local_api = False
    if (api.scheme!='https' and a.api_origin not in {f'http://{ip}:3000' for ip in LAB_IPS}) or not local_api or api.username or api.password or api.query or api.fragment or api.path not in ('','/'):
        p.error('Use a private HTTPS API origin or a registered local Windows lab HTTP origin on port 3000')
    if not 1024<=a.port<=65535:p.error('Use an unprivileged TCP port')
    os.umask(0o077)
    marker=a.root/'.vynic-local-release-lab'
    if a.root.exists() and not marker.exists() and any(a.root.iterdir()):p.error('Refusing an existing non-lab directory')
    a.root.mkdir(parents=True,exist_ok=True);marker.touch()
    if a.action=='serve':serve(a);return
    if a.action in ['run','prepare']:
        with lab_lock(a.root):prepare(a)
    elif a.action=='prepare-pos-update':
        with lab_lock(a.root):prepare_pos_update(a)
    elif a.action=='networks':
        with lab_lock(a.root):publish_networks(a, build_setup=True)
    elif a.action=='publish':
        with lab_lock(a.root):publish(a)
    if a.action in ['run','start']:start(a)
    elif a.action=='verify':verify(a)
    if a.action!='serve':
        status=json.loads((a.root/'public/status.json').read_text()) if (a.root/'public/status.json').exists() else {}
        print('Mac release publication: '+json.dumps(status)+'; Windows installs change only after explicit Update Now.')
    print(json.dumps({'releaseRoot':str(a.root),'httpsURL':a.origin,'setup':str(network_profile(a)[0]/'VynicSetup.exe'),'ca':str(a.root/'public/rootCA.pem'),'posInput':str(a.root/'input/vynic-pos.zip')},indent=2))

if __name__=='__main__':
    try:main()
    except Exception as e:
        print('Local release lab failed: '+str(e),file=sys.stderr);sys.exit(1)
