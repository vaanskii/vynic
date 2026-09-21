import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from windows_pe import resource,version_info,icon_resources

class WindowsPETest(unittest.TestCase):
    def test_version_info_has_fixed_identity_and_numeric_version(self):
        v=version_info('Vynic Setup','VynicSetup.exe','1.2.3.4')
        self.assertEqual(struct.unpack_from('<H',v)[0],len(v))
        for value in ['CompanyName','Vynic','FileDescription','Vynic Setup','OriginalFilename','VynicSetup.exe','1.2.3.4']:
            self.assertIn((value+'\0').encode('utf-16le'),v)
        self.assertIn(struct.pack('<II',0x00010002,0x00030004),v)
        for bad in ['1.0','1.0.0.65536','1.0.0.-1']:
            with self.assertRaises(ValueError):version_info('p','p.exe',bad)

    def test_coff_relocations_cover_both_resources(self):
        obj=resource({24:b'<manifest/>',16:version_info('Vynic Edge','VynicEdge.exe','1.0.0.0')})
        self.assertEqual(struct.unpack_from('<H',obj)[0],0x8664)
        rawsize,raw,reloc=struct.unpack_from('<III',obj,36)
        self.assertEqual(struct.unpack_from('<H',obj,52)[0],2)
        for i in range(2):
            at,symbol,kind=struct.unpack_from('<IIH',obj,reloc+i*10)
            pointer,size=struct.unpack_from('<II',obj,raw+at)
            self.assertLessEqual(pointer+size,rawsize)
            self.assertEqual((symbol,kind),(0,3))

    def test_all_existing_brand_icon_sizes_are_embedded(self):
        ico = (Path(__file__).resolve().parents[2]/'operations/windows/runner/resources/app_icon.ico').read_bytes()
        icons = icon_resources(ico)
        count = struct.unpack_from('<H', ico, 4)[0]
        self.assertEqual(len(icons), count+1)
        group = icons[(14, 1)]
        self.assertEqual(struct.unpack_from('<HHH', group), (0, 1, count))
        for i in range(count):
            size, offset = struct.unpack_from('<II', ico, 6+i*16+8)
            self.assertEqual(icons[(3, i+1)], ico[offset:offset+size])
            self.assertEqual(struct.unpack_from('<IH', group, 6+i*14+8), (size, i+1))
        obj = resource({24:b'<manifest/>', **icons})
        self.assertEqual(struct.unpack_from('<H', obj, 52)[0], count+2)
        for bad in [b'', ico[:10], ico[:-1]]:
            with self.assertRaises(ValueError): icon_resources(bad)

    def test_signing_preflight_requires_all_products_and_public_cert_selector(self):
        from unittest.mock import patch
        spec=importlib.util.spec_from_file_location('signer',Path(__file__).with_name('sign-windows-release.py'))
        signer=importlib.util.module_from_spec(spec);spec.loader.exec_module(signer)
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);tool=root/'signtool.exe';tool.touch()
            files=[root/name for name in signer.PRODUCTS]
            for f in files:f.touch()
            def metadata(p):return {'resources':{(16,1,1033):version_info(signer.PRODUCTS[p.name],p.name,'1.0.0.0')}}
            with patch.object(signer,'inspect',side_effect=metadata):
                signer.validate_inputs(files,tool,'a'*40,'https://timestamp.example.test')
                for subset,key,url in [(files[:2],'a'*40,'https://timestamp.example.test'),(files,'private-key','https://timestamp.example.test'),(files,'a'*40,'http://timestamp.example.test')]:
                    with self.assertRaises(ValueError):signer.validate_inputs(subset,tool,key,url)

    def test_no_interpreters_in_runtime_source(self):
        root=Path(__file__).resolve().parents[1]
        for folder in ['cmd/setup','internal/setup']:
            for file in (root/folder).glob('*.go'):
                if file.name.endswith('_test.go'):continue
                text=file.read_text().lower()
                for forbidden in ['powershell.exe','cmd.exe','-encodedcommand','wscript.shell','dialog.ps1']:
                    self.assertNotIn(forbidden,text,str(file))

if __name__=='__main__':unittest.main()
