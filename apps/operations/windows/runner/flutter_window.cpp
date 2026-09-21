#include "flutter_window.h"

#include <optional>
#ifdef VYNIC_POS_FULLSCREEN
#include <shellapi.h>
#include "resource.h"
#endif

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
#ifdef VYNIC_POS_FULLSCREEN
    AddTrayIcon();
#endif
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
#ifdef VYNIC_POS_FULLSCREEN
  RemoveTrayIcon();
#endif
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
#ifdef VYNIC_POS_FULLSCREEN
  static const UINT taskbar_created = RegisterWindowMessage(L"TaskbarCreated");
  if (message == taskbar_created) {
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }
  if (message == WM_APP + 17) {
    if (lparam == WM_LBUTTONDBLCLK) ShowFromTray();
    if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      HMENU menu = CreatePopupMenu();
      if (!menu) return 0;
      AppendMenuW(menu, MF_STRING, 1, L"Vynic POS-ის გახსნა");
      AppendMenuW(menu, MF_STRING, 2, L"აპლიკაციიდან გასვლა");
      POINT point;
      GetCursorPos(&point);
      SetForegroundWindow(hwnd);
      const UINT action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                         point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      PostMessage(hwnd, WM_NULL, 0, 0);
      if (action == 1 || action == 2) ShowFromTray();
      // WM_CLOSE follows Flutter's existing confirmed clean-exit handler.
      // Never terminate the process or signal the Edge host from the tray.
      if (action == 2) PostMessage(hwnd, WM_CLOSE, 0, 0);
    }
    return 0;
  }
#endif
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#ifdef VYNIC_POS_FULLSCREEN
void FlutterWindow::AddTrayIcon() {
  if (tray_added_) return;
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = WM_APP + 17;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"Vynic POS");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (!tray_added_) OutputDebugStringW(L"Vynic POS: notification icon could not be added\n");
}
void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  if (!Shell_NotifyIconW(NIM_DELETE, &data))
    OutputDebugStringW(L"Vynic POS: notification icon removal failed\n");
  tray_added_ = false;
}
void FlutterWindow::ShowFromTray() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}
#endif
