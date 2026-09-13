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
    self.assertIn(f'vynic_{product}',(output/'windows/CMakeLists.txt').read_text())
    self.assertNotIn('APP_ROLE',(output/'lib/main.dart').read_text())
 def test_manager_initializes_no_pos_services(self):
  source=(Path(__file__).resolve().parents[1]/'lib/main_manager.dart').read_text()
  for forbidden in ['DatabaseService.init','PosIngestServer','PrinterService','ManagerSyncService','dotenv']:
   self.assertNotIn(forbidden,source)
if __name__=='__main__':unittest.main()
