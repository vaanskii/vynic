"""Regression guard for isolated POS-native startup; no Manager identity edits."""
import tempfile
import unittest
from pathlib import Path
from product import prepare

class WindowsFullscreenTest(unittest.TestCase):
    def test_pos_uses_popup_monitor_bounds_and_manager_keeps_window_chrome(self):
        with tempfile.TemporaryDirectory() as directory:
            for product in ('pos', 'manager'):
                output = prepare(product, Path(directory) / product)
                cmake = (output / 'windows/runner/CMakeLists.txt').read_text()
                self.assertIn('if(BINARY_NAME STREQUAL "vynic_pos")', cmake)
                self.assertIn(f'set(BINARY_NAME "vynic_{product}")', (output / 'windows/CMakeLists.txt').read_text())
                native = (output / 'windows/runner/win32_window.cpp').read_text()
                fullscreen = native.split('#ifdef VYNIC_POS_FULLSCREEN', 1)[1].split('#else', 1)[0]
                self.assertIn('WS_POPUP', fullscreen)
                self.assertIn('monitor_info.rcMonitor', fullscreen)
                self.assertNotIn('Scale(', fullscreen)
                self.assertIn('WS_OVERLAPPEDWINDOW', native.split('#else', 1)[1])
                self.assertIn('case WM_DPICHANGED:', native)
                self.assertIn('case WM_DISPLAYCHANGE:', native)

if __name__ == '__main__':
    unittest.main()
