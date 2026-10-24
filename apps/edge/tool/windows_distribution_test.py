import base64
import copy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from windows_distribution import validate

NOW = datetime(2026, 10, 24, tzinfo=timezone.utc)


class DistributionTest(unittest.TestCase):
    def setUp(self):
        self.config = {
            'bootstrapURL': 'https://releases.vynic.ge/windows/stable/bootstrap.json',
            'channel': 'stable',
            'keys': {'fixture-public-only': {
                'public': base64.b64encode(bytes(range(32))).decode(),
                'expires': '2027-10-24T00:00:00Z',
            }},
        }

    def validate(self, config=None, production=True):
        return validate(json.dumps(config or self.config), production=production, now=NOW)

    def test_public_configuration_and_explicit_beta(self):
        self.assertEqual(self.validate(), self.config)
        self.config['channel'] = 'beta'
        self.validate()

    def test_lab_only_accepted_without_production_gate(self):
        self.config.update(bootstrapURL='https://10.10.10.3:8443/bootstrap.json', channel='local-development')
        self.validate(production=False)
        with self.assertRaises(ValueError):
            self.validate()

    def test_production_refuses_unusable_or_credentialed_endpoints(self):
        for url in [
            'http://releases.vynic.ge/a', 'https://localhost/a', 'https://127.0.0.1/a',
            'https://[::1]/a', 'https://127.1/a', 'https://10.10.10.3:8443/a', 'https://releases.example.invalid/a',
            'https://example.com/a', 'https://release.local/a', 'https://release.test/a',
            'https://release.internal/a', 'https://release.lan/a', 'https://release.home.arpa/a',
            'https://user:password@releases.vynic.ge/a',
            'https://@releases.vynic.ge/a', 'https://releases.vynic.ge/a?token=secret',
            'https://releases.vynic.ge/a#fragment', 'https://releases.vynic.ge:8443/a',
            'https://releases.vynic.ge:bad/a', 'https://release_host.vynic.ge/a',
            'https://releases.vynic.ge/\nbootstrap.json', 'https://releases.vynic.ge\\evil/a',
        ]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                config = {**self.config, 'bootstrapURL': url}
                self.validate(config)

    def test_refuses_missing_unknown_and_duplicate_fields(self):
        for config in [[], {}, {**self.config, 'privateKey': 'forbidden'},
                       {**self.config, 'keys': {}}, {**self.config, 'keys': []},
                       {**self.config, 'channel': ''}, {**self.config, 'channel': '../stable'}]:
            with self.subTest(config=config), self.assertRaises(ValueError):
                validate(json.dumps(config), now=NOW)
        for raw in ['{"channel":"stable","channel":"beta"}',
                    json.dumps(self.config).replace('"expires":', '"public":"duplicate","expires":')]:
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                validate(raw, now=NOW)

    def test_refuses_bad_expired_and_secret_keys(self):
        for change in [
            {'public': 'not-base64'}, {'public': base64.b64encode(bytes(32)).decode()},
            {'public': base64.b64encode(bytes(31)).decode()}, {'public': None},
            {'expires': '2026-10-23T00:00:00Z'}, {'expires': '2027-10-24'},
            {'expires': '2027-10-24T00:00:00'}, {'expires': '2027-99-24T00:00:00Z'},
            {'expires': '2026-11-24T00:00:00Z'}, {'private': 'forbidden'},
        ]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                config = copy.deepcopy(self.config)
                config['keys']['fixture-public-only'].update(change)
                self.validate(config)

    def test_rotation_can_overlap_a_short_lived_key(self):
        self.config['keys']['old'] = {**self.config['keys']['fixture-public-only'],
                                      'expires': '2026-10-25T00:00:00Z'}
        self.validate()

    def test_example_is_deliberately_not_buildable(self):
        example = Path(__file__).resolve().parents[1] / 'packaging/windows/distribution.example.json'
        with self.assertRaises(ValueError):
            validate(example.read_bytes(), production=True, now=NOW)

    def test_invalid_build_does_not_invoke_compiler_or_create_resource(self):
        spec = importlib.util.spec_from_file_location('build_setup', Path(__file__).with_name('build-setup.py'))
        build = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build)
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / 'distribution.json'
            config.write_text(json.dumps({**self.config, 'keys': {}}))
            with patch.object(sys, 'argv', ['build-setup.py', '--production', '--distribution', str(config),
                                           '--out', str(Path(folder) / 'VynicSetup.exe')]), \
                    patch.object(build, 'resource') as resource, \
                    patch.object(subprocess, 'run') as run, \
                    patch('sys.stderr'):
                with self.assertRaises(SystemExit) as error:
                    build.main()
                self.assertEqual(error.exception.code, 2)
                resource.assert_not_called()
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
