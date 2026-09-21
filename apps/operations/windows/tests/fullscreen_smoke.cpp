// Native geometry test. Build twice with/without VYNIC_POS_FULLSCREEN using
// tool/windows-window-test.cmd after preparing/building a Windows product.
#include "win32_window.h"
#include <iostream>

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Win32Window window;
  if (!window.Create(L"Vynic window geometry test", {10, 10}, {1280, 720})) return 1;
  HWND hwnd = window.GetHandle();
  const auto style = GetWindowLongPtr(hwnd, GWL_STYLE);
#ifdef VYNIC_POS_FULLSCREEN
  if ((style & WS_CAPTION) != 0 || (style & WS_THICKFRAME) != 0 ||
      (style & WS_POPUP) == 0) return 2;
  auto fillsMonitor = [hwnd]() {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    RECT actual{};
    return GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &info) &&
           GetWindowRect(hwnd, &actual) && EqualRect(&actual, &info.rcMonitor);
  };
  if (!fillsMonitor()) return 3;
  // DPI's suggested window rectangle must not shrink a fullscreen POS.
  RECT suggestion{10, 10, 1000, 600};
  SendMessage(hwnd, WM_DPICHANGED, MAKELONG(144, 144), reinterpret_cast<LPARAM>(&suggestion));
  if (!fillsMonitor()) return 4;
  SendMessage(hwnd, WM_DISPLAYCHANGE, 0, 0);
  if (!fillsMonitor()) return 5;
  std::cout << "POS: borderless monitor bounds, DPI/display-change checks passed\n";
#else
  if ((style & WS_CAPTION) != WS_CAPTION || (style & WS_THICKFRAME) == 0) return 6;
  std::cout << "Manager: normal window chrome preserved\n";
#endif
  window.Destroy();
  return 0;
}
