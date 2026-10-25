#!/usr/bin/env python3
"""Review, then publish one qualified offline Windows beta ZIP to private R2.

Default execution is offline. No deployment, feeds, credential discovery, ACLs,
bucket changes, release publication or deletion. See docs/PRIVATE_R2_RELEASES.md.
"""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from urllib.parse import urlsplit
import zipfile

from windows_distribution import unique_object, validate as validate_distribution

BUCKET = 'vynic-installers'
MAX_ARCHIVE = 512 << 20
MAX_EXPANDED = 1536 << 20
HEX = r'[0-9a-f]{64}'
VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'


class PublishError(ValueError):
    """Fixed, credential-free publisher diagnostic safe to display."""


def require(ok, message):
    if not ok:
        raise PublishError(message)


def decode(raw):
    return json.loads(raw, object_pairs_hook=unique_object)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def digest(stream, limit=MAX_ARCHIVE):
    h, total = hashlib.sha256(), 0
    while True:
        data = stream.read(min(1 << 20, limit + 1 - total))
        if not data:
            return h.hexdigest(), total
        total += len(data)
        require(total <= limit, 'File exceeds publisher size limit')
        h.update(data)


def regular(path):
    require(stat.S_ISREG(path.lstat().st_mode), 'Only regular, non-symlink input files are allowed')


def bounded(path, limit=128 << 10):
    regular(path)
    with path.open('rb') as f:
        data = f.read(limit + 1)
    require(len(data) <= limit, 'Input JSON/evidence exceeds size limit')
    return data


def https(value):
    require(isinstance(value, str), 'Invalid manifest URL')
    u = urlsplit(value)
    require(u.scheme == 'https' and u.hostname and not u.username and not u.password
            and not u.query and not u.fragment and not any(c.isspace() for c in value)
            and '\\' not in value, 'Manifest URLs must be credential-free HTTPS')


def future(value, now):
    t = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(t.tzinfo is not None and now < t <= now + timedelta(days=31),
            'Expired or excessive manifest validity')
    return t


def envelope(raw, keys, domain, now):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    e = decode(raw)
    require(set(e) == {'keyId', 'payload', 'signature'}, 'Invalid signed envelope')
    require(e['keyId'] in keys, 'Untrusted manifest key')
    key = keys[e['keyId']]
    require(datetime.fromisoformat(key['expires'].replace('Z', '+00:00')) > now, 'Expired trust key')
    payload = base64.b64decode(e['payload'], validate=True)
    require(len(payload) <= 128 << 10, 'Oversized signed metadata')
    try:
        Ed25519PublicKey.from_public_bytes(base64.b64decode(key['public'], validate=True)).verify(
            base64.b64decode(e['signature'], validate=True), domain.encode() + payload)
    except InvalidSignature:
        raise PublishError('Invalid Ed25519 manifest signature') from None
    return decode(payload)


def entries(z, required=None):
    require(len(z.infolist()) <= 20000, 'Too many ZIP entries')
    seen, total = set(), 0
    for i in z.infolist():
        name = i.filename.rstrip('/')
        require(name and not name.startswith('/') and not i.filename.endswith('//') and not any(c in name for c in '\\:<>"|?*')
                and not any(ord(c) < 32 for c in name), 'Unsafe ZIP path')
        for part in name.split('/'):
            require(part not in ('', '.', '..') and part.rstrip(' .') == part
                    and not re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])',
                                         part.split('.')[0], re.I), 'Unsafe Windows ZIP path')
        require(name.casefold() not in seen, 'Duplicate ZIP entry')
        seen.add(name.casefold())
        mode = i.external_attr >> 16
        require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR)
                and not i.flag_bits & 1, 'ZIP links/special/encrypted entries refused')
        total += i.file_size
        require(total <= MAX_EXPANDED, 'Expanded ZIP exceeds size limit')
    if required:
        require(required in z.namelist() and not z.getinfo(required).is_dir(), 'Required executable absent')


def member(z, name, limit):
    require(name in z.namelist() and z.getinfo(name).file_size <= limit, 'Missing/oversized bundle member')
    with z.open(name) as f:
        data = f.read(limit + 1)
    require(len(data) <= limit, 'Oversized bundle member')
    return data


def verify_payload(z, index, manifest, product, now):
    expected = {'product', 'version', 'release', 'os', 'arch', 'channel', 'url', 'sha256',
                'size', 'expires', 'updaterProtocol', 'hiveSchema', 'edgeSchema', 'dataPolicy'}
    if product == 'vynic-pos':
        expected.add('licenseProtocol')
        require(type(manifest.get('licenseProtocol')) is int and manifest['licenseProtocol'] == 1,
                'Publisher-signed licensing capability required for the integrated beta')
    require(set(manifest) == expected, 'Unexpected manifest fields')
    require(all(type(manifest[k]) is int for k in ('release', 'size', 'updaterProtocol', 'hiveSchema', 'edgeSchema')),
            'Manifest numeric fields must be integers')
    require(manifest['product'] == product and manifest['channel'] == 'beta'
            and manifest['os'] == 'windows' and manifest['arch'] == 'amd64'
            and re.fullmatch(VERSION, manifest['version'])
            and type(manifest['release']) is int and manifest['release'] > 0
            and manifest['updaterProtocol'] == 1 and manifest['hiveSchema'] == 9
            and manifest['edgeSchema'] == 2
            and manifest['dataPolicy'] == ('hive9-no-migration' if product == 'vynic-pos' else 'edge2-no-migration')
            and re.fullmatch(HEX, manifest['sha256'])
            and type(manifest['size']) is int and 0 < manifest['size'] <= MAX_ARCHIVE,
            'Signed package compatibility/policy rejected')
    future(manifest['expires'], now)
    https(manifest['url'])
    require(manifest['url'] in index, 'Signed payload missing from offline mapping')
    name = index[manifest['url']]
    with z.open(name) as source, tempfile.TemporaryFile() as copy:
        h, count = hashlib.sha256(), 0
        while True:
            chunk = source.read(1 << 20)
            if not chunk:
                break
            count += len(chunk)
            require(count <= manifest['size'], 'Payload size mismatch')
            h.update(chunk)
            copy.write(chunk)
        require(count == manifest['size'] and h.hexdigest() == manifest['sha256'], 'Payload hash/size mismatch')
        copy.seek(0)
        with zipfile.ZipFile(copy) as nested:
            entries(nested, 'vynic_pos.exe' if product == 'vynic-pos' else 'VynicEdge.exe')
            require(nested.testzip() is None, 'Payload ZIP integrity failure')


def qualification(path):
    raw = bounded(path)
    q = decode(raw)
    require(set(q) == {'schema', 'channel', 'sourceCommit', 'version', 'build', 'artifactName',
                      'artifactBytes', 'artifactSha256', 'setupFile', 'setupSha256', 'checks',
                      'authenticode'}, 'Invalid qualification receipt fields')
    require(q['schema'] == 1 and q['channel'] == 'beta' and re.fullmatch(r'[0-9a-f]{40}', q['sourceCommit'])
            and re.fullmatch(VERSION, q['version']) and type(q['build']) is int and q['build'] > 0,
            'A reviewed Windows beta qualification receipt is required')
    expected_name = f"Vynic-Windows-{q['version']}-build{q['build']}-beta-offline.zip"
    require(q['artifactName'] == expected_name and re.fullmatch(HEX, q['artifactSha256'])
            and re.fullmatch(HEX, q['setupSha256']) and type(q['artifactBytes']) is int
            and 0 < q['artifactBytes'] <= MAX_ARCHIVE
            and re.fullmatch(r'VynicSetup(?:-[A-Za-z0-9.-]+)?\.exe', q['setupFile'])
            and q['authenticode'] in ('unsigned-beta', 'verified'), 'Invalid qualified artifact identity')
    require(set(q['checks']) == {'build', 'tests'}, 'Successful build and tests evidence required')
    for check in q['checks'].values():
        require(set(check) == {'status', 'file', 'sha256'} and check['status'] == 'passed'
                and re.fullmatch(HEX, check['sha256']), 'Build/tests have not passed')
        evidence = bounded(path.parent / check['file'], 10 << 20)
        require(evidence and hashlib.sha256(evidence).hexdigest() == check['sha256'],
                'Qualification evidence changed or missing')
    return q, hashlib.sha256(raw).hexdigest()


@contextmanager
def prepare(artifact, distribution, evidence, account, now=None):
    """Snapshot once; approve and upload those exact validated bytes, not a changing path."""
    now = now or datetime.now(timezone.utc)
    require(re.fullmatch(r'[0-9a-f]{32}', account), 'Explicit Cloudflare account ID required')
    q, evidence_hash = qualification(evidence)
    raw = bounded(distribution)
    d = validate_distribution(raw, production=True, now=now)
    require(d['channel'] == 'beta', 'This publisher cannot promote stable releases')
    regular(artifact)
    require(artifact.name == q['artifactName'], 'Artifact filename differs from qualification')
    require(artifact.stat().st_size == q['artifactBytes'], 'Archive size differs from qualification')
    with tempfile.TemporaryFile() as snapshot:
        with artifact.open('rb') as source:
            count = 0
            while True:
                data = source.read(1 << 20)
                if not data:
                    break
                count += len(data)
                require(count <= MAX_ARCHIVE, 'Archive exceeds publisher size limit')
                snapshot.write(data)
        snapshot.seek(0)
        sha, size = digest(snapshot)
        require((sha, size) == (q['artifactSha256'], q['artifactBytes']), 'Archive hash/size differs from qualification')
        snapshot.seek(0)
        with zipfile.ZipFile(snapshot) as z:
            entries(z, q['setupFile'])
            index = decode(member(z, 'bundle-index.json', 16 << 10))
            require(isinstance(index, dict) and 0 < len(index) <= 16, 'Invalid offline bundle index')
            for url, name in index.items():
                https(url)
                require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name)
                        and name in z.namelist() and not z.getinfo(name).is_dir(), 'Invalid offline bundle mapping')
            require(d['bootstrapURL'] in index, 'Pinned bootstrap absent from offline package')
            b = envelope(member(z, index[d['bootstrapURL']], 128 << 10), d['keys'], 'VYNIC-BOOTSTRAP-v1\n', now)
            require(set(b) == {'posBinaryLayout', 'product', 'protocol', 'release', 'os', 'arch',
                              'channel', 'expires', 'edge', 'pos', 'posFeed', 'repairBase', 'posReleaseBase'},
                    'Unexpected bootstrap fields')
            require(all(type(b[k]) is int for k in ('posBinaryLayout', 'protocol', 'release')),
                    'Bootstrap numeric fields must be integers')
            require(b['product'] == 'vynic-bootstrap' and b['protocol'] == 1 and b['posBinaryLayout'] == 2
                    and b['channel'] == 'beta' and b['os'] == 'windows' and b['arch'] == 'amd64'
                    and b['release'] == q['build'], 'Bootstrap identity differs from qualification')
            future(b['expires'], now)
            for field in ('posFeed', 'repairBase', 'posReleaseBase'):
                https(b[field])
            pos = envelope(canonical(b['pos']), d['keys'], 'VYNIC-POS-RELEASE-v1\n', now)
            require(pos['version'] == q['version'] and pos['release'] == q['build'], 'POS identity differs from qualification')
            metadata = [
                    (b['posReleaseBase'] + '/' + pos['version'] + '.json', 'VYNIC-POS-RELEASE-v1\n', pos),
                    (b['repairBase'] + '/' + str(b['release']) + '.json', 'VYNIC-BOOTSTRAP-v1\n', b)]
            # A fresh-install beta intentionally has no active automatic feed.
            # If one is supplied locally, it must match the signed baseline.
            if b['posFeed'] in index:
                metadata.append((b['posFeed'], 'VYNIC-POS-RELEASE-v1\n', pos))
            for url, domain, expected in metadata:
                require(url in index, 'Current/repair metadata absent from offline package')
                observed = envelope(member(z, index[url], 128 << 10), d['keys'], domain, now)
                require(observed == expected, 'Current/repair metadata differs from the pinned package')
            verify_payload(z, index, pos, 'vynic-pos', now)
            verify_payload(z, index, b['edge'], 'vynic-edge', now)
            with z.open(q['setupFile']) as setup:
                setup_hash, _ = digest(setup)
            require(setup_hash == q['setupSha256'], 'Setup hash differs from qualification')
            require(z.testzip() is None, 'Offline archive integrity failure')
        plan = {'schema': 1, 'accountId': account, 'bucket': BUCKET,
                'key': f"windows/beta/{q['version']}/build{q['build']}/{q['artifactName']}",
                'artifactName': q['artifactName'], 'bytes': size, 'sha256': sha,
                'sourceCommit': q['sourceCommit'], 'qualificationSha256': evidence_hash,
                'distributionSha256': hashlib.sha256(raw).hexdigest(), 'channel': 'beta',
                'version': q['version'], 'build': q['build'], 'authenticode': q['authenticode'],
                'metadataExpires': min(future(m['expires'], now) for m in (b, pos, b['edge'])).isoformat(),
                'publicAccess': False, 'storageClass': 'STANDARD'}
        snapshot.seek(0)
        yield plan, snapshot


def plan_hash(plan):
    return hashlib.sha256(canonical(plan)).hexdigest()


def client(account):
    import boto3
    from botocore.config import Config
    access = os.environ.get('VYNIC_R2_PUBLISH_ACCESS_KEY_ID')
    secret = os.environ.get('VYNIC_R2_PUBLISH_SECRET_ACCESS_KEY')
    require(access and secret, 'Explicit R2 publisher environment credentials required; no ambient credential lookup')
    return boto3.client('s3', endpoint_url=f'https://{account}.r2.cloudflarestorage.com', region_name='auto',
                        aws_access_key_id=access, aws_secret_access_key=secret,
                        aws_session_token=os.environ.get('VYNIC_R2_PUBLISH_SESSION_TOKEN'),
                        config=Config(signature_version='s3v4', connect_timeout=10, read_timeout=120,
                                      retries={'total_max_attempts': 1}, proxies={},
                                      request_checksum_calculation='when_required',
                                      response_checksum_validation='when_required',
                                      s3={'addressing_style': 'path'}))


def upload(plan, snapshot, approval, s3=None):
    require(approval == plan_hash(plan), 'Approval does not match this exact upload plan; no network request made')
    s3 = s3 or client(plan['accountId'])
    from botocore.exceptions import BotoCoreError, ClientError
    existing = False
    try:
        snapshot.seek(0)
        s3.put_object(Bucket=BUCKET, Key=plan['key'], Body=snapshot, ContentLength=plan['bytes'],
                      ContentType='application/zip', CacheControl='private, no-store',
                      ContentDisposition=f'attachment; filename="{plan["artifactName"]}"',
                      StorageClass='STANDARD', IfNoneMatch='*',
                      Metadata={'sha256': plan['sha256'], 'source-commit': plan['sourceCommit']})
    except ClientError as e:
        if e.response.get('ResponseMetadata', {}).get('HTTPStatusCode') == 412:
            existing = True
        else:
            raise PublishError('R2 refused upload; nothing promoted. Check scoped publisher access and rerun the same approved plan.') from None
    except BotoCoreError:
        raise PublishError('R2 upload outcome uncertain; rerun the same approved plan to verify. No promotion occurred.') from None
    try:
        result = s3.get_object(Bucket=BUCKET, Key=plan['key'])
        with result['Body'] as body:
            sha, size = digest(body, plan['bytes'])
        require((sha, size) == (plan['sha256'], plan['bytes']),
                'R2 readback mismatch: version is occupied or upload is unverified; do not delete or overwrite')
    except (ClientError, BotoCoreError):
        raise PublishError('R2 readback failed; upload is unverified. No promotion occurred.') from None
    return {'status': 'verified-existing' if existing else 'uploaded-and-verified',
            'planSha256': plan_hash(plan), 'bucket': BUCKET, 'key': plan['key'],
            'bytes': size, 'sha256': sha, 'downloadActivated': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--distribution', type=Path, required=True)
    parser.add_argument('--qualification', type=Path, required=True)
    parser.add_argument('--account-id', required=True)
    parser.add_argument('--upload', action='store_true')
    parser.add_argument('--approve-plan', help='SHA-256 from the independently reviewed offline plan')
    args = parser.parse_args()
    try:
        require(args.upload == bool(args.approve_plan), '--upload and --approve-plan must be supplied together')
        with prepare(args.artifact, args.distribution, args.qualification, args.account_id) as (plan, snapshot):
            result = upload(plan, snapshot, args.approve_plan) if args.upload else {
                'status': 'review-required', 'planSha256': plan_hash(plan), 'plan': plan}
            print(json.dumps(result, indent=2))
    except PublishError as error:
        print(str(error), file=sys.stderr)
        return 1
    except ModuleNotFoundError:
        print('Install the pinned R2 publisher requirements in the isolated release environment.', file=sys.stderr)
        return 1
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as error:
        # Local input error details can contain secrets/URLs; report a stable class.
        print('Private R2 publication refused (' + type(error).__name__ + '). '
              'Check the qualification, trust, package and exact-plan approval. No delivery was activated.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
