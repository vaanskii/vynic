import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from build_config import public_build_config
import dev
import product


class BuildConfigTest(unittest.TestCase):
    def test_only_public_keys_are_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / '.env'
            file.write_text('POS_SYNC_API_KEY=fixture-private\nBACKEND_URL_MACOS=http://127.0.0.1:3000\nVYNIC_ENV=development\nVYNIC_API_URL="http://api.vynic.localhost"\n')
            values = public_build_config(file)
            self.assertEqual(set(values), {'VYNIC_ENV', 'VYNIC_API_URL'})
            self.assertEqual(values['VYNIC_API_URL'], 'http://api.vynic.localhost')

    def test_invalid_url_error_does_not_emit_value(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / '.env'
            file.write_text('VYNIC_API_URL=https://fixture-user:fixture-private@example.invalid\n')
            with self.assertRaises(ValueError) as error:
                public_build_config(file)
            self.assertFalse('fixture-private' in str(error.exception))

    def test_developer_command_consumes_public_configuration(self):
        with patch.object(dev, 'public_build_config', return_value={'VYNIC_ENV': 'development', 'VYNIC_API_URL': 'http://api.vynic.localhost'}) as reader, patch.object(dev, 'workspace', return_value=Path('/tmp/synthetic-workspace')), patch.object(dev.subprocess, 'call', return_value=0) as runner, patch.dict(os.environ, {}, clear=True), patch('sys.argv', ['dev.py', 'manager']):
            with self.assertRaises(SystemExit) as outcome:
                dev.main()
            self.assertEqual(outcome.exception.code, 0)
            reader.assert_called_once()
            command = runner.call_args.args[0]
            self.assertIn('--dart-define=VYNIC_API_URL=http://api.vynic.localhost', command)
            self.assertIn('--dart-define=VYNIC_ENV=development', command)
            self.assertFalse(any('POS_SYNC_API_KEY' in x or 'BACKEND_URL_' in x for x in command))

    def test_explicit_developer_override(self):
        with patch.object(dev, 'public_build_config', return_value={'VYNIC_ENV': 'development', 'VYNIC_API_URL': 'http://api.vynic.localhost'}), patch.object(dev, 'workspace', return_value=Path('/tmp/synthetic-workspace')), patch.object(dev.subprocess, 'call', return_value=0) as runner, patch.dict(os.environ, {'VYNIC_DEV_API_URL': 'http://127.0.0.1:3000'}, clear=True), patch('sys.argv', ['dev.py', 'pos']):
            with self.assertRaises(SystemExit):
                dev.main()
            self.assertIn('--dart-define=VYNIC_API_URL=http://127.0.0.1:3000', runner.call_args.args[0])

    def test_production_config_consumption_and_https_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            output.mkdir()
            values = {'VYNIC_ENV': 'production', 'VYNIC_API_URL': 'https://api.vynic.ge'}
            with patch.object(product, 'public_build_config', return_value=values), patch.object(product, 'prepare', return_value=output), patch.object(product.shutil, 'which', return_value='/tmp/synthetic-flutter'), patch.object(product.subprocess, 'run') as runner, patch('sys.argv', ['product.py', 'build', 'manager', 'macos', '--output', str(output)]):
                product.main()
                command = runner.call_args_list[-1].args[0]
                self.assertIn('--dart-define=VYNIC_ENV=production', command)
                self.assertIn('--dart-define=VYNIC_API_URL=https://api.vynic.ge', command)
            with patch.object(product, 'public_build_config', return_value={'VYNIC_ENV': 'production', 'VYNIC_API_URL': 'http://api.vynic.localhost'}), patch.object(product, 'prepare') as prepare, patch('sys.argv', ['product.py', 'build', 'manager', 'macos', '--output', str(output)]):
                with self.assertRaises(SystemExit) as error:
                    product.main()
                self.assertEqual(error.exception.code, 2)
                prepare.assert_not_called()


if __name__ == '__main__':
    unittest.main()
