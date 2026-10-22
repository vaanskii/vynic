#include "windows_spooler.h"

#include <algorithm>
#include <iostream>
#include <utility>

namespace vynic::printing {
namespace {

class PrinterScope {
 public:
  PrinterScope(SpoolerApi& api, PrinterHandle handle)
      : api_(api), handle_(handle) {}
  ~PrinterScope() {
    // Exceptional paths still release the handle. Normal paths report cleanup
    // failures in the typed result rather than losing the original failure.
    if (!handle_) return;
    if (document_open && !api_.Abort(handle_))
      std::cerr << "Vynic spooler exception cleanup: AbortPrinter failed ("
                << api_.LastError() << ")\n";
    if (!api_.Close(handle_))
      std::cerr << "Vynic spooler exception cleanup: ClosePrinter failed ("
                << api_.LastError() << ")\n";
  }

  Submission Finish(Submission result, bool attempted) {
    if (result.error && document_open && !api_.Abort(handle_)) {
      result.error->message += "; AbortPrinter cleanup failed (" +
                               std::to_string(api_.LastError()) + ")";
    }
    document_open = false;
    if (!api_.Close(handle_)) {
      const auto code = api_.LastError();
      if (result.error) {
        result.error->message +=
            "; ClosePrinter cleanup failed (" + std::to_string(code) + ")";
      } else {
        result.error =
            Error{"closePrinter", attempted, code,
                  "ClosePrinter failed after RAW document acceptance"};
      }
    }
    handle_ = 0;
    return result;
  }

  bool document_open = false;

 private:
  SpoolerApi& api_;
  PrinterHandle handle_;
};

}  // namespace

bool ValidText(const std::wstring& value, size_t max_length) {
  return !value.empty() && value.size() <= max_length &&
         std::any_of(value.begin(), value.end(),
                     [](wchar_t c) { return c > L' '; }) &&
         std::all_of(value.begin(), value.end(),
                     [](wchar_t c) { return c >= 32 && c != 127; });
}

Submission SubmitRaw(SpoolerApi& api, const Queue& expected_queue,
                     const std::vector<uint8_t>& bytes,
                     const std::wstring& document_name,
                     bool* submission_attempted,
                     const std::function<bool()>& may_start) {
  if (submission_attempted) *submission_attempted = false;
  Submission result;
  auto fail = [&](const char* stage, bool attempted, uint32_t code,
                  const char* message) {
    result.error = Error{stage, attempted, code, message};
    return result;
  };
  if (!ValidText(expected_queue.name, kMaxQueueNameLength) ||
      !ValidText(expected_queue.driver, kMaxDescriptorLength) ||
      !ValidText(expected_queue.port, kMaxDescriptorLength) ||
      !ValidText(document_name, kMaxDocumentNameLength) || bytes.empty() ||
      bytes.size() > kMaxTransmissionBytes) {
    return fail("validate", false, 0, "Invalid RAW queue identity or payload");
  }
  auto inventory = api.ListQueues();
  if (inventory.error) {
    inventory.error->write_attempted = false;
    result.error = std::move(inventory.error);
    return result;
  }
  const auto matching =
      std::count_if(inventory.queues.begin(), inventory.queues.end(),
                    [&](const Queue& queue) {
                      return queue.name == expected_queue.name &&
                             queue.driver == expected_queue.driver &&
                             queue.port == expected_queue.port;
                    });
  if (inventory.queues.size() > kMaxQueues || matching != 1) {
    return fail(
        "selectQueue", false, 0,
        "Installed queue name, driver or port changed; review configuration");
  }
  if (may_start && !may_start()) {
    return fail("dispatch", false, 0,
                "RAW submission held before opening a queue");
  }
  PrinterHandle handle = 0;
  const bool opened = api.Open(expected_queue.name, &handle);
  const auto open_error = opened ? 0 : api.LastError();
  if (!handle) {
    return fail("openPrinter", false, open_error, "OpenPrinter failed");
  }
  PrinterScope scope(api, handle);
  if (!opened) {
    return scope.Finish(
        fail("openPrinter", false, open_error, "OpenPrinter failed"), false);
  }
  // Recheck the opened handle too, so editing a queue between enumeration and
  // OpenPrinter cannot silently change the configured destination.
  auto opened_inventory = api.Inspect(handle);
  if (opened_inventory.error) {
    result.error = std::move(opened_inventory.error);
    result.error->write_attempted = false;
    return scope.Finish(result, false);
  }
  if (opened_inventory.queues.size() != 1 ||
      opened_inventory.queues[0].name != expected_queue.name ||
      opened_inventory.queues[0].driver != expected_queue.driver ||
      opened_inventory.queues[0].port != expected_queue.port) {
    return scope.Finish(
        fail("selectQueue", false, 0,
             "Opened queue name, driver or port changed; review configuration"),
        false);
  }
  if (may_start && !may_start()) {
    return scope.Finish(fail("dispatch", false, 0,
                             "RAW submission held before starting a document"),
                        false);
  }
  // Set BEFORE StartDocPrinter: even a failed/throwing call is conservative.
  if (submission_attempted) *submission_attempted = true;
  result.job_id = api.StartDocument(handle, document_name, L"RAW");
  if (!result.job_id) {
    return scope.Finish(fail("startDocPrinter", true, api.LastError(),
                             "StartDocPrinter failed"),
                        true);
  }
  scope.document_open = true;
  if (!api.StartPage(handle)) {
    return scope.Finish(fail("startPagePrinter", true, api.LastError(),
                             "StartPagePrinter failed"),
                        true);
  }
  const bool wrote = api.Write(handle, bytes, &result.bytes_written);
  const auto write_error = wrote ? 0 : api.LastError();
  if (!wrote || result.bytes_written != bytes.size()) {
    return scope.Finish(
        fail("writePrinter", true, write_error,
             "WritePrinter failed or accepted only part of the RAW bytes"),
        true);
  }
  if (!api.EndPage(handle)) {
    return scope.Finish(
        fail("endPagePrinter", true, api.LastError(), "EndPagePrinter failed"),
        true);
  }
  if (!api.EndDocument(handle)) {
    return scope.Finish(
        fail("endDocPrinter", true, api.LastError(), "EndDocPrinter failed"),
        true);
  }
  scope.document_open = false;
  return scope.Finish(result, true);
}

}  // namespace vynic::printing
