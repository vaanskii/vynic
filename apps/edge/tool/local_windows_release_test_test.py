import importlib.util
import json
import base64
import re
from unittest.mock import patch
from pathlib import Path
import stat
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('lab', Path(__file__).with_name('local_windows_release_test.py'))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class LocalReleaseTests(unittest.TestCase):
    def test_local_pos_update_preserves_baseline_and_generates_http_opt_in(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'public').mkdir()
            (root/'public/bootstrap.json').write_text('pinned baseline')
            state = {'posVersion':'1.0.0','posRelease':1,'edgeArtifact':'pinned-edge.zip','edgeRelease':2}
            lab.json_write(root/'state.json', state)
            args = type('Args', (), {'root':root,'origin':'https://10.10.10.3:8443','api_origin':'http://10.10.10.3:3000'})()
            with patch.object(lab,'prepare_pos_source',return_value=('1.0.0','abc','pos-source-abc.zip')):
                lab.prepare_pos_update(args)
                lab.prepare_pos_update(args)
            updated = json.loads((root/'state.json').read_text())
            self.assertEqual(updated['posVersion'],'1.0.1')
            self.assertEqual(updated['posRelease'],2)
            self.assertEqual(updated['edgeArtifact'],'pinned-edge.zip')
            self.assertEqual((root/'public/bootstrap.json').read_text(),'pinned baseline')
            cmd = (root/'public/build-pos.cmd').read_text()
            self.assertIn('--dart-define=VYNIC_API_URL=http://10.10.10.3:3000',cmd)
            self.assertIn('--dart-define=VYNIC_ENV=development',cmd)
            self.assertIn('--dart-define=VYNIC_LOCAL_WINDOWS_LAB=true',cmd)
            self.assertIn('https://10.10.10.3:8443/pos-source-',cmd)
            encoded = re.search(r"FromBase64String\('([^']+)'\)",cmd).group(1)
            self.assertEqual(json.loads(base64.b64decode(encoded)), updated['posReceipt'])

    def test_run_attempts_publication_of_copied_pending_zip(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'input').mkdir()
            (root/'input/vynic-pos.zip').write_bytes(b'validated separately')
            state={'posUpdate':True,'posUpdatePending':True,'posReceipt':{'apiOrigin':'http://10.10.10.3:3000'}}
            lab.json_write(root/'state.json',state)
            args=type('Args',(),{'root':root,'api_origin':'http://10.10.10.3:3000'})()
            with patch.object(lab,'write_pos_command'),patch.object(lab,'publish') as publish:
                lab.prepare(args)
                publish.assert_called_once_with(args)

    def test_second_network_build_uses_separate_api_and_https_download(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            args = type('Args', (), {'root': root, 'origin': 'https://172.20.10.2:8443',
                                    'api_origin': 'http://172.20.10.2:3000'})()
            state = {'posVersion': '1.0.5', 'posRelease': 6, 'posReceipt': {'sourceSha256': 'abc'}}
            lab.write_pos_command(args, state)
            cmd = (root/'public/build-pos.cmd').read_text()
            self.assertIn('--dart-define=VYNIC_API_URL=http://172.20.10.2:3000', cmd)
            self.assertIn('--build-name=1.0.5 --build-number=6', cmd)
            self.assertIn('https://172.20.10.2:8443/pos-source-abc.zip', cmd)
            self.assertIn('Add-Type -AssemblyName System.IO.Compression;', cmd)
            self.assertIn('.Replace([char]92,[char]47)', cmd)

    def test_profile_selection_keeps_original_distribution_and_rejects_unknown_lan(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            lab.json_write(root/'state.json', {'origin': 'https://10.10.10.3:8443'})
            profile = root/'public/networks/172.20.10.2'
            lab.json_write(profile/'distribution.json', {})
            args = type('Args', (), {'root': root, 'origin': 'https://172.20.10.2:8443', 'ip': '172.20.10.2'})()
            self.assertEqual(lab.network_profile(args), (profile, args.origin+'/networks/172.20.10.2'))
            args.origin = 'https://10.10.10.3:8443'
            self.assertEqual(lab.network_profile(args), (root/'public', args.origin))
            args.origin = 'https://192.168.1.8:8443'; args.ip = '192.168.1.8'
            with self.assertRaises(ValueError):
                lab.network_profile(args)

    def test_network_mirrors_refuse_production_channel(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            lab.json_write(root/'state.json', {})
            lab.json_write(root/'public/distribution.json', {'channel': 'production'})
            args = type('Args', (), {'root': root})()
            with self.assertRaisesRegex(ValueError, 'development-only'):
                lab.publish_networks(args)

    def test_windows_zip_repack_preserves_bytes_and_canonical_root(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/'pos.zip'
            pe = bytearray(1024*1024)
            pe[:2] = b'MZ'
            struct.pack_into('<I', pe, 60, 64)
            pe[64:68] = b'PE\0\0'
            struct.pack_into('<H', pe, 68, 0x8664)
            contents = {'vynic_pos.exe': bytes(pe), 'flutter_windows.dll': bytes(pe),
                        r'data\icudtl.dat': b'icu', r'data\flutter_assets\a': b'asset',
                        'local-build.json': b'{}'}
            with zipfile.ZipFile(path, 'w') as z:
                for name, data in contents.items():
                    z.writestr(name, data)
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                lab.pos_receipt(path, {'posReceipt': {}})
            lab.repack_pos(path, {'posReceipt': {}})
            with zipfile.ZipFile(path) as z:
                self.assertEqual(set(z.namelist()), {n.replace(chr(92), '/') for n in contents})
                for name, data in contents.items():
                    self.assertEqual(z.read(name.replace(chr(92), '/')), data)

    def test_windows_paths_reject_unsafe_aliases_and_links(self):
        for name in [r'..\evil', r'C:\evil', r'\server\file', r'a\..\b',
                     r'a\NUL.txt', r'a\COM1.exe', r'a\x. ', r'a\b:stream',
                     r'a\\b', '/root', 'a/./b', 'a\x00b']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                lab.checked_zip_names([zipfile.ZipInfo(name)], True)
        for names in [[r'data\a', 'DATA/a'], ['data', r'data\a']]:
            with self.assertRaises(ValueError):
                lab.checked_zip_names([zipfile.ZipInfo(n) for n in names], True)
        link = zipfile.ZipInfo('link')
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(ValueError):
            lab.checked_zip_names([link], True)

    def test_source_zip_is_repeatable_and_rejects_keys(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);source=root/'source';source.mkdir()
            (source/'app.dart').write_text('current source')
            lab.zip_tree(source,root/'a.zip');lab.zip_tree(source,root/'b.zip')
            self.assertEqual(lab.digest(root/'a.zip'),lab.digest(root/'b.zip'))
            (source/'release.pem').write_text('not a real key')
            with self.assertRaisesRegex(ValueError,'Secret-shaped'):
                lab.zip_tree(source,root/'c.zip')

    def test_missing_pos_does_not_publish_fake_bootstrap(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'public').mkdir();(root/'input').mkdir()
            lab.json_write(root/'state.json',{'posVersion':'1.0.0'})
            args=type('Args',(),{'root':root})()
            self.assertFalse(lab.publish(args))
            self.assertFalse((root/'public/bootstrap.json').exists())
            self.assertEqual(json.loads((root/'public/status.json').read_text())['state'],'WAITING_FOR_REAL_WINDOWS_POS')

    def test_synthetic_windows_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'fake.zip';receipt={'product':'vynic-pos'}
            with zipfile.ZipFile(path,'w') as z:
                for file in ['vynic_pos.exe','flutter_windows.dll','data/icudtl.dat','data/flutter_assets/a']:
                    z.writestr(file,b'not a real Windows build')
                z.writestr('local-build.json',json.dumps(receipt))
            with self.assertRaisesRegex(ValueError,'Synthetic'):
                lab.pos_receipt(path,{'posReceipt':receipt})

    def test_wrong_source_receipt_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'old.zip'
            with zipfile.ZipFile(path,'w') as z:
                for file in ['vynic_pos.exe','flutter_windows.dll','data/icudtl.dat','data/flutter_assets/a']:
                    z.writestr(file,b'not executed')
                z.writestr('local-build.json','{}')
            with self.assertRaisesRegex(ValueError,'current source'):
                lab.pos_receipt(path,{'posReceipt':{'sourceSha256':'expected'}})

if __name__=='__main__':unittest.main()
