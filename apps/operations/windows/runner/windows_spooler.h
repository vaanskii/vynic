#ifndef RUNNER_WINDOWS_SPOOLER_H_
#define RUNNER_WINDOWS_SPOOLER_H_

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace vynic::printing {

constexpr size_t kMaxTransmissionBytes = 8 * 1024 * 1024 + 1024;
constexpr size_t kMaxQueueNameLength = 255;
constexpr size_t kMaxDescriptorLength = 1024;
constexpr size_t kMaxDocumentNameLength = 255;
constexpr size_t kMaxQueues = 1024;

struct Queue {
  std::wstring name;
  std::wstring driver;
  std::wstring port;
};

struct Error {
  std::string stage;
  // StartDocPrinter can create a job even without a successful WritePrinter.
  bool write_attempted;
  uint32_t windows_error;
  std::string message;
};

struct Inventory {
  std::vector<Queue> queues;
  std::optional<Error> error;
};

struct Submission {
  uint32_t job_id = 0;
  uint32_t bytes_written = 0;
  std::optional<Error> error;
};

using PrinterHandle = uintptr_t;

// A narrow injectable Winspool seam. Tests never load Winspool or print a job.
class SpoolerApi {
 public:
  virtual ~SpoolerApi() = default;
  virtual Inventory ListQueues() = 0;
  virtual bool Open(const std::wstring& queue, PrinterHandle* handle) = 0;
  virtual Inventory Inspect(PrinterHandle handle) = 0;
  virtual uint32_t StartDocument(PrinterHandle handle,
                                 const std::wstring& document,
                                 const std::wstring& datatype) = 0;
  virtual bool StartPage(PrinterHandle handle) = 0;
  virtual bool Write(PrinterHandle handle, const std::vector<uint8_t>& bytes,
                     uint32_t* written) = 0;
  virtual bool EndPage(PrinterHandle handle) = 0;
  virtual bool EndDocument(PrinterHandle handle) = 0;
  virtual bool Abort(PrinterHandle handle) = 0;
  virtual bool Close(PrinterHandle handle) = 0;
  virtual uint32_t LastError() = 0;
};

bool ValidText(const std::wstring& value, size_t max_length);

// Exactly one submission, with no retry after a partial or failed native call.
Submission SubmitRaw(SpoolerApi& api, const Queue& expected_queue,
                     const std::vector<uint8_t>& bytes,
                     const std::wstring& document_name,
                     bool* submission_attempted = nullptr,
                     const std::function<bool()>& may_start = {});

}  // namespace vynic::printing

#endif  // RUNNER_WINDOWS_SPOOLER_H_
