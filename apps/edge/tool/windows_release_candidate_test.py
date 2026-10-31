import copy
from datetime import datetime, timedelta, timezone
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import windows_release_candidate as candidate


class CandidatePolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = json.loads((candidate.ROOT / candidate.POLICY).read_text())
        for key in self.policy['distribution']['keys'].values():
            key['expires'] = (datetime.now(timezone.utc)+timedelta(days=365)).isoformat()

    def validate(self, **kwargs):
        return candidate.validate_request(kwargs.get('policy', self.policy), kwargs.get('sha', 'a'*40),
                                          kwargs.get('version', '1.1.1'), kwargs.get('build', 20))

    def test_actual_updater_requires_new_version_and_new_counter(self):
        self.assertEqual(self.validate()['version'], '1.1.1')
        for version, build in [('1.1.0', 20), ('1.0.14', 99), ('1.1.1', 19), ('1.1.1', True),
                               ('1.1.1', 65536), ('65536.1.1', 20), ('1.01.1', 20), ('1.1.1;whoami', 20)]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                self.validate(version=version, build=build)

    def test_arbitrary_source_origin_channel_private_fields_and_empty_pin_refused(self):
        for key, value in [('schema', 2), ('channel', 'stable'), ('apiOrigin', 'http://localhost'),
                           ('licensePublicKey', 'A'*43+'='), ('flutterRevision', 'stable'),
                           ('goVersion', 'latest'), ('privateKey', 'synthetic-do-not-print')]:
            p=copy.deepcopy(self.policy); p[key]=value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(policy=p)
        with self.assertRaises(ValueError):
            self.validate(sha='main')

    def test_distribution_must_stay_at_approved_beta_origin(self):
        p=copy.deepcopy(self.policy);p['distribution']['bootstrapURL']='https://other.example.org/bootstrap.json'
        with self.assertRaises(ValueError): self.validate(policy=p)

    def test_stale_trust_refused_before_build(self):
        for key in self.policy['distribution']['keys'].values(): key['expires']='2000-01-01T00:00:00Z'
        with self.assertRaises(ValueError): self.validate()

    def test_inventory_binds_every_byte_and_rejects_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'binary.exe').write_bytes(b'fixture')
            first=candidate.inventory(root);(root/'binary.exe').write_bytes(b'changed')
            self.assertNotEqual(first[0]['sha256'], candidate.inventory(root)[0]['sha256'])
            (root/'.env').write_text('synthetic')
            with self.assertRaises(ValueError):candidate.inventory(root)

    def test_source_archive_refuses_traversal_and_links_before_extracting(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute',tarfile.REGTYPE),
                           ('safe/link',tarfile.SYMTYPE), ('safe/link',tarfile.LNKTYPE)]:
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);archive=root/'source.tar';dest=root/'source';dest.mkdir()
                with tarfile.open(archive,'w') as t:
                    m=tarfile.TarInfo(name);m.type=kind;m.linkname='elsewhere'
                    t.addfile(m, io.BytesIO(b''))
                with self.assertRaises(ValueError):candidate.extract_source(archive,dest)
                self.assertEqual(list(dest.iterdir()),[])

    def test_source_extract_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/'source.tar';dest=root/'source';dest.mkdir()
            with tarfile.open(archive,'w') as t:
                m=tarfile.TarInfo('input');m.size=3;t.addfile(m,io.BytesIO(b'new'))
            (dest/'input').write_bytes(b'old')
            with self.assertRaises(FileExistsError):candidate.extract_source(archive,dest)
            self.assertEqual((dest/'input').read_bytes(),b'old')

    def test_failed_command_never_produces_success_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with patch.object(candidate.subprocess,'run',side_effect=candidate.subprocess.CalledProcessError(1,['fixture'])):
                with self.assertRaises(candidate.subprocess.CalledProcessError):
                    candidate.checked_run(['fixture'],root,root/'failed.log')
            self.assertFalse((root/'candidate.json').exists())


if __name__ == '__main__': unittest.main()
