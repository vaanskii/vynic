#ifndef VYNIC_PRINT_HELPER_PROTOCOL_H_
#define VYNIC_PRINT_HELPER_PROTOCOL_H_

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace vynic::print_helper {

constexpr uint16_t kProtocolVersion = 1;
constexpr uint32_t kMagic = 0x31505456; // VTP1, little endian.
constexpr size_t kMaxFrameBytes = 16 * 1024 * 1024;
constexpr size_t kMaxPayloadBytes = 8 * 1024 * 1024 + 1024;
constexpr char kGuardPrefix[] = "Global\\VynicPrint-";

enum class Tag : uint8_t {
  inventory = 1,
  submit = 2,
  commit = 3,
  ready = 64,
  result = 65,
  inventory_result = 66,
};

struct Request {
  Tag tag = Tag::inventory;
  std::string queue;
  std::string driver;
  std::string port;
  std::string document;
  std::string guard;
  std::vector<uint8_t> payload;
};

struct WireResult {
  uint8_t state = 0; // 0 notSent; 1 submitted; 2 uncertain.
  bool attempted = false;
  uint32_t bytes_written = 0;
  uint32_t job_id = 0;
  uint32_t windows_error = 0;
  std::string stage;
  std::string detail;
};

struct Descriptor {
  std::string name;
  std::string driver;
  std::string port;
};

bool ValidUtf8(const std::string &text, size_t max_units, bool allow_empty,
               bool require_visible = true);
bool DecodeRequest(const std::vector<uint8_t> &frame, Request *request);
bool IsCommit(const std::vector<uint8_t> &frame);
std::vector<uint8_t> Header(Tag tag);
std::vector<uint8_t> EncodeResult(const WireResult &result);
std::vector<uint8_t> EncodeInventory(const std::vector<Descriptor> &queues);

} // namespace vynic::print_helper

#endif
