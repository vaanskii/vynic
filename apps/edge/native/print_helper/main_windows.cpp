#include "session.h"
#include "windows_spooler_native.h"

#include <windows.h>

#include <algorithm>
#include <stdexcept>
#include <string>

namespace {
namespace helper = vynic::print_helper;

class PipeIO final : public helper::FrameIO {
public:
  bool Read(std::vector<uint8_t> *frame) override {
    uint8_t prefix[4]{};
    if (!Exact(GetStdHandle(STD_INPUT_HANDLE), prefix, sizeof(prefix), false))
      return false;
    uint32_t size = 0;
    for (int n = 0; n < 4; ++n)
      size |= static_cast<uint32_t>(prefix[n]) << (n * 8);
    if (size < 8 || size > helper::kMaxFrameBytes)
      return false;
    frame->resize(size);
    return Exact(GetStdHandle(STD_INPUT_HANDLE), frame->data(), size, false);
  }
  bool Write(const std::vector<uint8_t> &frame) override {
    if (frame.size() < 8 || frame.size() > helper::kMaxFrameBytes)
      return false;
    const auto size = static_cast<uint32_t>(frame.size());
    uint8_t prefix[4]{};
    for (int n = 0; n < 4; ++n)
      prefix[n] = static_cast<uint8_t>(size >> (n * 8));
    return Exact(GetStdHandle(STD_OUTPUT_HANDLE), prefix, sizeof(prefix),
                 true) &&
           Exact(GetStdHandle(STD_OUTPUT_HANDLE),
                 const_cast<uint8_t *>(frame.data()), size, true);
  }

private:
  static bool Exact(HANDLE handle, uint8_t *data, size_t size, bool write) {
    size_t offset = 0;
    while (offset < size) {
      DWORD transferred = 0;
      const auto count =
          static_cast<DWORD>(std::min<size_t>(size - offset, 65536));
      const BOOL ok =
          write ? WriteFile(handle, data + offset, count, &transferred, nullptr)
                : ReadFile(handle, data + offset, count, &transferred, nullptr);
      if (!ok || transferred == 0 || transferred > count)
        return false;
      offset += transferred;
    }
    return true;
  }
};

std::wstring Wide(const std::string &text) {
  const auto size = static_cast<int>(text.size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        text.data(), size, nullptr, 0);
  if (count <= 0)
    throw std::runtime_error("Invalid UTF-8");
  std::wstring out(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), size,
                          out.data(), count) != count)
    throw std::runtime_error("Invalid UTF-8");
  return out;
}

std::string Utf8(const std::wstring &text) {
  if (text.empty())
    return {};
  const auto size = static_cast<int>(text.size());
  const int count =
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), size,
                          nullptr, 0, nullptr, nullptr);
  if (count <= 0)
    throw std::runtime_error("Invalid UTF-16");
  std::string out(static_cast<size_t>(count), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), size,
                          out.data(), count, nullptr, nullptr) != count)
    throw std::runtime_error("Invalid UTF-16");
  return out;
}

class SemaphoreKeeper final : public helper::GuardKeeper {
public:
  ~SemaphoreKeeper() {
    if (handle_)
      CloseHandle(handle_);
  }
  bool Retain(const std::string &name) override {
    if (handle_)
      return false;
    handle_ = OpenSemaphoreW(SYNCHRONIZE | SEMAPHORE_MODIFY_STATE, FALSE,
                             Wide(name).c_str());
    if (!handle_)
      return false;
    const DWORD state = WaitForSingleObject(handle_, 0);
    if (state == WAIT_TIMEOUT)
      return true;
    // Parent alone owns/relinquishes count. Undo an accidental acquisition and
    // fail closed if it was not held; never allow this path to reach SubmitRaw.
    if (state == WAIT_OBJECT_0)
      ReleaseSemaphore(handle_, 1, nullptr);
    CloseHandle(handle_);
    handle_ = nullptr;
    return false;
  }

private:
  HANDLE handle_ = nullptr;
};

} // namespace

int main(int argc, char **) {
  if (argc != 1)
    return 2; // There are no print-capable command-line arguments.
  PipeIO io;
  SemaphoreKeeper guard;
  vynic::printing::WinspoolApi api;
  return helper::RunSession(io, api, guard, Wide, Utf8) ? 0 : 1;
}
