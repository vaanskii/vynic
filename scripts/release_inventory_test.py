import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_inventory', Path(__file__).with_name('release_inventory.py'))
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class ReleaseInventoryTests(unittest.TestCase):
    def test_application_and_local_links_never_become_external_queries(self):
        lock = {'lockfileVersion': 3, 'packages': {
            '': {'name': 'private-application', 'version': '9.9.9'},
            'node_modules/local-contracts': {'link': True, 'resolved': '../../private'},
            'node_modules/public-lib': {'version': '1.2.3', 'resolved': 'https://registry.npmjs.org/public-lib/-/public-lib-1.2.3.tgz'},
        }}
        rows = inventory.npm_components(lock, 'private/project')
        payload = inventory.query_payload(rows)
        self.assertEqual(payload, {'queries': [{'package': {'ecosystem': 'npm', 'name': 'public-lib'}, 'version': '1.2.3'}]})
        self.assertNotIn('private', json.dumps(payload))

    def test_scopes_aliases_development_and_optional_are_retained(self):
        lock = {'lockfileVersion': 3, 'packages': {
            '': {'devDependencies': {'alias': '*'}},
            'node_modules/alias': {'name': '@scope/public-lib', 'version': '1.2.3', 'dev': True, 'optional': True,
                                   'resolved': 'https://registry.npmjs.org/@scope/public-lib/-/public-lib-1.2.3.tgz'},
        }}
        row, = inventory.npm_components(lock, 'app')
        self.assertEqual(row['name'], '@scope/public-lib')
        self.assertTrue(row['direct'])
        self.assertTrue(row['developmentOnly'])
        self.assertTrue(row['optional'])

    def test_multiple_locked_versions_are_not_collapsed(self):
        lock = {'lockfileVersion': 3, 'packages': {
            '': {},
            'node_modules/lib': {'version': '1.0.0', 'resolved': 'https://registry.npmjs.org/lib/-/lib-1.0.0.tgz'},
            'node_modules/parent/node_modules/lib': {'version': '2.0.0', 'resolved': 'https://registry.npmjs.org/lib/-/lib-2.0.0.tgz'},
        }}
        payload = inventory.query_payload(inventory.npm_components(lock, 'app'))
        self.assertEqual([row['version'] for row in payload['queries']], ['1.0.0', '2.0.0'])

    def test_unsafe_urls_fail_without_exposing_their_values(self):
        for value in ['https://user:PRIVATE@registry.npmjs.org/lib.tgz', 'https://registry.npmjs.org/lib.tgz?token=PRIVATE']:
            with self.subTest(value=value), self.assertRaises(inventory.InventoryError) as result:
                inventory.public_url(value, {'registry.npmjs.org'})
            self.assertNotIn('PRIVATE', str(result.exception))

    def test_custom_registry_and_hostname_lookalikes_are_not_public_queries(self):
        self.assertFalse(inventory.public_url('https://private.example/lib.tgz', {'registry.npmjs.org'}))
        self.assertFalse(inventory.public_url('https://registry.npmjs.org.evil.invalid/lib.tgz', {'registry.npmjs.org'}))

    def test_unknown_lock_format_or_missing_versions_fail_explicitly(self):
        for lock in [{'lockfileVersion': 1}, {'lockfileVersion': 3, 'packages': {'node_modules/x': {}}}]:
            with self.subTest(lock=lock), self.assertRaises(inventory.InventoryError):
                inventory.npm_components(lock, 'app')

    def test_pub_sdk_and_path_dependencies_stay_local(self):
        rows = inventory.pub_components({'packages': {
            'flutter': {'source': 'sdk', 'version': '0.0.0', 'dependency': 'direct main'},
            'private_contracts': {'source': 'path', 'version': '1.0.0', 'dependency': 'direct main'},
            'public_lib': {'source': 'hosted', 'version': '1.2.3', 'dependency': 'direct dev',
                           'description': {'url': 'https://pub.dev', 'sha256': 'public-checksum'}},
        }}, 'private/app')
        payload = inventory.query_payload(rows)
        self.assertEqual(len(payload['queries']), 1)
        self.assertEqual(payload['queries'][0]['package']['name'], 'public_lib')
        self.assertTrue(next(row for row in rows if row['name'] == 'public_lib')['developmentOnly'])

    def test_go_local_replacement_and_unreviewed_paths_are_not_sent(self):
        rows = inventory.go_components({'Require': [
            {'Path': 'google.golang.org/grpc', 'Version': 'v1.2.3'},
            {'Path': 'vynic.local/contracts', 'Version': 'v0.0.0'},
            {'Path': 'github.com/private-owner/internal', 'Version': 'v1.2.3'},
        ], 'Replace': [{'Old': {'Path': 'vynic.local/contracts'}, 'New': {'Path': '../contracts'}}]}, 'private/go.mod')
        payload = inventory.query_payload(rows)
        self.assertEqual(len(payload['queries']), 1)
        self.assertEqual(payload['queries'][0]['package']['name'], 'google.golang.org/grpc')

    def test_query_deduplication_preserves_ecosystem_and_version(self):
        rows = [{'queryEligible': True, 'ecosystem': ecosystem, 'name': 'public_lib', 'version': version}
                for ecosystem, version in [('npm', '1.2.3'), ('npm', '1.2.3'), ('Pub', '1.2.3'), ('npm', '2.0.0')]]
        self.assertEqual(len(inventory.query_payload(rows)['queries']), 3)

    def test_empty_omit_dev_bom_cannot_qualify_declared_runtime_dependencies(self):
        lock = {'packages': {'': {'dependencies': {'runtime-lib': '*'}},
                             'node_modules/runtime-lib': {'version': '1.2.3'}}}
        self.assertEqual(inventory.missing_runtime_direct(lock, {'components': []}), ['runtime-lib'])
        self.assertEqual(inventory.missing_runtime_direct(lock, {'components': [{'name': 'runtime-lib'}]}), [])

    def test_aliases_and_local_links_do_not_make_false_runtime_coverage_gaps(self):
        lock = {'packages': {'': {'dependencies': {'alias': '*', 'local': '*'}},
                             'node_modules/alias': {'name': '@scope/actual', 'version': '1.2.3'},
                             'node_modules/local': {'link': True}}}
        self.assertEqual(inventory.missing_runtime_direct(lock, {'components': [{'name': '@scope/actual'}]}), [])

    def test_transitive_pub_development_classification_is_unknown(self):
        rows = inventory.pub_components({'packages': {'lib': {'source': 'hosted', 'version': '1.2.3',
                                           'dependency': 'transitive', 'description': {'url': 'https://pub.dev'}}}}, 'app')
        self.assertIsNone(rows[0]['developmentOnly'])

    def test_invalid_query_fields_are_rejected(self):
        for name, version in [('lib\nPRIVATE', '1.2.3'), ('public_lib', 'https://PRIVATE'), ('public_lib', '')]:
            with self.subTest(name=name), self.assertRaises(inventory.InventoryError):
                inventory.query_payload([{'queryEligible': True, 'ecosystem': 'npm', 'name': name, 'version': version}])

    def test_runtime_credentials_proxy_and_options_are_not_forwarded(self):
        with patch.dict(os.environ, {'NPM_TOKEN': 'PRIVATE', 'HTTPS_PROXY': 'PRIVATE', 'NODE_OPTIONS': 'PRIVATE', 'RUBYOPT': 'PRIVATE'}):
            clean = inventory.clean_env()
        for key in ('NPM_TOKEN', 'HTTPS_PROXY', 'NODE_OPTIONS', 'RUBYOPT'):
            self.assertNotIn(key, clean)

    def test_changed_input_during_collection_fails_instead_of_qualifying_mixed_state(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'lock.json'
            path.write_text('before')
            hashes = {'lock.json': inventory.digest(path)}
            path.write_text('after')
            with self.assertRaises(inventory.InventoryError):
                inventory.verify_inputs(root, hashes)

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = root / 'report.json'
            report.write_text('owned-existing-report')
            with self.assertRaises(inventory.InventoryError):
                inventory.inventory(root, root, 'unused')
            self.assertEqual(report.read_text(), 'owned-existing-report')

    def test_safe_yaml_rejects_objects_and_does_not_execute_them(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'unsafe.lock'
            path.write_text('--- !ruby/object:PRIVATE\nfield: hidden\n')
            original = path.read_bytes()
            with self.assertRaises(inventory.InventoryError) as result:
                inventory.yaml_json(path)
            self.assertNotIn('PRIVATE', str(result.exception))
            self.assertEqual(path.read_bytes(), original)

    def test_cocoapods_known_symbol_keys_are_read_as_data(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'Podfile.lock'
            path.write_text('EXTERNAL SOURCES:\n  public_plugin:\n    :path: .symlinks/plugins/public_plugin\n')
            result = inventory.yaml_json(path, pod=True)
            self.assertEqual(result['EXTERNAL SOURCES']['public_plugin']['path'], '.symlinks/plugins/public_plugin')

    def test_cocoapods_unknown_symbol_and_object_tags_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'Podfile.lock'
            for text in ['field: :PRIVATE\n', '--- !ruby/object:PRIVATE\nfield: hidden\n']:
                path.write_text(text)
                with self.assertRaises(inventory.InventoryError):
                    inventory.yaml_json(path, pod=True)


if __name__ == '__main__':
    unittest.main()
