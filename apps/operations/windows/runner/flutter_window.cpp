#include "flutter_window.h"

#include <optional>
#include <wincred.h>
#include <algorithm>
#include <iomanip>
#include <sstream>
#include <shellapi.h>
#ifdef VYNIC_POS_FULLSCREEN
#include <shellapi.h>
#include "resource.h"
#endif

#include "flutter/generated_plugin_registrant.h"

namespace {
// Require OS-owned boot identity; never derive it from wall time minus uptime.
// A VM can reuse the boot GUID across reboot. Microsoft's BootId counter grows
// on every successful boot, so both values must match for offline continuity.
// https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-hvci-enablement
std::optional<std::string> LicenseBootId() {
  using Query = LONG (WINAPI*)(ULONG, PVOID, ULONG, PULONG);
  struct BootEnvironment { GUID id; ULONG firmware; ULONGLONG flags; } info{};
  const auto module = GetModuleHandleW(L"ntdll.dll");
  const auto query = module ? reinterpret_cast<Query>(
      GetProcAddress(module, "NtQuerySystemInformation")) : nullptr;
  ULONG returned = 0;
  if (!query || query(90, &info, static_cast<ULONG>(sizeof(info)), &returned) < 0 ||
      returned < sizeof(GUID)) return std::nullopt;
  DWORD boot_counter = 0;
  DWORD counter_size = sizeof(boot_counter);
  const auto counter_status = RegGetValueW(
      HKEY_LOCAL_MACHINE,
      L"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\PrefetchParameters",
      L"BootId", RRF_RT_REG_DWORD | RRF_SUBKEY_WOW6464KEY, nullptr,
      &boot_counter, &counter_size);
  if (counter_status != ERROR_SUCCESS || counter_size != sizeof(boot_counter) ||
      boot_counter == 0) return std::nullopt;
  const auto* bytes = reinterpret_cast<const unsigned char*>(&info.id);
  bool nonzero = false;
  std::ostringstream stream;
  stream << std::hex << std::setfill('0');
  for (size_t i = 0; i < sizeof(GUID); ++i) {
    nonzero = nonzero || bytes[i] != 0;
    stream << std::setw(2) << static_cast<unsigned>(bytes[i]);
  }
  stream << ':' << std::setw(8) << boot_counter;
  return nonzero ? std::optional<std::string>(stream.str()) : std::nullopt;
}
std::optional<std::string> LicenseArgument(const flutter::EncodableValue* args,
                                          const char* name) {
  const auto* values = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
  if (!values) return std::nullopt;
  const auto found = values->find(flutter::EncodableValue(name));
  if (found == values->end()) return std::nullopt;
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? std::optional<std::string>(*value) : std::nullopt;
}
}  // namespace

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
  windows_spooler_channel_ = std::make_unique<WindowsSpoolerChannel>(
      flutter_controller_->engine()->messenger(), GetHandle());
  license_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ge.vynic/license",
      &flutter::StandardMethodCodec::GetInstance());
  license_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "elapsed" || call.method_name() == "continuity") {
      const auto boot = LicenseBootId();
      if (!boot) { result->Error("continuity_unavailable", "Trusted clock unavailable"); return; }
      const auto elapsed = flutter::EncodableValue(static_cast<int64_t>(GetTickCount64()));
      if (call.method_name() == "elapsed") result->Success(elapsed);
      else result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("elapsedMs"), elapsed},
        {flutter::EncodableValue("bootId"), flutter::EncodableValue(*boot)}}));
    } else if (call.method_name() == "readAnchor" || call.method_name() == "writeAnchor") {
      const auto account = LicenseArgument(call.arguments(), "account");
      if (!account || account->size() != 64 || !std::all_of(account->begin(), account->end(),
          [](char c) { return (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9'); })) {
        result->Error("invalid_anchor", "Invalid vault account"); return;
      }
      std::wstring target = L"Vynic/SubscriptionLicense/";
      target.append(account->begin(), account->end());
      if (call.method_name() == "readAnchor") {
        PCREDENTIALW credential = nullptr;
        if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
          if (GetLastError() == ERROR_NOT_FOUND) result->Success();
          else result->Error("vault_unavailable", "License vault unavailable");
          return;
        }
        if (!credential->CredentialBlob || credential->CredentialBlobSize == 0 ||
            credential->CredentialBlobSize > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
          CredFree(credential);
          result->Error("invalid_anchor", "Invalid vault record"); return;
        }
        const std::string value(reinterpret_cast<const char*>(credential->CredentialBlob),
                                credential->CredentialBlobSize);
        CredFree(credential);
        result->Success(flutter::EncodableValue(value));
      } else {
        const auto value = LicenseArgument(call.arguments(), "value");
        if (!value || value->size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
          result->Error("invalid_anchor", "Invalid vault record"); return;
        }
        CREDENTIALW credential{};
        credential.Type = CRED_TYPE_GENERIC;
        credential.TargetName = target.data();
        credential.CredentialBlobSize = static_cast<DWORD>(value->size());
        credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(value->data()));
        credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
        if (CredWriteW(&credential, 0)) result->Success();
        else result->Error("vault_unavailable", "License vault unavailable");
      }
    } else if (call.method_name() == "purchase") {
      auto opened = ShellExecuteW(nullptr, L"open", L"https://vynic.ge/pricing", nullptr, nullptr, SW_SHOWNORMAL);
      if (reinterpret_cast<intptr_t>(opened) > 32) result->Success();
      else result->Error("open_failed", "Could not open website");
    } else { result->NotImplemented(); }
  });
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
  license_channel_.reset();
  windows_spooler_channel_.reset();
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
  if (windows_spooler_channel_ && windows_spooler_channel_->HandleMessage(message))
    return 0;
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
