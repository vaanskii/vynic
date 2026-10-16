// Portable fake-only seam proof. No Winspool API is linked or invoked.
// clang++ -std=c++17 -Wall -Wextra -Werror windows_spooler_test.cpp
//   ../runner/windows_spooler.cpp -o /tmp/vynic-spooler-test
#include "../runner/windows_spooler.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace vynic::printing;

namespace {

const Queue kQueue{L"Synthetic ; $(unused)", L"Synthetic ESC/POS driver",
                   L"USB001"};
const std::vector<uint8_t> kBytes{0x1b, 0x40, 0x00, 0xff};
int assertions = 0;

void Require(bool condition, const char* description) {
  ++assertions;
  if (!condition) {
    std::cerr << "FAILED: " << description << "\n";
    std::exit(1);
  }
}

class FakeApi final : public SpoolerApi {
 public:
  std::string fail;
  Queue installed = kQueue;
  Queue opened = kQueue;
  bool throw_write = false;
  bool fail_abort = false;
  bool fail_close = false;
  bool short_write = false;
  bool return_handle_on_open_failure = false;
  bool duplicate = false;
  int opens = 0, inspections = 0, starts = 0, writes = 0;
  int start_pages = 0, end_pages = 0, ends = 0, aborts = 0, closes = 0;
  std::wstring queue_name, document_name, datatype;
  std::vector<uint8_t> received;

  Inventory ListQueues() override {
    if (fail == "enumerate")
      return {{},
              Error{"enumerate", false, 1722, "Synthetic unavailable spooler"}};
    return duplicate ? Inventory{{installed, installed}, std::nullopt}
                     : Inventory{{installed}, std::nullopt};
  }
  bool Open(const std::wstring& queue, PrinterHandle* handle) override {
    ++opens;
    queue_name = queue;
    *handle = fail != "openPrinter" || return_handle_on_open_failure ? 7 : 0;
    return fail != "openPrinter";
  }
  Inventory Inspect(PrinterHandle handle) override {
    Require(handle == 7, "inspect gets opened handle");
    ++inspections;
    if (fail == "inspectPrinter")
      return {{},
              Error{"inspectPrinter", false, 5, "Synthetic inspect failure"}};
    return {{opened}, std::nullopt};
  }
  uint32_t StartDocument(PrinterHandle handle, const std::wstring& document,
                         const std::wstring& type) override {
    Require(handle == 7, "start gets opened handle");
    ++starts;
    document_name = document;
    datatype = type;
    return fail == "startDocPrinter" ? 0 : 42;
  }
  bool StartPage(PrinterHandle) override {
    ++start_pages;
    return fail != "startPagePrinter";
  }
  bool Write(PrinterHandle, const std::vector<uint8_t>& bytes,
             uint32_t* written) override {
    ++writes;
    received = bytes;
    if (throw_write) throw std::runtime_error("Synthetic throwing write");
    *written = static_cast<uint32_t>(bytes.size() - (short_write ? 1 : 0));
    return fail != "writePrinter";
  }
  bool EndPage(PrinterHandle) override {
    ++end_pages;
    return fail != "endPagePrinter";
  }
  bool EndDocument(PrinterHandle) override {
    ++ends;
    return fail != "endDocPrinter";
  }
  bool Abort(PrinterHandle) override {
    ++aborts;
    return !fail_abort;
  }
  bool Close(PrinterHandle) override {
    ++closes;
    return !fail_close;
  }
  uint32_t LastError() override { return 5; }
};

Submission Submit(FakeApi& api, bool* attempted = nullptr) {
  return SubmitRaw(api, kQueue, kBytes, L"JOB synthetic-1", attempted);
}

}  // namespace

int main() {
  {
    FakeApi api;
    bool attempted = false;
    const auto result = Submit(api, &attempted);
    Require(!result.error, "success has no error");
    Require(result.job_id == 42 && result.bytes_written == kBytes.size(),
            "exact acceptance receipt");
    Require(api.queue_name == kQueue.name,
            "queue name is exact and never a command");
    Require(api.datatype == L"RAW", "RAW datatype is explicit");
    Require(api.document_name == L"JOB synthetic-1", "document name preserved");
    Require(api.received == kBytes,
            "all bytes including NUL and high byte preserved");
    Require(attempted && api.writes == 1 && api.starts == 1,
            "one document and one write");
    Require(api.closes == 1 && api.aborts == 0,
            "success closes handle without abort");
  }
  for (const auto* stage : {"enumerate", "openPrinter", "inspectPrinter"}) {
    FakeApi api;
    api.fail = stage;
    bool attempted = true;
    const auto result = Submit(api, &attempted);
    Require(result.error && result.error->stage == stage,
            "pre-document failure stage retained");
    Require(!result.error->write_attempted && !attempted,
            "pre-document failure is known not attempted");
    Require(api.starts == 0 && api.writes == 0,
            "pre-document failure writes nothing");
    Require(api.closes == (std::string(stage) == "inspectPrinter" ? 1 : 0),
            "pre-document handle cleanup");
  }
  for (const auto* stage :
       {"startDocPrinter", "startPagePrinter", "writePrinter", "endPagePrinter",
        "endDocPrinter"}) {
    FakeApi api;
    api.fail = stage;
    bool attempted = false;
    const auto result = Submit(api, &attempted);
    Require(result.error && result.error->stage == stage,
            "post-document failure stage retained");
    Require(result.error->write_attempted && attempted,
            "attempt marked before StartDocPrinter");
    Require(api.starts == 1 && api.writes <= 1 && api.closes == 1,
            "failure never retries and closes handle");
    Require(api.aborts == (std::string(stage) == "startDocPrinter" ? 0 : 1),
            "started document aborted on failure");
  }
  {
    FakeApi api;
    api.short_write = true;
    const auto result = Submit(api);
    Require(result.error && result.error->stage == "writePrinter",
            "short write is failure");
    Require(result.error->write_attempted && api.writes == 1 && api.ends == 0,
            "short write remains uncertain with no retry");
    Require(api.aborts == 1 && api.closes == 1,
            "short write releases native resources");
  }
  {
    FakeApi api;
    api.fail_close = true;
    const auto result = Submit(api);
    Require(result.error && result.error->stage == "closePrinter",
            "close failure is visible");
    Require(result.error->write_attempted && api.closes == 1 && api.ends == 1,
            "close failure after acceptance remains uncertain");
  }
  {
    FakeApi api;
    api.fail = "writePrinter";
    api.fail_abort = true;
    api.fail_close = true;
    const auto result = Submit(api);
    Require(result.error && result.error->stage == "writePrinter",
            "cleanup preserves original failure");
    Require(result.error->message.find("AbortPrinter cleanup failed") !=
                std::string::npos,
            "abort cleanup failure surfaced");
    Require(result.error->message.find("ClosePrinter cleanup failed") !=
                std::string::npos,
            "close cleanup failure surfaced");
    Require(api.aborts == 1 && api.closes == 1,
            "cleanup does not replay failed submission");
  }
  {
    FakeApi api;
    api.throw_write = true;
    bool attempted = false;
    bool thrown = false;
    try {
      Submit(api, &attempted);
    } catch (const std::runtime_error&) {
      thrown = true;
    }
    Require(thrown && attempted,
            "unexpected write exception retains uncertainty marker");
    Require(api.aborts == 1 && api.closes == 1,
            "exception closes native handle");
  }
  {
    FakeApi api;
    api.fail = "openPrinter";
    api.return_handle_on_open_failure = true;
    const auto result = Submit(api);
    Require(result.error && !result.error->write_attempted,
            "failed open does not start document");
    Require(api.closes == 1, "even failed open with a handle is closed");
  }
  for (int change = 0; change < 4; ++change) {
    FakeApi api;
    if (change == 0) api.installed.name = L"different name";
    if (change == 1) api.installed.driver = L"different driver";
    if (change == 2) api.installed.port = L"different port";
    if (change == 3) api.duplicate = true;
    const auto result = Submit(api);
    Require(result.error && result.error->stage == "selectQueue",
            "installed queue identity drift rejected");
    Require(!result.error->write_attempted && api.opens == 0,
            "identity drift does not open a queue");
  }
  for (int change = 0; change < 3; ++change) {
    FakeApi api;
    if (change == 0) api.opened.name = L"retargeted name";
    if (change == 1) api.opened.driver = L"retargeted driver";
    if (change == 2) api.opened.port = L"retargeted port";
    const auto result = Submit(api);
    Require(result.error && result.error->stage == "selectQueue",
            "opened handle identity drift rejected");
    Require(
        !result.error->write_attempted && api.starts == 0 && api.closes == 1,
        "retargeted handle released before StartDoc");
  }
  {
    FakeApi api;
    const auto result = SubmitRaw(api, kQueue, kBytes, L"JOB synthetic-1",
                                  nullptr, [] { return false; });
    Require(result.error && result.error->stage == "dispatch",
            "expired admission held before opening queue");
    Require(!result.error->write_attempted && api.opens == 0 && api.starts == 0,
            "expired admission cannot start a late document");
  }
  {
    FakeApi api;
    int checks = 0;
    const auto result = SubmitRaw(api, kQueue, kBytes, L"JOB synthetic-1",
                                  nullptr, [&] { return ++checks == 1; });
    Require(result.error && result.error->stage == "dispatch",
            "shutdown rechecked after opening queue");
    Require(
        !result.error->write_attempted && api.starts == 0 && api.closes == 1,
        "shutdown does not start late document");
  }
  for (int invalid = 0; invalid < 7; ++invalid) {
    FakeApi api;
    auto queue = kQueue;
    auto bytes = kBytes;
    std::wstring document = L"JOB synthetic-1";
    if (invalid == 0) queue.name = L"";
    if (invalid == 1) queue.name = std::wstring(L"one\0two", 7);
    if (invalid == 2) queue.name = std::wstring(kMaxQueueNameLength + 1, L'q');
    if (invalid == 3) queue.driver = L"";
    if (invalid == 4) queue.port = L"invalid\nport";
    if (invalid == 5) bytes.clear();
    if (invalid == 6) bytes.resize(kMaxTransmissionBytes + 1);
    const auto result = SubmitRaw(api, queue, bytes, document);
    Require(result.error && result.error->stage == "validate",
            "invalid native input rejected");
    Require(!result.error->write_attempted && api.opens == 0 && api.starts == 0,
            "invalid input does not open or submit");
  }
  std::cout << "Windows spooler fake-only seam: " << assertions
            << " assertions passed\n";
  return 0;
}
