#include "../runner/windows_spooler_channel.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <functional>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "../runner/windows_spooler.h"

// A native test process, with no Flutter engine or product initialization. The
// only admitted Winspool operation is EnumPrintersW. Every submitRaw fixture
// contains an EMPTY payload (or no payload), so both channel and core
// validation prohibit OpenPrinter/StartDocPrinter even if a synthetic name
// matches a queue.
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Clock = std::chrono::steady_clock;

constexpr char kChannel[] = "vynic/windows_spooler";
constexpr wchar_t kWindowClass[] = L"VynicReadOnlySpoolerChannelTest";
int assertions = 0;

void Require(bool condition, const char *message) {
  ++assertions;
  if (!condition)
    throw std::runtime_error(message);
}

enum class ReplyKind { none, success, error, not_implemented };

struct Reply {
  int id = 0;
  int count = 0;
  ReplyKind kind = ReplyKind::none;
  EncodableValue value;
  EncodableValue details;
  std::string code;
};

struct Context {
  DWORD ui_thread = GetCurrentThreadId();
  Clock::time_point deadline = Clock::now() + std::chrono::seconds(26);
  std::atomic<bool> wrong_thread{false};
  WindowsSpoolerChannel *channel = nullptr;
  int messages = 0;
  std::string failure;
  std::vector<int> replies;
};

class FakeMessenger final : public flutter::BinaryMessenger {
public:
  explicit FakeMessenger(Context &context) : context_(context) {}

  void Send(const std::string &, const uint8_t *, size_t,
            flutter::BinaryReply = nullptr) const override {
    throw std::runtime_error("Unexpected outgoing engine message");
  }

  void SetMessageHandler(const std::string &name,
                         flutter::BinaryMessageHandler handler) override {
    Require(GetCurrentThreadId() == context_.ui_thread,
            "Handler registration stays on the UI thread");
    Require(name == kChannel, "Only the spooler channel is registered");
    if (handler)
      ++registrations;
    else
      ++unregistrations;
    handler_ = std::move(handler);
  }

  bool registered() const { return static_cast<bool>(handler_); }

  std::shared_ptr<Reply> Call(const std::string &method,
                              EncodableValue arguments = {}) {
    Require(registered(), "A channel handler must be registered");
    auto reply = std::make_shared<Reply>();
    reply->id = ++next_id_;
    const auto &codec = flutter::StandardMethodCodec::GetInstance();
    auto encoded = codec.EncodeMethodCall(flutter::MethodCall<EncodableValue>(
        method, std::make_unique<EncodableValue>(std::move(arguments))));
    Require(encoded != nullptr, "Method call encodes with the real codec");
    handler_(encoded->data(), encoded->size(),
             [this, reply](const uint8_t *data, size_t size) {
               if (GetCurrentThreadId() != context_.ui_thread) {
                 context_.wrong_thread = true;
                 return;
               }
               ++reply->count;
               context_.replies.push_back(reply->id);
               if (size == 0) {
                 reply->kind = ReplyKind::not_implemented;
                 return;
               }
               if (!data) {
                 context_.failure = "Nonempty reply has a null buffer";
                 return;
               }
               flutter::MethodResultFunctions<EncodableValue> result(
                   [reply](const EncodableValue *value) {
                     reply->kind = ReplyKind::success;
                     if (value)
                       reply->value = *value;
                   },
                   [reply](const std::string &code, const std::string &,
                           const EncodableValue *details) {
                     reply->kind = ReplyKind::error;
                     reply->code = code;
                     if (details)
                       reply->details = *details;
                   },
                   [reply] { reply->kind = ReplyKind::not_implemented; });
               if (!flutter::StandardMethodCodec::GetInstance()
                        .DecodeAndProcessResponseEnvelope(data, size, &result))
                 context_.failure = "Native response envelope failed decoding";
             });
    return reply;
  }

  int registrations = 0;
  int unregistrations = 0;

private:
  Context &context_;
  flutter::BinaryMessageHandler handler_;
  int next_id_ = 0;
};

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  auto *context =
      reinterpret_cast<Context *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam);
    context = static_cast<Context *>(create->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(context));
  }
  if (context && context->channel &&
      message == WindowsSpoolerChannel::kCompletionMessage) {
    ++context->messages;
    try {
      context->channel->HandleMessage(message);
    } catch (const std::exception &error) {
      context->failure = error.what();
    } catch (...) {
      context->failure = "Unexpected message-handler exception";
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

class Harness {
public:
  Harness() : messenger(context) {
    WNDCLASSW info{};
    info.lpfnWndProc = WindowProcedure;
    info.hInstance = GetModuleHandleW(nullptr);
    info.lpszClassName = kWindowClass;
    Require(RegisterClassW(&info) != 0, "Hidden window class registers");
    window_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                              nullptr, info.hInstance, &context);
    if (!window_) {
      UnregisterClassW(kWindowClass, info.hInstance);
      throw std::runtime_error("Message-only window creation failed");
    }
  }

  ~Harness() {
    CloseChannel();
    DestroyWindow(window_);
    UnregisterClassW(kWindowClass, GetModuleHandleW(nullptr));
  }

  void OpenChannel() {
    Require(!channel_, "Previous channel is closed before recreation");
    channel_ = std::make_unique<WindowsSpoolerChannel>(&messenger, window_);
    context.channel = channel_.get();
  }

  void CloseChannel() {
    context.channel = nullptr;
    channel_.reset();
  }

  bool HasQueuedCompletion() {
    MSG message{};
    const bool present = PeekMessageW(&message, window_,
                                      WindowsSpoolerChannel::kCompletionMessage,
                                      WindowsSpoolerChannel::kCompletionMessage,
                                      PM_NOREMOVE) != FALSE;
    Require(!present ||
                (message.hwnd == window_ &&
                 message.message == WindowsSpoolerChannel::kCompletionMessage),
            "Filtered peek finds only this window's completion message");
    return present;
  }

  void WaitForQueuedCompletion() {
    while (!HasQueuedCompletion()) {
      Require(!context.wrong_thread, "Replies stay on the UI thread");
      Require(context.failure.empty(), context.failure.c_str());
      Require(Clock::now() < context.deadline,
              "Queued completion arrives within the harness deadline");
      Require(MsgWaitForMultipleObjects(0, nullptr, FALSE, 25,
                                        QS_POSTMESSAGE) != WAIT_FAILED,
              "Bounded posted-message wait succeeds");
    }
    Require(Clock::now() < context.deadline,
            "Queued completion arrives within the harness deadline");
  }

  void PumpUntil(const std::function<bool()> &complete) {
    while (!complete()) {
      Require(!context.wrong_thread, "Replies stay on the UI thread");
      Require(context.failure.empty(), context.failure.c_str());
      Require(Clock::now() < context.deadline,
              "Entire harness completes within its 26-second deadline");
      MSG message{};
      for (int n = 0;
           n < 128 && PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE); ++n) {
        Require(message.message != WM_QUIT, "No unexpected quit message");
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
      if (!complete())
        Require(MsgWaitForMultipleObjects(0, nullptr, FALSE, 25, QS_ALLINPUT) !=
                    WAIT_FAILED,
                "Bounded message wait succeeds");
    }
    Require(!context.wrong_thread, "No worker-thread reply was observed");
    Require(context.failure.empty(), context.failure.c_str());
  }

  Context context;
  FakeMessenger messenger;

private:
  HWND window_ = nullptr;
  std::unique_ptr<WindowsSpoolerChannel> channel_;
};

const EncodableValue *Field(const EncodableMap &map, const char *key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

void RequireError(const Reply &reply, const char *stage, bool attempted) {
  Require(reply.count == 1 && reply.kind == ReplyKind::error,
          "Exactly one typed error envelope is returned");
  Require(reply.code == "vynic_spooler_error",
          "Native error code is preserved");
  const auto *details = std::get_if<EncodableMap>(&reply.details);
  Require(details != nullptr, "Native error details are a map");
  const auto *actual_stage = Field(*details, "stage");
  const auto *write = Field(*details, "writeAttempted");
  Require(actual_stage && std::get_if<std::string>(actual_stage) &&
              std::get<std::string>(*actual_stage) == stage,
          "Native error stage is preserved");
  Require(write && std::get_if<bool>(write) &&
              std::get<bool>(*write) == attempted,
          "Native write-attempt marker is preserved");
}

size_t RequireInventory(const Reply &reply) {
  Require(reply.count == 1 && reply.kind == ReplyKind::success,
          "Read-only real queue enumeration returns exactly one success");
  const auto *queues = std::get_if<EncodableList>(&reply.value);
  Require(queues && queues->size() <= vynic::printing::kMaxQueues,
          "Queue list respects the native inventory bound");
  for (const auto &queue : *queues) {
    const auto *row = std::get_if<EncodableMap>(&queue);
    Require(row && row->size() == 3, "Queue descriptor has three exact fields");
    const std::pair<const char *, size_t> fields[]{
        {"name", vynic::printing::kMaxQueueNameLength},
        {"driver", vynic::printing::kMaxDescriptorLength},
        {"port", vynic::printing::kMaxDescriptorLength}};
    for (const auto &[key, max_units] : fields) {
      const auto *field = Field(*row, key);
      const auto *text = field ? std::get_if<std::string>(field) : nullptr;
      Require(text != nullptr,
              "Queue descriptor fields decode as UTF-8 strings");
      Require(text->size() <= max_units * 4,
              "Queue descriptor respects its UTF-8 byte bound");
      const int units =
          text->empty()
              ? 0
              : MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
                                    static_cast<int>(text->size()), nullptr, 0);
      Require((text->empty() || units > 0) &&
                  static_cast<size_t>(units) <= max_units,
              "Queue descriptor is valid UTF-8 within its UTF-16 unit bound");
    }
    Require(!std::get<std::string>(*Field(*row, "name")).empty(),
            "Queue name is not empty");
  }
  return queues->size();
}

void Run() {
  Harness harness;
  harness.OpenChannel();
  auto &messenger = harness.messenger;
  Require(messenger.registered(), "Constructor registers the real channel");
  Require(!harness.context.channel->HandleMessage(WM_USER + 99),
          "Unrelated messages remain available to the window");
  auto unknown = messenger.Call("notAWinspoolMethod");
  Require(unknown->count == 1 && unknown->kind == ReplyKind::not_implemented,
          "Unknown methods return one not-implemented response");
  RequireError(*messenger.Call("listQueues", EncodableValue(EncodableMap{})),
               "validate", false);

  // No nonempty print byte vector is constructed anywhere in this harness.
  EncodableMap empty_payload{
      {EncodableValue("queueName"), EncodableValue("Synthetic test queue")},
      {EncodableValue("expectedDriverName"),
       EncodableValue("Synthetic driver")},
      {EncodableValue("expectedPortName"), EncodableValue("Synthetic port")},
      {EncodableValue("documentName"), EncodableValue("Nonphysical test")},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{})},
  };
  RequireError(*messenger.Call("submitRaw"), "validate", false);
  RequireError(*messenger.Call("submitRaw", EncodableValue(empty_payload)),
               "validate", false);
  empty_payload.emplace(EncodableValue("extra"), EncodableValue(true));
  RequireError(*messenger.Call("submitRaw", EncodableValue(empty_payload)),
               "validate", false);

  harness.context.replies.clear();
  std::vector<std::shared_ptr<Reply>> inventory;
  for (int n = 0; n < 4; ++n)
    inventory.push_back(messenger.Call("listQueues"));
  for (const auto &reply : inventory)
    Require(reply->count == 0, "Inventory never replies before pumping the UI");
  auto overflow = messenger.Call("listQueues");
  RequireError(*overflow, "dispatch", false);
  harness.context.replies.clear();
  harness.PumpUntil([&] {
    for (const auto &reply : inventory)
      if (reply->count == 0)
        return false;
    return true;
  });
  Require(harness.context.messages > 0,
          "Real posted window messages delivered");
  size_t first_queue_count = 0;
  for (size_t n = 0; n < inventory.size(); ++n) {
    const auto &reply = *inventory[n];
    const auto queue_count = RequireInventory(reply);
    if (n == 0)
      first_queue_count = queue_count;
    Require(harness.context.replies[n] == reply.id,
            "Single-worker inventory replies preserve FIFO order");
  }

  // Prove a new completion is queued but has not delivered its reply before
  // destruction. Each live inventory is valid independently; queue snapshots
  // may legitimately change between EnumPrinters calls.
  Require(!harness.HasQueuedCompletion(),
          "Earlier inventory completion messages have been drained");
  auto shutdown_a = messenger.Call("listQueues");
  auto shutdown_b = messenger.Call("listQueues");
  const auto delivered_messages = harness.context.messages;
  harness.WaitForQueuedCompletion();
  Require(shutdown_a->count == 0 && shutdown_b->count == 0 &&
              harness.context.messages == delivered_messages,
          "Queued old completion has not been dispatched or replied");
  const auto closing = Clock::now();
  harness.CloseChannel();
  Require(Clock::now() - closing < std::chrono::seconds(1),
          "Channel destruction does not join a Winspool worker");
  Require(!messenger.registered(),
          "Destructor unregisters the channel handler");
  RequireError(*shutdown_a, "shutdown", true);
  RequireError(*shutdown_b, "shutdown", true);
  Require(!harness.context.wrong_thread,
          "Shutdown replies stay on the UI thread");
  Require(harness.HasQueuedCompletion(),
          "Undispatched old completion survives channel destruction");

  // A fresh adapter on the same HWND first ignores the retained old completion
  // before any new work is admitted, then handles a new read-only inventory.
  harness.OpenChannel();
  harness.PumpUntil(
      [&] { return harness.context.messages > delivered_messages; });
  Require(shutdown_a->count == 1 && shutdown_b->count == 1,
          "Dispatching an old notification cannot repeat a shutdown reply");
  auto recreated = messenger.Call("listQueues");
  harness.PumpUntil([&] { return recreated->count != 0; });
  RequireInventory(*recreated);
  Require(shutdown_a->count == 1 && shutdown_b->count == 1,
          "Old completed work cannot reply twice after destruction");
  harness.CloseChannel();
  Require(messenger.registrations == 2 && messenger.unregistrations == 2,
          "Each channel lifetime registers and unregisters exactly once");
  std::cout << "Windows spooler read-only channel harness: " << assertions
            << " assertions passed; " << first_queue_count
            << " queues enumerated; no documents submitted\n";
}

} // namespace

int main() {
  try {
    Run();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "Read-only channel harness failed: " << error.what() << "\n";
    return 1;
  }
}
