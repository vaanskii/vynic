#ifndef RUNNER_WINDOWS_SPOOLER_CHANNEL_H_
#define RUNNER_WINDOWS_SPOOLER_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>

class WindowsSpoolerChannel {
 public:
  static constexpr UINT kCompletionMessage = WM_APP + 18;

  WindowsSpoolerChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowsSpoolerChannel();
  WindowsSpoolerChannel(const WindowsSpoolerChannel&) = delete;
  WindowsSpoolerChannel& operator=(const WindowsSpoolerChannel&) = delete;

  // Invoked by FlutterWindow on its platform thread, never by the worker.
  bool HandleMessage(UINT message);

 private:
  struct WorkerState;
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  static void RunWorker(std::shared_ptr<WorkerState> state);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<WorkerState> state_;
  std::map<uint64_t,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      pending_;
  uint64_t next_id_ = 1;
};

#endif  // RUNNER_WINDOWS_SPOOLER_CHANNEL_H_
