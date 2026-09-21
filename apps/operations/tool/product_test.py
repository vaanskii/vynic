import tempfile,unittest
from pathlib import Path
from product import prepare
class ProductTest(unittest.TestCase):
 def test_distinct_fixed_entrypoints_native_identity_and_no_env(self):
  with tempfile.TemporaryDirectory() as directory:
   for product in ['pos','manager']:
    output=prepare(product,Path(directory)/product)
    self.assertEqual((output/'lib/main.dart').read_text(),f"export 'main_{product}.dart';\n")
    self.assertNotIn('.env',(output/'pubspec.yaml').read_text())
    self.assertNotIn('data/menu.json',(output/'pubspec.yaml').read_text())
    self.assertFalse(list(output.rglob('.env*')))
    native=(output/'windows/runner/main.cpp').read_text()
    self.assertIn(f'ge.vynic.{product}',native)
    self.assertIn(f'ge.vynic.{product}',(output/'macos/Runner/Configs/AppInfo.xcconfig').read_text())
    self.assertIn(f'vynic_{product}',(output/'windows/CMakeLists.txt').read_text())
    self.assertNotIn('APP_ROLE',(output/'lib/main.dart').read_text())
    rc=(output/'windows/runner/Runner.rc').read_text()
    self.assertIn('\"Vynic\"' if product=='pos' else '\"vanski\"',rc)
    self.assertIn(f'vynic_{product}.exe',rc)
 def test_manager_takes_its_own_icon_and_pos_keeps_the_checked_in_one(self):
  source=Path(__file__).resolve().parents[1]
  overlay=source/'branding/manager'
  slots=[icon.relative_to(overlay) for icon in overlay.rglob('*') if icon.is_file()]
  self.assertTrue(any(slot.suffix=='.ico' for slot in slots))
  with tempfile.TemporaryDirectory() as directory:
   for product in ['pos','manager']:
    output=prepare(product,Path(directory)/product)
    for slot in slots:
     expected=(overlay if product=='manager' else source)/slot
     self.assertEqual((output/slot).read_bytes(),expected.read_bytes(),f'{product} {slot}')
 def test_manager_initializes_no_pos_services(self):
  source=(Path(__file__).resolve().parents[1]/'lib/main_manager.dart').read_text()
  for forbidden in ['DatabaseService.init','PosIngestServer','PrinterService','ManagerSyncService','dotenv']:
   self.assertNotIn(forbidden,source)
if __name__=='__main__':unittest.main()
