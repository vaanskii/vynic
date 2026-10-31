#!/usr/bin/env python3
"""Build unsigned Windows candidate inputs. Never signs, uploads or activates.

Hosted Windows builds are not ordinary-user installer acceptance. The separate
asInvoker core harness and real enrollment/lifecycle acceptance remain required.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

from windows_distribution import unique_object, validate as validate_distribution
from windows_pe import inspect, version_strings

ROOT = Path(__file__).resolve().parents[3]
POLICY = 'docs/release-ci/windows/public-policy.json'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def semver(value):
    require(isinstance(value, str) and re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value),
            'A numeric three-part version is required')
    parts = tuple(map(int, value.split('.')))
    require(max(parts) <= 65535, 'Version exceeds Windows PE component limits')
    return parts


def validate_request(policy, sha, version, build):
    require(re.fullmatch(r'[0-9a-f]{40}', sha or ''), 'An exact reviewed source SHA is required')
    require(set(policy) == {'schema', 'channel', 'apiOrigin', 'licensePublicKey', 'distribution',
                           'minimumPreviousVersion', 'minimumPreviousBuild', 'flutterVersion',
                           'flutterRevision', 'goVersion', 'pythonVersion'}, 'Unknown release policy fields')
    require(policy['schema'] == 1 and policy['channel'] == 'beta'
            and policy['apiOrigin'] == 'https://api.vynic.ge', 'Unexpected beta/API policy')
    require(semver(version) > semver(policy['minimumPreviousVersion']),
            'POS updater requires a strictly newer version, not only a higher build')
    require(type(build) is int and type(policy['minimumPreviousBuild']) is int
            and policy['minimumPreviousBuild'] < build <= 65535, 'A newer bounded build number is required')
    key = base64.b64decode(policy['licensePublicKey'], validate=True)
    require(len(key) == 32 and key != bytes(32), 'A real public licensing pin is required')
    d = validate_distribution(json.dumps(policy['distribution']).encode(), production=True)
    require(d['channel'] == 'beta' and d['bootstrapURL'] ==
            'https://releases.vynic.ge/windows/beta/bootstrap.json', 'Unexpected distribution target')
    require(re.fullmatch(r'[0-9a-f]{40}', policy['flutterRevision']), 'Flutter revision must be pinned')
    require(all(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', policy[k]) for k in
                ('flutterVersion', 'goVersion', 'pythonVersion')), 'Toolchains require exact versions')
    return {'sourceCommit': sha, 'version': version, 'build': build, 'channel': 'beta'}


def hash_file(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def inventory(directory):
    files = []
    for p in sorted(directory.rglob('*')):
        require(not p.is_symlink(), 'Candidate contains a symlink')
        if not p.is_file():
            continue
        name = p.relative_to(directory).as_posix()
        require(not any(part.startswith('.env') for part in p.relative_to(directory).parts)
                and p.suffix.lower() not in {'.pem', '.key', '.pfx', '.p12', '.jks'},
                'Forbidden credential/config file in candidate output')
        files.append({'path': name, 'bytes': p.stat().st_size, 'sha256': hash_file(p)})
    require(bool(files), 'Candidate output is empty')
    return files


def extract_source(archive, destination):
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            require(not Path(member.name).is_absolute() and '..' not in parts
                    and (member.isdir() or member.isfile()), 'Unsafe source archive member')
        for member in tar.getmembers():
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as src, target.open('xb') as dst:
                    shutil.copyfileobj(src, dst)


def checked_run(argv, cwd, log, env=None):
    # No private credentials are accepted by this stage. Only public build pins
    # enter command arguments. Logs are local candidate evidence, not receipts
    # fabricated from a caller-provided "passed" flag.
    with log.open('xb') as output:
        subprocess.run([str(x) for x in argv], cwd=cwd, env=env, stdout=output,
                       stderr=subprocess.STDOUT, check=True, timeout=3600)


def build_candidate(root, output, sha, version, build, flutter, go):
    policy = json.loads((root / POLICY).read_text(), object_pairs_hook=unique_object)
    request = validate_request(policy, sha, version, build)
    require(os.name == 'nt', 'Actual candidate compilation requires Windows')
    require('.'.join(map(str, sys.version_info[:3])) == policy['pythonVersion'], 'Python toolchain mismatch')
    require(not any(os.environ.get(k) for k in ('VYNIC_RELEASE_SIGNING_KEY_PEM',
                'VYNIC_R2_PUBLISH_ACCESS_KEY_ID', 'VYNIC_R2_PUBLISH_SECRET_ACCESS_KEY',
                'CLOUDFLARE_API_TOKEN', 'VYNIC_LICENSE_SIGNING_KEY')),
            'Signing, publisher and server credentials must not enter the build stage')
    git = lambda *args: subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    require(git('rev-parse', 'HEAD') == sha and not git('status', '--porcelain', '--untracked-files=no'),
            'Build requires the exact clean reviewed commit')
    require(not output.exists(), 'Use a new candidate directory; never overwrite previous outputs')
    output.mkdir(parents=True)
    logs = output / 'evidence'; logs.mkdir()
    archive = output / 'source.tar'
    with archive.open('xb') as f:
        subprocess.run(['git', 'archive', sha, 'apps/operations', 'apps/edge', 'packages/contracts', POLICY],
                       cwd=root, stdout=f, check=True)
    source = output / 'source'; source.mkdir()
    extract_source(archive, source)
    require(hash_file(source / POLICY) == hash_file(root / POLICY), 'Policy differs from reviewed source')
    actual_flutter = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    require(actual_flutter['frameworkRevision'] == policy['flutterRevision']
            and actual_flutter['frameworkVersion'] == policy['flutterVersion'], 'Flutter toolchain mismatch')
    actual_go = subprocess.check_output([go, 'version'], text=True).strip()
    require(f"go{policy['goVersion']} windows/amd64" in actual_go, 'Go toolchain mismatch')
    env = {**os.environ, 'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'GOTOOLCHAIN': 'local'}
    operations = source / 'apps/operations'
    checked_run([flutter, 'pub', 'get', '--enforce-lockfile'], operations, logs/'pub.log', env)
    # Broad unit/widget gates: baseline failures remain failures, never skips.
    checked_run([flutter, 'test', '--no-pub', 'test/unit', 'test/widget'], operations, logs/'flutter-tests.log', env)
    product = source / 'apps/pos'
    checked_run([sys.executable, operations/'tool/product.py', 'prepare', 'pos', 'windows',
                 '--environment', 'production', '--api-url', policy['apiOrigin'], '--output', product],
                source, logs/'prepare-product.log', env)
    checked_run([flutter, 'pub', 'get', '--enforce-lockfile'], product, logs/'product-pub.log', env)
    checked_run([flutter, 'build', 'windows', '--release', '--no-pub', '--build-name='+version,
                 '--build-number='+str(build), '--dart-define=VYNIC_ENV=production',
                 '--dart-define=VYNIC_API_URL='+policy['apiOrigin'], '--dart-define=VYNIC_APP_VERSION='+version,
                 '--dart-define=VYNIC_APP_BUILD='+str(build),
                 '--dart-define=VYNIC_LICENSE_PUBLIC_KEY='+policy['licensePublicKey']],
                product, logs/'pos-build.log', env)
    binaries = output/'unsigned'; binaries.mkdir()
    shutil.copytree(product/'build/windows/x64/runner/Release', binaries/'pos')
    require(policy['licensePublicKey'].encode() in (binaries/'pos/data/app.so').read_bytes(),
            'Compiled POS is missing the approved public licensing pin')
    fields = version_strings(inspect(binaries/'pos/vynic_pos.exe')['resources'][(16, 1, 1033)])
    require(fields.get('FileVersion') == version+'+'+str(build), 'POS binary version mismatch')
    distribution = output/'distribution.json'
    distribution.write_text(json.dumps(policy['distribution'], indent=2)+'\n')
    tool = source/'apps/edge/tool'
    native_version = version+'.'+str(build)
    checked_run([sys.executable, tool/'build-edge-windows.py', '--go', go, '--version', native_version,
                 '--out', binaries/'VynicEdge.exe'], source, logs/'edge-build.log', env)
    checked_run([sys.executable, tool/'build-setup.py', '--go', go, '--version', native_version,
                 '--production', '--distribution', distribution, '--out', binaries/'VynicSetup.exe'],
                source, logs/'setup-build.log', env)
    checked_run([sys.executable, tool/'build-windows-core-tests.py', '--go', go,
                 '--out', output/'core-tests'], source, logs/'core-build.log', env)
    receipt = {**request, 'schema': 1, 'status': 'unsigned-candidate-not-qualified',
               'policySha256': hash_file(source/POLICY), 'sourceArchiveSha256': hash_file(archive),
               'tools': {'flutter': actual_flutter['frameworkRevision'], 'go': actual_go,
                         'python': policy['pythonVersion']},
               'files': inventory(binaries), 'evidence': inventory(logs),
               'nativeCore': 'compiled-not-executed', 'installerEnrollment': 'pending',
               'authenticode': 'unsigned', 'manifestSigning': 'pending', 'uploaded': False, 'promoted': False}
    (output/'candidate.json').write_text(json.dumps(receipt, indent=2)+'\n')
    return receipt


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--approved-sha', required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--build', required=True, type=int)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--flutter', default='flutter')
    p.add_argument('--go', default='go')
    p.add_argument('--validate-only', action='store_true')
    a = p.parse_args()
    try:
        if a.validate_only:
            validate_request(json.loads((ROOT/POLICY).read_text(), object_pairs_hook=unique_object),
                             a.approved_sha, a.version, a.build)
            print('Release request policy passed; no compilation, signing, upload or activation')
        else:
            build_candidate(ROOT, a.output.resolve(), a.approved_sha, a.version, a.build, a.flutter, a.go)
            print('Unsigned candidate built; native acceptance, signing and private publication remain pending')
    except (ValueError, KeyError, OSError, subprocess.SubprocessError):
        print('Candidate stopped. Inspect local stage evidence; nothing was signed, uploaded or activated.', file=sys.stderr)
        sys.exit(1)
