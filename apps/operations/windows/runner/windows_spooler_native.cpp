#include "windows_spooler_native.h"

#include <windows.h>
#include <winspool.h>

#include <algorithm>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace vynic::printing {
namespace {
constexpr DWORD kMaxInventoryBytes = 8 * 1024 * 1024;

HANDLE Native(PrinterHandle handle) { return reinterpret_cast<HANDLE>(handle); }

Inventory InventoryError(const char *stage, DWORD code, const char *message) {
  return {{}, Error{stage, false, code, message}};
}

// Winspool promises strings in its returned buffer. Bounds remain explicit,
// including malformed provider responses, rather than scanning unchecked.
std::optional<std::wstring>
ReadSpoolerString(const std::vector<uint8_t> &buffer, const wchar_t *text,
                  size_t max_length) {
  if (!text)
    return std::wstring();
  const auto begin = reinterpret_cast<uintptr_t>(buffer.data());
  const auto end = begin + buffer.size();
  const auto address = reinterpret_cast<uintptr_t>(text);
  if (address < begin || address >= end || address % alignof(wchar_t) != 0)
    return std::nullopt;
  const auto available = (end - address) / sizeof(wchar_t);
  const auto limit = std::min(available, max_length + 1);
  for (size_t i = 0; i < limit; ++i) {
    if (text[i] == 0)
      return std::wstring(text, i);
  }
  return std::nullopt;
}

std::optional<Queue> ReadQueue(const std::vector<uint8_t> &buffer,
                               const PRINTER_INFO_2W &info) {
  const auto name = ReadSpoolerString(buffer, info.pPrinterName,
                                      vynic::printing::kMaxQueueNameLength);
  const auto driver = ReadSpoolerString(buffer, info.pDriverName,
                                        vynic::printing::kMaxDescriptorLength);
  const auto port = ReadSpoolerString(buffer, info.pPortName,
                                      vynic::printing::kMaxDescriptorLength);
  if (!name || !driver || !port ||
      !vynic::printing::ValidText(*name, vynic::printing::kMaxQueueNameLength))
    return std::nullopt;
  return Queue{*name, *driver, *port};
}

} // namespace

Inventory WinspoolApi::ListQueues() {
  DWORD needed = 0, returned = 0;
  const DWORD flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  const BOOL measured =
      EnumPrintersW(flags, nullptr, 2, nullptr, 0, &needed, &returned);
  const DWORD error = measured ? ERROR_SUCCESS : GetLastError();
  if (measured && needed == 0)
    return {};
  if ((!measured && error != ERROR_INSUFFICIENT_BUFFER) || needed == 0 ||
      needed > kMaxInventoryBytes) {
    return InventoryError("enumerate", error,
                          "Could not measure installed queues");
  }
  std::vector<uint8_t> buffer(needed);
  if (!EnumPrintersW(flags, nullptr, 2, buffer.data(), needed, &needed,
                     &returned))
    return InventoryError("enumerate", GetLastError(),
                          "Could not enumerate installed queues");
  if (returned > vynic::printing::kMaxQueues ||
      static_cast<size_t>(returned) * sizeof(PRINTER_INFO_2W) > buffer.size()) {
    return InventoryError("enumerate", ERROR_INVALID_DATA,
                          "Queue inventory exceeded bounds");
  }
  Inventory inventory;
  const auto *infos = reinterpret_cast<const PRINTER_INFO_2W *>(buffer.data());
  for (DWORD i = 0; i < returned; ++i) {
    auto queue = ReadQueue(buffer, infos[i]);
    if (!queue)
      return InventoryError("enumerate", ERROR_INVALID_DATA,
                            "Invalid installed queue descriptor");
    inventory.queues.push_back(std::move(*queue));
  }
  std::sort(inventory.queues.begin(), inventory.queues.end(),
            [](const Queue &a, const Queue &b) { return a.name < b.name; });
  return inventory;
}

bool WinspoolApi::Open(const std::wstring &queue, PrinterHandle *output) {
  HANDLE handle = nullptr;
  PRINTER_DEFAULTSW defaults{};
  defaults.DesiredAccess = PRINTER_ACCESS_USE;
  const BOOL opened =
      OpenPrinterW(const_cast<wchar_t *>(queue.c_str()), &handle, &defaults);
  *output = reinterpret_cast<PrinterHandle>(handle);
  return opened != FALSE;
}

Inventory WinspoolApi::Inspect(PrinterHandle handle) {
  DWORD needed = 0;
  const BOOL measured = GetPrinterW(Native(handle), 2, nullptr, 0, &needed);
  const DWORD error = measured ? ERROR_SUCCESS : GetLastError();
  if ((!measured && error != ERROR_INSUFFICIENT_BUFFER) ||
      needed < sizeof(PRINTER_INFO_2W) || needed > kMaxInventoryBytes) {
    return InventoryError("inspectPrinter", error,
                          "Could not measure opened queue identity");
  }
  std::vector<uint8_t> buffer(needed);
  if (!GetPrinterW(Native(handle), 2, buffer.data(), needed, &needed))
    return InventoryError("inspectPrinter", GetLastError(),
                          "Could not inspect opened queue identity");
  auto queue = ReadQueue(
      buffer, *reinterpret_cast<const PRINTER_INFO_2W *>(buffer.data()));
  if (!queue)
    return InventoryError("inspectPrinter", ERROR_INVALID_DATA,
                          "Invalid opened queue identity");
  return {{std::move(*queue)}, std::nullopt};
}

uint32_t WinspoolApi::StartDocument(PrinterHandle handle,
                                    const std::wstring &document,
                                    const std::wstring &datatype) {
  DOC_INFO_1W info{};
  info.pDocName = const_cast<wchar_t *>(document.c_str());
  info.pDatatype = const_cast<wchar_t *>(datatype.c_str());
  // No output-file path, shell invocation, command, or driver installation.
  return StartDocPrinterW(Native(handle), 1, reinterpret_cast<LPBYTE>(&info));
}
bool WinspoolApi::StartPage(PrinterHandle handle) {
  return StartPagePrinter(Native(handle)) != FALSE;
}
bool WinspoolApi::Write(PrinterHandle handle, const std::vector<uint8_t> &bytes,
                        uint32_t *written) {
  DWORD count = 0;
  const BOOL success =
      WritePrinter(Native(handle), const_cast<uint8_t *>(bytes.data()),
                   static_cast<DWORD>(bytes.size()), &count);
  *written = count;
  return success != FALSE;
}
bool WinspoolApi::EndPage(PrinterHandle handle) {
  return EndPagePrinter(Native(handle)) != FALSE;
}
bool WinspoolApi::EndDocument(PrinterHandle handle) {
  return EndDocPrinter(Native(handle)) != FALSE;
}
bool WinspoolApi::Abort(PrinterHandle handle) {
  return AbortPrinter(Native(handle)) != FALSE;
}
bool WinspoolApi::Close(PrinterHandle handle) {
  return ClosePrinter(Native(handle)) != FALSE;
}
uint32_t WinspoolApi::LastError() { return GetLastError(); }

} // namespace vynic::printing
