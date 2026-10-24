import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from windows_pe import version_info

spec = importlib.util.spec_from_file_location('signer', Path(__file__).with_name('sign-windows-release.py'))
signer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signer)


class SigningTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tool = self.root / 'signtool.exe'
        self.tool.touch()
        self.files = [self.root / name for name in signer.PRODUCTS]
        for file in self.files:
            file.write_bytes(b'fixture only, not a Windows executable')
        self.thumbprint = 'A' * 40
        self.details = {'status': 'Valid', 'type': 'Authenticode', 'thumbprint': self.thumbprint,
                        'subject': 'CN=Fixture Publisher', 'timestampThumbprint': 'B' * 40}

    def metadata(self, path):
        return {'resources': {(16, 1, 1033): version_info(signer.PRODUCTS[path.name], path.name, '1.0.0.0')}}

    def test_independent_payload_and_setup_stages(self):
        with patch.object(signer, 'inspect', side_effect=self.metadata):
            for stage in signer.STAGES:
                files = [file for file in self.files if file.name in signer.STAGES[stage]]
                signer.validate_inputs(files, self.tool, self.thumbprint, 'https://timestamp.example.test', stage)
                signer.validate_inputs(files, self.tool, self.thumbprint, None, stage, verify_only=True)
                with self.assertRaises(ValueError):
                    signer.validate_inputs(files + [files[0]], self.tool, self.thumbprint,
                                           'https://timestamp.example.test', stage)
                with self.assertRaises(ValueError):
                    signer.validate_inputs(files, self.tool, self.thumbprint, None, stage)

    def test_product_metadata_cannot_impersonate_publisher_trust(self):
        for change in [{'status': 'NotSigned'}, {'status': 'HashMismatch'}, {'status': 'NotTrusted'},
                       {'type': 'Catalog'}, {'thumbprint': 'C' * 40}, {'thumbprint': None},
                       {'subject': ''}, {'timestampThumbprint': None}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                signer.check_signature({**self.details, **change}, self.thumbprint)
        self.assertEqual(signer.check_signature(self.details, self.thumbprint.lower()), self.details)

    def test_verification_refuses_timestamp_warning_and_skips_inspection(self):
        with patch.object(signer.subprocess, 'run', side_effect=subprocess.CalledProcessError(2, 'signtool')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                signer.verify_signature(self.files[0], self.tool, self.thumbprint, 'powershell.exe')
            self.assertEqual(run.call_count, 1)
            self.assertIn('/tw', run.call_args.args[0])
            self.assertTrue(run.call_args.kwargs['check'])

    def test_verification_path_is_data_not_powershell_code(self):
        file = self.root / "quo'te $() ; literal.exe"
        with patch.object(signer.subprocess, 'run', return_value=subprocess.CompletedProcess(
                [], 0, stdout=json.dumps(self.details))) as run:
            signer.verify_signature(file, self.tool, self.thumbprint, 'powershell.exe')
            verify, inspection = run.call_args_list
            self.assertEqual(verify.args[0][1:6], ['verify', '/pa', '/all', '/tw', '/v'])
            self.assertNotIn(str(file), inspection.args[0][-1])
            self.assertEqual(inspection.kwargs['env']['VYNIC_RELEASE_VERIFY_FILE'], str(file))
            self.assertNotIn('-ExecutionPolicy', inspection.args[0])

    def test_verify_only_never_signs_or_changes_bytes(self):
        file = self.files[0]
        before = file.read_bytes()
        with patch.object(signer, 'verify_signature', return_value=self.details), \
                patch.object(signer.subprocess, 'run') as run:
            report = signer.process_files([file], self.tool, self.thumbprint, None, 'powershell.exe', True)
            run.assert_not_called()
        self.assertEqual(file.read_bytes(), before)
        self.assertEqual(report[0]['sha256'], hashlib.sha256(before).hexdigest())
        self.assertEqual(report[0]['publisherSubject'], self.details['subject'])
        self.assertEqual(report[0]['operation'], 'verify')

    def test_sign_failure_never_reports_verified(self):
        with patch.object(signer.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'signtool')), \
                patch.object(signer, 'verify_signature') as verify:
            with self.assertRaises(subprocess.CalledProcessError):
                signer.process_files(self.files, self.tool, self.thumbprint, 'https://timestamp.example.test', 'powershell.exe')
            verify.assert_not_called()

    def test_signs_sha256_then_reports_verified_bytes(self):
        with patch.object(signer, 'verify_signature', return_value=self.details), \
                patch.object(signer.subprocess, 'run') as run:
            report = signer.process_files(self.files, self.tool, self.thumbprint,
                                          'https://timestamp.example.test', 'powershell.exe')
            self.assertEqual(len(report), 3)
            command = run.call_args.args[0]
            self.assertEqual(command[command.index('/fd') + 1], 'SHA256')
            self.assertEqual(command[command.index('/td') + 1], 'SHA256')
            self.assertEqual(command[command.index('/sha1') + 1], self.thumbprint)
            self.assertNotIn('/f', command)  # no PFX/password arguments

    def test_changed_file_during_verification_is_rejected(self):
        file = self.files[0]
        def changed(*args):
            file.write_bytes(b'changed after signature check')
            return self.details
        with patch.object(signer, 'verify_signature', side_effect=changed):
            with self.assertRaisesRegex(ValueError, 'changed during'):
                signer.process_files([file], self.tool, self.thumbprint, None, 'powershell.exe', True)


if __name__ == '__main__':
    unittest.main()
