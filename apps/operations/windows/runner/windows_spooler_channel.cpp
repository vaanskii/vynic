#include "windows_spooler_channel.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <exception>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "windows_spooler.h"
#include "windows_spooler_native.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;
using vynic::printing::Error;
using vynic::printing::Inventory;
using vynic::printing::PrinterHandle;
using vynic::printing::Queue;
using vynic::printing::Submission;
using vynic::printing::WinspoolApi;


constexpr size_t kMaxPendingCalls = 4;
// Leave a margin before Dart's 30-second response timeout. A queued or slowly
// opening request cannot start a fresh document after its admission expires.
constexpr auto kAdmissionTimeout = std::chrono::seconds(25);

const EncodableValue* Argument(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::optional<std::wstring> ReadTextArgument(const EncodableMap& map,
                                             const char* key,
                                             size_t max_length) {
  const auto* value = Argument(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  if (!text || text->empty() || text->size() > max_length * 4)
    return std::nullopt;
  const auto size = static_cast<int>(text->size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        text->data(), size, nullptr, 0);
  if (count <= 0 || static_cast<size_t>(count) > max_length)
    return std::nullopt;
  std::wstring wide(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), size,
                          wide.data(), count) != count ||
      !vynic::printing::ValidText(wide, max_length))
    return std::nullopt;
  return wide;
}

std::optional<std::string> Utf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const auto size = static_cast<int>(text.size());
  const int count =
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), size,
                          nullptr, 0, nullptr, nullptr);
  if (count <= 0) return std::nullopt;
  std::string utf8(static_cast<size_t>(count), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), size,
                          utf8.data(), count, nullptr, nullptr) != count)
    return std::nullopt;
  return utf8;
}

void ReplyError(Result& result, const Error& error,
                const Submission& submission = {}) {
  result.Error(
      "vynic_spooler_error", error.message,
      EncodableValue(EncodableMap{
          {EncodableValue("stage"), EncodableValue(error.stage)},
          {EncodableValue("writeAttempted"),
           EncodableValue(error.write_attempted)},
          {EncodableValue("windowsError"),
           EncodableValue(static_cast<int64_t>(error.windows_error))},
          {EncodableValue("jobId"),
           EncodableValue(static_cast<int64_t>(submission.job_id))},
          {EncodableValue("bytesWritten"),
           EncodableValue(static_cast<int64_t>(submission.bytes_written))},
      }));
}

struct Work {
  uint64_t id = 0;
  bool inventory = true;
  Queue expected_queue;
  std::wstring document;
  std::vector<uint8_t> bytes;
  std::chrono::steady_clock::time_point admission_deadline;
};

struct Completed {
  uint64_t id = 0;
  bool inventory = true;
  Inventory queues;
  Submission submission;
};

}  // namespace

struct WindowsSpoolerChannel::WorkerState {
  std::atomic<bool> stopped{false};
  std::mutex mutex;
  std::condition_variable wake;
  HWND window = nullptr;
  std::deque<Work> jobs;
  std::deque<Completed> completed;
};

WindowsSpoolerChannel::WindowsSpoolerChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "vynic/windows_spooler",
          &flutter::StandardMethodCodec::GetInstance())),
      state_(std::make_shared<WorkerState>()) {
  state_->window = window;
  // Shared worker state owns no Flutter pointers. Shutdown never joins a
  // blocked Winspool call on the UI thread, and completion replies stay on that
  // thread.
  std::thread(&WindowsSpoolerChannel::RunWorker, state_).detach();
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
}

WindowsSpoolerChannel::~WindowsSpoolerChannel() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->stopped = true;
    state_->window = nullptr;
    state_->jobs.clear();
    state_->completed.clear();
  }
  state_->wake.notify_one();
  // Reply before Flutter's controller is destroyed. An active call might have
  // already submitted bytes; queue shutdown must never report it as not sent.
  for (auto& item : pending_)
    ReplyError(
        *item.second,
        Error{"shutdown", true, 0,
              "RAW adapter stopped; submission outcome requires review"});
  pending_.clear();
}

void WindowsSpoolerChannel::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<Result> result) {
  Work work;
  if (call.method_name() == "listQueues") {
    if (call.arguments() &&
        !std::holds_alternative<std::monostate>(*call.arguments())) {
      ReplyError(*result,
                 Error{"validate", false, 0, "Inventory takes no arguments"});
      return;
    }
  } else if (call.method_name() == "submitRaw") {
    work.inventory = false;
    const auto* args = call.arguments()
                           ? std::get_if<EncodableMap>(call.arguments())
                           : nullptr;
    if (!args || args->size() != 5) {
      ReplyError(*result, Error{"validate", false, 0,
                                "Invalid RAW submission arguments"});
      return;
    }
    const auto name = ReadTextArgument(*args, "queueName",
                                       vynic::printing::kMaxQueueNameLength);
    const auto driver = ReadTextArgument(*args, "expectedDriverName",
                                         vynic::printing::kMaxDescriptorLength);
    const auto port = ReadTextArgument(*args, "expectedPortName",
                                       vynic::printing::kMaxDescriptorLength);
    const auto document = ReadTextArgument(
        *args, "documentName", vynic::printing::kMaxDocumentNameLength);
    const auto* value = Argument(*args, "bytes");
    const auto* bytes =
        value ? std::get_if<std::vector<uint8_t>>(value) : nullptr;
    if (!name || !driver || !port || !document || !bytes || bytes->empty() ||
        bytes->size() > vynic::printing::kMaxTransmissionBytes) {
      ReplyError(*result, Error{"validate", false, 0,
                                "Invalid RAW queue identity or payload"});
      return;
    }
    work.expected_queue = {*name, *driver, *port};
    work.document = *document;
    work.bytes = *bytes;
  } else {
    result->NotImplemented();
    return;
  }
  if (pending_.size() >= kMaxPendingCalls) {
    ReplyError(*result, Error{"dispatch", false, 0,
                              "RAW adapter is busy; no submission attempted"});
    return;
  }
  work.id = next_id_++;
  work.admission_deadline =
      std::chrono::steady_clock::now() + kAdmissionTimeout;
  pending_.emplace(work.id, std::move(result));
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->jobs.push_back(std::move(work));
  }
  state_->wake.notify_one();
}

void WindowsSpoolerChannel::RunWorker(std::shared_ptr<WorkerState> state) {
  WinspoolApi api;
  for (;;) {
    Work work;
    {
      std::unique_lock<std::mutex> lock(state->mutex);
      state->wake.wait(lock,
                       [&] { return state->stopped || !state->jobs.empty(); });
      if (state->stopped) return;
      work = std::move(state->jobs.front());
      state->jobs.pop_front();
    }
    Completed done;
    done.id = work.id;
    done.inventory = work.inventory;
    bool submission_attempted = false;
    const auto may_start = [&] {
      return !state->stopped.load() &&
             std::chrono::steady_clock::now() < work.admission_deadline;
    };
    try {
      if (!may_start()) {
        const Error failure{"dispatch", false, 0,
                            "Native request expired before submission"};
        if (work.inventory)
          done.queues.error = failure;
        else
          done.submission.error = failure;
      } else if (work.inventory) {
        done.queues = api.ListQueues();
      } else {
        done.submission = vynic::printing::SubmitRaw(
            api, work.expected_queue, work.bytes, work.document,
            &submission_attempted, may_start);
      }
    } catch (const std::exception& error) {
      const Error failure{"nativeException", submission_attempted, 0,
                          error.what()};
      if (work.inventory)
        done.queues.error = failure;
      else
        done.submission.error = failure;
    } catch (...) {
      const Error failure{"nativeException", submission_attempted, 0,
                          "Unexpected native RAW adapter failure"};
      if (work.inventory)
        done.queues.error = failure;
      else
        done.submission.error = failure;
    }
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->stopped) return;
      state->completed.push_back(std::move(done));
      if (!PostMessageW(state->window, kCompletionMessage, 0, 0))
        OutputDebugStringW(
            L"Vynic RAW adapter: completion dispatch failed; Dart timeout "
            L"requires review\n");
    }
  }
}

bool WindowsSpoolerChannel::HandleMessage(UINT message) {
  if (message != kCompletionMessage) return false;
  std::deque<Completed> completed;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    completed.swap(state_->completed);
  }
  for (auto& done : completed) {
    const auto found = pending_.find(done.id);
    if (found == pending_.end()) continue;
    auto result = std::move(found->second);
    pending_.erase(found);
    if (done.inventory) {
      if (done.queues.error) {
        ReplyError(*result, *done.queues.error);
        continue;
      }
      EncodableList queues;
      bool valid = true;
      for (const auto& queue : done.queues.queues) {
        auto name = Utf8(queue.name), driver = Utf8(queue.driver),
             port = Utf8(queue.port);
        if (!name || !driver || !port) {
          valid = false;
          break;
        }
        queues.emplace_back(EncodableMap{
            {EncodableValue("name"), EncodableValue(*name)},
            {EncodableValue("driver"), EncodableValue(*driver)},
            {EncodableValue("port"), EncodableValue(*port)},
        });
      }
      if (valid)
        result->Success(EncodableValue(queues));
      else
        ReplyError(*result, Error{"enumerate", false, ERROR_INVALID_DATA,
                                  "Invalid queue text encoding"});
    } else if (done.submission.error) {
      ReplyError(*result, *done.submission.error, done.submission);
    } else {
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("accepted"), EncodableValue(true)},
          {EncodableValue("jobId"),
           EncodableValue(static_cast<int64_t>(done.submission.job_id))},
          {EncodableValue("bytesWritten"),
           EncodableValue(static_cast<int64_t>(done.submission.bytes_written))},
      }));
    }
  }
  return true;
}
