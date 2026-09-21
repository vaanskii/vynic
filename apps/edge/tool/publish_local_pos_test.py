import json
import base64
import hashlib
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import publish_local_pos as p

class PublisherTests(unittest.TestCase):
    def test_guest_script_uses_literal_paths_hash_exit_check_and_build_mutex(self):
        self.assertEqual(p.ps_quote("O'Brien $HOME"), "'O''Brien $HOME'")
        script=p.build_script('https://172.20.10.2:8443','a'*64,r"\\Mac\Home\O'Brien\input\.candidate",'abc')
        for required in ('Get-FileHash',"O''Brien",'$LASTEXITCODE -ne 0','VynicLocalPOSPublisher'):
            self.assertIn(required,script)
        for forbidden in ('Stop-Process','SkipCertificateCheck','private/'):
            self.assertNotIn(forbidden,script)

    def test_concurrent_publish_fails_without_queuing_next_release(self):
        with tempfile.TemporaryDirectory() as d:
            with p.publication_lock(Path(d)):
                with self.assertRaisesRegex(RuntimeError,'already running'):
                    with p.publication_lock(Path(d)): self.fail('duplicate acquired')

    def test_production_distribution_is_refused_before_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'public').mkdir()
            (root/'.vynic-local-release-lab').touch()
            (root/'public/distribution.json').write_text(json.dumps({'channel':'production'}))
            with patch.object(p,'shared_path',return_value='share'):
                with self.assertRaisesRegex(ValueError,'local-development'):
                    p.validate_root(root)
            self.assertFalse((root/'state.json').exists())

    def test_validated_transfer_atomically_replaces_only_input_zip(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'input').mkdir()
            old=root/'input/vynic-pos.zip';old.write_bytes(b'old')
            incoming=root/'input/.candidate';incoming.write_bytes(b'new')
            state={'posVersion':'1.0.8','posRelease':9,'posReceipt':{}}
            (root/'state.json').write_text(json.dumps(state))
            def validate(path, expected):
                self.assertEqual(old.read_bytes(),b'old')
                self.assertEqual(path.read_bytes(),b'new')
                self.assertEqual(expected,state)
            with patch.object(p.lab,'pos_receipt',side_effect=validate):
                p.accept_bundle(SimpleNamespace(root=root),incoming,state)
            self.assertEqual(old.read_bytes(),b'new')
            self.assertFalse(incoming.exists())
            self.assertEqual(json.loads((root/'state.json').read_text()),state)

    def test_metadata_renewal_keeps_pinned_binary_identity_and_checks_hash(self):
        def envelope(payload):
            return json.dumps({'payload':base64.b64encode(json.dumps(payload).encode()).decode()}).encode()
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            for name in ('public/pos/releases','public/repair','public/artifacts','work'):
                (root/name).mkdir(parents=True,exist_ok=True)
            data=b'unchanged signed artifact'
            (root/'public/artifacts/pos.zip').write_bytes(data)
            manifest={'product':'vynic-pos','version':'1.0.7','release':8,
                      'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),
                      'url':'https://10.10.10.3:8443/artifacts/pos.zip','expires':'2000-01-01T00:00:00Z'}
            path=root/'public/pos/releases/1.0.7.json';path.write_bytes(envelope(manifest))
            def signer(args, **kwargs):
                source=Path(args[args.index('--manifest')+1])
                return SimpleNamespace(stdout=envelope(json.loads(source.read_text())))
            with patch.object(p.lab,'run',side_effect=signer):
                p.lab.renew_lab_metadata(SimpleNamespace(root=root))
            updated=json.loads(base64.b64decode(json.loads(path.read_bytes())['payload']))
            self.assertNotEqual(updated['expires'],manifest['expires'])
            updated['expires']=manifest['expires'];self.assertEqual(updated,manifest)
            (root/'public/artifacts/pos.zip').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'artifact changed'):
                p.lab.renew_lab_metadata(SimpleNamespace(root=root))

    def test_publication_refuses_reused_version_or_feed_downgrade(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'public/pos/releases').mkdir(parents=True)
            artifact=root/'pos.zip'; artifact.write_bytes(b'published POS')
            manifest={'version':'1.0.8','release':9,'sha256':p.lab.digest(artifact),'size':artifact.stat().st_size}
            envelope=json.dumps({'payload':base64.b64encode(json.dumps(manifest).encode()).decode()})
            (root/'public/pos/releases/1.0.8.json').write_text(envelope)
            (root/'public/pos/manifest.json').write_text(envelope)
            p.lab.validate_publication_identity(root,'1.0.8',9,artifact)
            artifact.write_bytes(b'different POS with same receipt')
            with self.assertRaisesRegex(ValueError,'immutable'):
                p.lab.validate_publication_identity(root,'1.0.8',9,artifact)
            for version,release in [('1.0.7',8),('1.0.9',9),('1.0.7',10)]:
                with self.assertRaises(ValueError):
                    p.lab.validate_publication_identity(root,version,release,artifact)
            p.lab.validate_publication_identity(root,'1.0.9',10,artifact)
            self.assertEqual((root/'public/pos/manifest.json').read_text(),envelope)

    def test_network_allowlist(self):
        with self.assertRaises(ValueError): p.select_ip('203.0.113.1')
        self.assertEqual(p.select_ip('172.20.10.2'),'172.20.10.2')

    def test_bad_bundle_preserves_previous_input(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'input').mkdir()
            old=root/'input/vynic-pos.zip';old.write_bytes(b'old')
            incoming=root/'input/.candidate';incoming.write_bytes(b'bad')
            state={'posVersion':'1.0.8','posRelease':9,'posReceipt':{}}
            (root/'state.json').write_text(json.dumps(state))
            with self.assertRaises(Exception): p.accept_bundle(SimpleNamespace(root=root),incoming,state)
            self.assertEqual(old.read_bytes(),b'old')

    def test_changed_release_refuses_transfer(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'state.json').write_text(json.dumps({'posVersion':'1.0.9'}))
            with self.assertRaisesRegex(RuntimeError,'changed during the build'):
                p.accept_bundle(SimpleNamespace(root=root),root/'candidate',{'posVersion':'1.0.8'})

    def scenario(self, root, pending):
        for name in ('logs','input','public'): (root/name).mkdir()
        (root/'input/vynic-pos.zip').write_bytes(b'old')
        (root/'public/build-pos.cmd').write_bytes(b'command')
        state={'posVersion':'1.0.8','posRelease':9,'posUpdatePending':pending,
               'posReceipt':{'sourceSha256':'same','apiOrigin':'http://172.20.10.2:3000'}}
        (root/'state.json').write_text(json.dumps(state))
        return SimpleNamespace(root=root,origin='https://172.20.10.2:8443',api_origin='http://172.20.10.2:3000')

    def test_build_failure_never_publishes(self):
        with tempfile.TemporaryDirectory() as d:
            a=self.scenario(Path(d),True)
            with patch.object(p,'ensure_vm'),patch.object(p,'shared_path',return_value='share'),patch.object(p,'guest',side_effect=[None,RuntimeError('build failed')]),patch.object(p.lab,'start'),patch.object(p.lab,'prepare_pos_source',return_value=('1.0.8','same','source.zip')),patch.object(p.lab,'prepare_pos_update'),patch.object(p.lab,'publish') as publish:
                with self.assertRaisesRegex(RuntimeError,'build failed'): p.publish_local(a,'prlctl','Windows')
                publish.assert_not_called()
            self.assertEqual((a.root/'input/vynic-pos.zip').read_bytes(),b'old')
            self.assertTrue(json.loads((a.root/'state.json').read_text())['posUpdatePending'])

    def test_same_source_reuses_release_without_build_or_bump(self):
        with tempfile.TemporaryDirectory() as d:
            a=self.scenario(Path(d),False)
            with patch.object(p,'ensure_vm'),patch.object(p,'shared_path',return_value='share'),patch.object(p,'guest') as guest,patch.object(p.lab,'start'),patch.object(p.lab,'prepare_pos_source',return_value=('1.0.8','same','source.zip')),patch.object(p.lab,'prepare_pos_update') as prepare,patch.object(p.lab,'pos_receipt'),patch.object(p.lab,'publish') as publish,patch.object(p.lab,'verify') as verify:
                result=p.publish_local(a,'prlctl','Windows')
                prepare.assert_not_called();self.assertEqual(guest.call_count,1)
                publish.assert_called_once_with(a);verify.assert_called_once_with(a)
                self.assertEqual(result['posRelease'],9)

if __name__=='__main__': unittest.main()
