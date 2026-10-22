#include "session.h"

#include <iostream>
#include <stdexcept>
#include <utility>

namespace {
namespace helper = vynic::print_helper;
namespace printing = vynic::printing;
int assertions = 0;

void Require(bool value, const char *message) {
  ++assertions;
  if (!value)
    throw std::runtime_error(message);
}
void U32(std::vector<uint8_t> &out, uint32_t value) {
  for (int n = 0; n < 4; ++n)
    out.push_back(static_cast<uint8_t>(value >> (n * 8)));
}
void Text(std::vector<uint8_t> &out, const std::string &text) {
  U32(out, static_cast<uint32_t>(text.size()));
  out.insert(out.end(), text.begin(), text.end());
}
std::vector<uint8_t> Submit(std::vector<uint8_t> bytes = {27, 64, 10},
                            std::string name = "Printer") {
  auto frame = helper::Header(helper::Tag::submit);
  for (const auto &text :
       {name, std::string("Driver"), std::string("Port"),
        std::string("Test document"),
        std::string(helper::kGuardPrefix) + std::string(64, 'a')})
    Text(frame, text);
  U32(frame, static_cast<uint32_t>(bytes.size()));
  frame.insert(frame.end(), bytes.begin(), bytes.end());
  return frame;
}

class MemoryIO final : public helper::FrameIO {
public:
  std::vector<std::vector<uint8_t>> incoming;
  std::vector<std::vector<uint8_t>> outgoing;
  size_t position = 0;
  size_t fail_write = 0;
  bool Read(std::vector<uint8_t> *frame) override {
    if (position == incoming.size())
      return false;
    *frame = incoming[position++];
    return true;
  }
  bool Write(const std::vector<uint8_t> &frame) override {
    outgoing.push_back(frame);
    return outgoing.size() != fail_write;
  }
};
class Guard final : public helper::GuardKeeper {
public:
  int retained = 0;
  bool available = true;
  bool Retain(const std::string &) override {
    ++retained;
    return available;
  }
};
class FakeApi final : public printing::SpoolerApi {
public:
  int lists = 0, opens = 0, inspections = 0, starts = 0, writes = 0;
  int closes = 0, aborts = 0;
  bool open_ok = true, start_ok = true, write_ok = true, changed = false;
  bool throw_start = false;
  std::vector<uint8_t> received;
  printing::Inventory ListQueues() override {
    ++lists;
    return {{{L"Printer", L"Driver", L"Port"}}, std::nullopt};
  }
  bool Open(const std::wstring &name,
            printing::PrinterHandle *handle) override {
    ++opens;
    Require(name == L"Printer", "Frozen queue name is retained");
    *handle = open_ok ? 1 : 0;
    return open_ok;
  }
  printing::Inventory Inspect(printing::PrinterHandle) override {
    ++inspections;
    return {{{L"Printer", changed ? L"Changed driver" : L"Driver", L"Port"}},
            std::nullopt};
  }
  uint32_t StartDocument(printing::PrinterHandle, const std::wstring &document,
                         const std::wstring &datatype) override {
    ++starts;
    Require(document == L"Test document" && datatype == L"RAW",
            "Frozen name and RAW datatype are retained");
    if (throw_start)
      throw std::runtime_error("synthetic StartDoc failure");
    return start_ok ? 77 : 0;
  }
  bool StartPage(printing::PrinterHandle) override { return true; }
  bool Write(printing::PrinterHandle, const std::vector<uint8_t> &bytes,
             uint32_t *written) override {
    ++writes;
    received = bytes;
    *written = write_ok ? static_cast<uint32_t>(bytes.size()) : 1;
    return write_ok;
  }
  bool EndPage(printing::PrinterHandle) override { return true; }
  bool EndDocument(printing::PrinterHandle) override { return true; }
  bool Abort(printing::PrinterHandle) override {
    ++aborts;
    return true;
  }
  bool Close(printing::PrinterHandle) override {
    ++closes;
    return true;
  }
  uint32_t LastError() override { return 5; }
};

std::wstring Wide(const std::string &text) {
  return {text.begin(), text.end()};
}
std::string Utf8(const std::wstring &text) {
  return {text.begin(), text.end()};
}
bool Run(MemoryIO &io, FakeApi &api, Guard &guard) {
  return helper::RunSession(io, api, guard, Wide, Utf8);
}
void Outcome(const MemoryIO &io, uint8_t state, bool attempted) {
  Require(!io.outgoing.empty(), "A typed response exists");
  const auto &frame = io.outgoing.back();
  Require(frame.size() >= 24 &&
              frame[6] == static_cast<uint8_t>(helper::Tag::result),
          "Response is a result envelope");
  Require(frame[8] == state && frame[9] == static_cast<uint8_t>(attempted),
          "Result has exact state and attempt evidence");
}
void NoNativeWrite(const FakeApi &api) {
  Require(api.opens == 0 && api.starts == 0 && api.writes == 0,
          "Admission failure never reaches Open/StartDoc/Write");
}

void Tests() {
  const auto valid = Submit();
  helper::Request parsed;
  Require(helper::DecodeRequest(valid, &parsed) &&
              parsed.payload == std::vector<uint8_t>({27, 64, 10}),
          "Exact bounded request decodes");
  for (size_t n = 0; n < valid.size(); ++n) {
    auto partial = std::vector<uint8_t>(valid.begin(), valid.begin() + n);
    Require(!helper::DecodeRequest(partial, &parsed),
            "Every partial request is rejected");
  }
  auto extra = valid;
  extra.push_back(0);
  Require(!helper::DecodeRequest(extra, &parsed),
          "Extra submission fields are rejected");
  auto version = valid;
  version[4] = 2;
  Require(!helper::DecodeRequest(version, &parsed),
          "Different protocol version is rejected");
  auto flags = valid;
  flags[7] = 1;
  Require(!helper::DecodeRequest(flags, &parsed),
          "Reserved fields must be zero");
  for (const auto &name : {std::string("\xc0\xaf"), std::string("\xed\xa0\x80"),
                           std::string("\xf4\x90\x80\x80"),
                           std::string("bad\nname"), std::string(256, 'a')})
    Require(!helper::DecodeRequest(Submit({1}, name), &parsed),
            "Invalid UTF-8/control/overlong identifiers are rejected");
  Require(!helper::DecodeRequest(Submit({}), &parsed),
          "Empty payload is rejected");
  Require(!helper::DecodeRequest(
              Submit(std::vector<uint8_t>(helper::kMaxPayloadBytes + 1, 0)),
              &parsed),
          "Oversized payload is rejected");
  std::string supplementary;
  for (int n = 0; n < 127; ++n)
    supplementary += "\xf0\x9f\x98\x80";
  Require(helper::DecodeRequest(Submit({1}, supplementary), &parsed),
          "Supplementary Unicode is counted in UTF-16 units");
  supplementary += "\xf0\x9f\x98\x80";
  Require(!helper::DecodeRequest(Submit({1}, supplementary), &parsed),
          "UTF-16 unit bound rejects 256 units");

  for (const auto &request : {std::vector<uint8_t>{}, Submit({}), extra}) {
    MemoryIO io;
    io.incoming = {request};
    FakeApi api;
    Guard guard;
    Require(Run(io, api, guard), "Validation error response writes");
    Outcome(io, 0, false);
    NoNativeWrite(api);
    Require(api.lists == 0 && guard.retained == 0,
            "Malformed requests have no native/guard side effects");
  }
  {
    MemoryIO io;
    io.incoming = {helper::Header(helper::Tag::inventory)};
    FakeApi api;
    Guard guard;
    Require(Run(io, api, guard), "Read-only inventory responds");
    Require(api.lists == 1 &&
                io.outgoing[0][6] ==
                    static_cast<uint8_t>(helper::Tag::inventory_result),
            "Inventory uses descriptor envelope");
    NoNativeWrite(api);
    Require(guard.retained == 0,
            "Inventory does not acquire a physical job guard");
  }
  for (auto commit :
       {std::vector<uint8_t>{}, helper::Header(helper::Tag::ready), extra}) {
    MemoryIO io;
    io.incoming = {valid, commit};
    FakeApi api;
    Guard guard;
    Require(Run(io, api, guard), "Invalid COMMIT gets typed response");
    Outcome(io, 0, false);
    NoNativeWrite(api);
    Require(guard.retained == 1 &&
                io.outgoing[0] == helper::Header(helper::Tag::ready),
            "Guard retention precedes READY");
  }
  {
    MemoryIO io;
    io.incoming = {valid};
    FakeApi api;
    Guard guard;
    Require(Run(io, api, guard), "EOF after READY responds without writing");
    Outcome(io, 0, false);
    NoNativeWrite(api);
  }
  {
    MemoryIO io;
    io.incoming = {valid};
    FakeApi api;
    Guard guard;
    guard.available = false;
    Require(Run(io, api, guard), "Unavailable parent guard fails closed");
    Outcome(io, 0, false);
    NoNativeWrite(api);
  }
  {
    MemoryIO io;
    io.incoming = {valid, helper::Header(helper::Tag::commit)};
    io.fail_write = 1;
    FakeApi api;
    Guard guard;
    Require(!Run(io, api, guard), "Lost READY never starts a document");
    NoNativeWrite(api);
  }
  {
    MemoryIO io;
    io.incoming = {valid, helper::Header(helper::Tag::commit)};
    FakeApi api;
    Guard guard;
    Require(Run(io, api, guard), "Committed fake submission responds");
    Outcome(io, 1, true);
    Require(api.starts == 1 && api.writes == 1 && api.closes == 1 &&
                api.aborts == 0,
            "Exactly one fake submission with cleanup");
    Require(api.received == std::vector<uint8_t>({27, 64, 10}),
            "Bytes remain exact");
  }
  {
    MemoryIO io;
    io.incoming = {valid, helper::Header(helper::Tag::commit)};
    FakeApi api;
    Guard guard;
    api.changed = true;
    Require(Run(io, api, guard), "Opened queue identity change responds");
    Outcome(io, 0, false);
    Require(api.opens == 1 && api.closes == 1 && api.starts == 0,
            "Changed opened driver is closed before StartDoc");
  }
  for (int failure = 0; failure < 3; ++failure) {
    MemoryIO io;
    io.incoming = {valid, helper::Header(helper::Tag::commit)};
    FakeApi api;
    Guard guard;
    api.start_ok = failure != 0;
    api.write_ok = failure != 1;
    api.throw_start = failure == 2;
    Require(Run(io, api, guard), "Synthetic post-attempt error responds");
    Outcome(io, 2, true);
    Require(api.starts == 1 && api.closes == 1,
            "Ambiguous attempt is not retried and closes its handle");
    Require(api.writes == (failure == 1 ? 1 : 0),
            "StartDoc ambiguity never retries a Write");
  }
  {
    MemoryIO io;
    io.incoming = {valid, helper::Header(helper::Tag::commit)};
    io.fail_write = 2;
    FakeApi api;
    Guard guard;
    Require(!Run(io, api, guard),
            "Lost final ACK is not success to the parent");
    Require(api.starts == 1 && api.writes == 1 && api.closes == 1,
            "Lost ACK never replays fake physical bytes");
  }
}
} // namespace

int main() {
  try {
    Tests();
    std::cout << "Print helper fake protocol: " << assertions
              << " assertions passed; no Winspool linked\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
