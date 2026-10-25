"""Offline publisher qualification. Synthetic keys/files only; no cloud calls."""
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

import boto3
from botocore.config import Config
from botocore.exceptions import EndpointConnectionError
from botocore.stub import ANY, Stubber
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import publish_private_r2 as pub

ACCOUNT = 'a' * 32
NOW = datetime(2026, 10, 25, tzinfo=timezone.utc)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def archive(files):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, raw in files.items():
            z.writestr(name, raw)
    return out.getvalue()


class Fixture:
    def __init__(self, root):
        self.root = root
        self.key = Ed25519PrivateKey.generate()
        public = self.key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.distribution = {'bootstrapURL': 'https://releases.vynic.ge/windows/beta/bootstrap.json',
                             'channel': 'beta', 'keys': {'test-key': {
                                 'public': base64.b64encode(public).decode(),
                                 'expires': (NOW + timedelta(days=365)).isoformat()}}}
        self.pos_zip = archive({'vynic_pos.exe': b'synthetic POS', 'data/app.so': b'synthetic AOT'})
        self.edge_zip = archive({'VynicEdge.exe': b'synthetic Edge'})
        self.pos = self.manifest('vynic-pos', self.pos_zip)
        self.edge = self.manifest('vynic-edge', self.edge_zip)
        self.bootstrap = {'posBinaryLayout': 2, 'product': 'vynic-bootstrap', 'protocol': 1,
                          'release': 18, 'os': 'windows', 'arch': 'amd64', 'channel': 'beta',
                          'expires': (NOW + timedelta(days=29)).isoformat(), 'edge': self.edge,
                          'pos': self.sign(self.pos, 'VYNIC-POS-RELEASE-v1\n'),
                          'posFeed': 'https://releases.vynic.ge/windows/beta/pos/manifest.json',
                          'repairBase': 'https://releases.vynic.ge/windows/beta/bootstrap',
                          'posReleaseBase': 'https://releases.vynic.ge/windows/beta/pos'}
        self.files = {'VynicSetup.exe': b'MZ-synthetic-unsigned-beta-setup',
                      'pos.zip': self.pos_zip, 'edge.zip': self.edge_zip}
        self.index = {self.distribution['bootstrapURL']: 'bootstrap.json',
                      self.pos['url']: 'pos.zip', self.edge['url']: 'edge.zip',
                      self.bootstrap['posFeed']: 'pos.json',
                      self.bootstrap['posReleaseBase'] + '/1.0.1.json': 'pos.json',
                      self.bootstrap['repairBase'] + '/18.json': 'bootstrap.json'}
        self.q = {'schema': 1, 'channel': 'beta', 'sourceCommit': 'b' * 40, 'version': '1.0.1',
                  'build': 18, 'artifactName': 'Vynic-Windows-1.0.1-build18-beta-offline.zip',
                  'artifactBytes': 0, 'artifactSha256': '', 'setupFile': 'VynicSetup.exe',
                  'setupSha256': sha(self.files['VynicSetup.exe']), 'authenticode': 'unsigned-beta', 'checks': {}}
        for name in ('build', 'tests'):
            raw = (name + ' passed on synthetic source bbbb').encode()
            (root / (name + '.log')).write_bytes(raw)
            self.q['checks'][name] = {'status': 'passed', 'file': name + '.log', 'sha256': sha(raw)}
        self.write()

    def manifest(self, product, raw):
        return {**({'licenseProtocol': 1} if product == 'vynic-pos' else {}), 'product': product, 'version': '1.0.1', 'release': 18, 'os': 'windows', 'arch': 'amd64',
                'channel': 'beta', 'url': 'https://releases.vynic.ge/' + product + '.zip',
                'sha256': sha(raw), 'size': len(raw), 'expires': (NOW + timedelta(days=29)).isoformat(),
                'updaterProtocol': 1, 'hiveSchema': 9, 'edgeSchema': 2,
                'dataPolicy': 'hive9-no-migration' if product == 'vynic-pos' else 'edge2-no-migration'}

    def sign(self, obj, domain):
        raw = pub.canonical(obj)
        return {'keyId': 'test-key', 'payload': base64.b64encode(raw).decode(),
                'signature': base64.b64encode(self.key.sign(domain.encode() + raw)).decode()}

    def write(self):
        self.files['bootstrap.json'] = pub.canonical(self.sign(self.bootstrap, 'VYNIC-BOOTSTRAP-v1\n'))
        self.files['pos.json'] = pub.canonical(self.bootstrap['pos'])
        self.files['bundle-index.json'] = pub.canonical(self.index)
        raw = archive(self.files)
        self.q['artifactBytes'], self.q['artifactSha256'] = len(raw), sha(raw)
        self.artifact = self.root / self.q['artifactName']
        self.artifact.write_bytes(raw)
        self.distribution_path = self.root / 'distribution.json'
        self.distribution_path.write_bytes(pub.canonical(self.distribution))
        self.receipt = self.root / 'qualification.json'
        self.receipt.write_bytes(pub.canonical(self.q))

    def prepare(self, now=NOW):
        return pub.prepare(self.artifact, self.distribution_path, self.receipt, ACCOUNT, now)


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.f = Fixture(Path(self.temp.name))

    def refused(self):
        with self.assertRaises((ValueError, KeyError)):
            with self.f.prepare():
                pass

    def test_plan_is_offline_and_binds_target_artifact_evidence_and_trust(self):
        with patch.object(pub, 'client', side_effect=AssertionError('network forbidden')):
            with self.f.prepare() as (p, snapshot):
                self.assertEqual(p['bucket'], 'vynic-installers')
                self.assertEqual(p['key'], 'windows/beta/1.0.1/build18/' + self.f.q['artifactName'])
                self.assertEqual(pub.digest(snapshot), (p['sha256'], p['bytes']))
                self.assertEqual(p['qualificationSha256'], sha(self.f.receipt.read_bytes()))
                self.assertFalse(p['publicAccess'])
                self.assertEqual(p['authenticode'], 'unsigned-beta')

    def test_failed_tests_block_even_with_valid_signatures(self):
        self.f.q['checks']['tests']['status'] = 'failed'
        self.f.write()
        self.refused()

    def test_publisher_requires_signed_licensing_capability(self):
        for capability in (None, 0, 2, True):
            with self.subTest(capability=capability):
                if capability is None:
                    self.f.pos.pop('licenseProtocol', None)
                else:
                    self.f.pos['licenseProtocol'] = capability
                self.f.bootstrap['pos'] = self.f.sign(self.f.pos, 'VYNIC-POS-RELEASE-v1\n')
                self.f.write()
                self.refused()

    def test_changed_build_evidence_blocks(self):
        (self.f.root / 'build.log').write_text('changed')
        self.refused()

    def test_changed_outer_archive_blocks(self):
        self.f.artifact.write_bytes(b'changed')
        self.refused()

    def test_changed_setup_blocks_even_with_updated_archive_digest(self):
        self.f.files['VynicSetup.exe'] = b'changed setup'
        self.f.write()
        self.refused()

    def test_corrupt_pos_blocks_even_with_updated_archive_digest(self):
        self.f.files['pos.zip'] = archive({'vynic_pos.exe': b'wrong bytes'})
        self.f.write()
        self.refused()

    def test_tampered_pos_signature_blocks(self):
        self.f.bootstrap['pos']['signature'] = base64.b64encode(bytes(64)).decode()
        self.f.write()
        self.refused()

    def test_wrong_trust_key_blocks(self):
        other = Ed25519PrivateKey.generate().public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.f.distribution['keys']['test-key']['public'] = base64.b64encode(other).decode()
        self.f.write()
        self.refused()

    def test_expired_metadata_blocks(self):
        with self.assertRaises(ValueError):
            with self.f.prepare(NOW + timedelta(days=30)):
                pass

    def test_no_stable_promotion(self):
        self.f.distribution['channel'] = 'stable'
        self.f.write()
        self.refused()

    def test_wrong_signed_build_and_schema_block(self):
        for field, value in [('release', 19), ('posBinaryLayout', 3)]:
            with self.subTest(field=field):
                before = self.f.bootstrap[field]
                self.f.bootstrap[field] = value
                self.f.write()
                self.refused()
                self.f.bootstrap[field] = before

    def test_zip_path_traversal_and_case_collision_block(self):
        for name in ('../private', 'C:/private', 'con.txt', 'POS.ZIP'):
            with self.subTest(name=name):
                self.f.files[name] = b'x'
                self.f.write()
                self.refused()
                del self.f.files[name]

    def test_offline_mapping_cannot_escape_or_fall_back(self):
        self.f.index[self.f.pos['url']] = '../pos.zip'
        self.f.write()
        self.refused()

    def test_approval_mismatch_precedes_credentials_and_network(self):
        with self.f.prepare() as (p, snapshot), patch.object(pub, 'client', side_effect=AssertionError('network')):
            with self.assertRaisesRegex(ValueError, 'Approval'):
                pub.upload(p, snapshot, '0' * 64)

    def test_changed_input_changes_approval(self):
        with self.f.prepare() as (p, _):
            old = pub.plan_hash(p)
        self.f.q['sourceCommit'] = 'c' * 40
        self.f.write()
        with self.f.prepare() as (p, _):
            self.assertNotEqual(pub.plan_hash(p), old)

    def test_snapshot_survives_source_change_after_approval(self):
        with self.f.prepare() as (p, snapshot):
            self.f.artifact.write_bytes(b'replaced after plan')
            self.assertEqual(pub.digest(snapshot), (p['sha256'], p['bytes']))

    def sdk(self):
        return boto3.client('s3', endpoint_url=f'https://{ACCOUNT}.r2.cloudflarestorage.com',
                            region_name='auto', aws_access_key_id='synthetic', aws_secret_access_key='synthetic',
                            config=Config(signature_version='s3v4', s3={'addressing_style': 'path'}))

    def expected_put(self, p):
        return {'Bucket': pub.BUCKET, 'Key': p['key'], 'Body': ANY, 'ContentLength': p['bytes'],
                'ContentType': 'application/zip', 'CacheControl': 'private, no-store',
                'ContentDisposition': f'attachment; filename="{p["artifactName"]}"',
                'StorageClass': 'STANDARD', 'IfNoneMatch': '*',
                'Metadata': {'sha256': p['sha256'], 'source-commit': p['sourceCommit']}}

    def test_sdk_upload_is_conditional_private_and_verified_by_complete_readback(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_response('put_object', {}, self.expected_put(p))
                stub.add_response('get_object', {'Body': io.BytesIO(self.f.artifact.read_bytes())},
                                  {'Bucket': pub.BUCKET, 'Key': p['key']})
                result = pub.upload(p, snapshot, pub.plan_hash(p), s3)
                self.assertEqual(result['status'], 'uploaded-and-verified')
                self.assertFalse(result['downloadActivated'])
                stub.assert_no_pending_responses()

    def test_existing_identical_object_is_verified_without_overwrite(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_client_error('put_object', 'PreconditionFailed', http_status_code=412,
                                      expected_params=self.expected_put(p))
                stub.add_response('get_object', {'Body': io.BytesIO(self.f.artifact.read_bytes())},
                                  {'Bucket': pub.BUCKET, 'Key': p['key']})
                self.assertEqual(pub.upload(p, snapshot, pub.plan_hash(p), s3)['status'], 'verified-existing')

    def test_existing_different_object_blocks_without_delete(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_client_error('put_object', 'PreconditionFailed', http_status_code=412,
                                      expected_params=self.expected_put(p))
                stub.add_response('get_object', {'Body': io.BytesIO(b'different')},
                                  {'Bucket': pub.BUCKET, 'Key': p['key']})
                with self.assertRaisesRegex(ValueError, 'readback mismatch'):
                    pub.upload(p, snapshot, pub.plan_hash(p), s3)
                stub.assert_no_pending_responses()

    def test_access_refusal_is_not_success_and_does_not_leak_provider_body(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_client_error('put_object', 'AccessDenied', service_message='SECRET', http_status_code=403,
                                      expected_params=self.expected_put(p))
                with self.assertRaises(ValueError) as result:
                    pub.upload(p, snapshot, pub.plan_hash(p), s3)
                self.assertNotIn('SECRET', str(result.exception))
                stub.assert_no_pending_responses()

    def test_ambient_aws_credentials_are_not_accepted(self):
        with patch.dict(os.environ, {'AWS_ACCESS_KEY_ID': 'not-authorized', 'AWS_SECRET_ACCESS_KEY': 'not-authorized'}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Explicit R2'):
                pub.client(ACCOUNT)

    def test_upload_timeout_is_uncertain_and_never_promotes(self):
        with self.f.prepare() as (p, snapshot):
            s3 = Mock()
            s3.put_object.side_effect = EndpointConnectionError(endpoint_url='https://SECRET.invalid')
            with self.assertRaisesRegex(ValueError, 'outcome uncertain') as result:
                pub.upload(p, snapshot, pub.plan_hash(p), s3)
            self.assertNotIn('SECRET', str(result.exception))
            s3.get_object.assert_not_called()

    def test_readback_failure_never_reports_success(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_response('put_object', {}, self.expected_put(p))
                stub.add_client_error('get_object', 'AccessDenied', http_status_code=403,
                                      expected_params={'Bucket': pub.BUCKET, 'Key': p['key']})
                with self.assertRaisesRegex(ValueError, 'readback failed'):
                    pub.upload(p, snapshot, pub.plan_hash(p), s3)

    def test_publisher_client_pins_endpoint_and_disables_ambient_proxies(self):
        env = {'VYNIC_R2_PUBLISH_ACCESS_KEY_ID': 'synthetic',
               'VYNIC_R2_PUBLISH_SECRET_ACCESS_KEY': 'synthetic',
               'AWS_ENDPOINT_URL': 'http://untrusted.invalid', 'HTTPS_PROXY': 'http://untrusted.invalid'}
        with patch.dict(os.environ, env, clear=True):
            s3 = pub.client(ACCOUNT)
        self.assertEqual(s3.meta.endpoint_url, f'https://{ACCOUNT}.r2.cloudflarestorage.com')
        self.assertEqual(s3.meta.region_name, 'auto')
        self.assertEqual(s3.meta.config.proxies, {})
        self.assertEqual(s3.meta.config.retries['total_max_attempts'], 1)

    def test_extra_readback_bytes_fail_closed(self):
        with self.f.prepare() as (p, snapshot):
            s3 = self.sdk()
            with Stubber(s3) as stub:
                stub.add_response('put_object', {}, self.expected_put(p))
                stub.add_response('get_object', {'Body': io.BytesIO(self.f.artifact.read_bytes() + b'extra')},
                                  {'Bucket': pub.BUCKET, 'Key': p['key']})
                with self.assertRaisesRegex(ValueError, 'size limit'):
                    pub.upload(p, snapshot, pub.plan_hash(p), s3)

    def test_missing_repair_mapping_blocks(self):
        del self.f.index[self.f.bootstrap['repairBase'] + '/18.json']
        self.f.write()
        self.refused()

    def test_fresh_install_bundle_does_not_require_activating_an_update_feed(self):
        del self.f.index[self.f.bootstrap['posFeed']]
        self.f.write()
        with self.f.prepare() as (plan, _):
            self.assertEqual(plan['build'], 18)

    def test_mismatched_validly_signed_repair_blocks(self):
        other = dict(self.f.pos, release=19)
        self.f.files['wrong-pos.json'] = pub.canonical(self.f.sign(other, 'VYNIC-POS-RELEASE-v1\n'))
        self.f.index[self.f.bootstrap['posReleaseBase'] + '/1.0.1.json'] = 'wrong-pos.json'
        self.f.write()
        self.refused()


if __name__ == '__main__':
    unittest.main()
