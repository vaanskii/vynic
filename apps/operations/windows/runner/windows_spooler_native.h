#ifndef RUNNER_WINDOWS_SPOOLER_NATIVE_H_
#define RUNNER_WINDOWS_SPOOLER_NATIVE_H_

#include "windows_spooler.h"

namespace vynic::printing {

// The same bounded, exact-identity adapter is used by the legacy Flutter
// channel and the Go-owned console helper. No Flutter dependency lives here.
class WinspoolApi final : public SpoolerApi {
public:
  Inventory ListQueues() override;
  bool Open(const std::wstring &queue, PrinterHandle *output) override;
  Inventory Inspect(PrinterHandle handle) override;
  uint32_t StartDocument(PrinterHandle handle, const std::wstring &document,
                         const std::wstring &datatype) override;
  bool StartPage(PrinterHandle handle) override;
  bool Write(PrinterHandle handle, const std::vector<uint8_t> &bytes,
             uint32_t *written) override;
  bool EndPage(PrinterHandle handle) override;
  bool EndDocument(PrinterHandle handle) override;
  bool Abort(PrinterHandle handle) override;
  bool Close(PrinterHandle handle) override;
  uint32_t LastError() override;
};

} // namespace vynic::printing

#endif // RUNNER_WINDOWS_SPOOLER_NATIVE_H_
