#ifndef VYNIC_PRINT_HELPER_SESSION_H_
#define VYNIC_PRINT_HELPER_SESSION_H_

#include "protocol.h"
#include "windows_spooler.h"

#include <string>

namespace vynic::print_helper {

class FrameIO {
public:
  virtual ~FrameIO() = default;
  virtual bool Read(std::vector<uint8_t> *frame) = 0;
  virtual bool Write(const std::vector<uint8_t> &frame) = 0;
};

class GuardKeeper {
public:
  virtual ~GuardKeeper() = default;
  // Retain the already-acquired parent semaphore; never release its count.
  virtual bool Retain(const std::string &name) = 0;
};

using ToWide = std::wstring (*)(const std::string &);
using ToUtf8 = std::string (*)(const std::wstring &);

// One complete validated request, then READY and a complete COMMIT, are
// required before SubmitRaw. The reusable core still performs all identity
// checks and owns every printer handle/cleanup path.
bool RunSession(FrameIO &io, printing::SpoolerApi &api, GuardKeeper &guard,
                ToWide wide, ToUtf8 utf8);

} // namespace vynic::print_helper

#endif
