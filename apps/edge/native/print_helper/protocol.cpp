#include "protocol.h"

#include <limits>
#include <utility>

namespace vynic::print_helper {
namespace {

void U16(std::vector<uint8_t> &out, uint16_t value) {
  out.push_back(static_cast<uint8_t>(value));
  out.push_back(static_cast<uint8_t>(value >> 8));
}
void U32(std::vector<uint8_t> &out, uint32_t value) {
  for (int n = 0; n < 4; ++n)
    out.push_back(static_cast<uint8_t>(value >> (n * 8)));
}
void Text(std::vector<uint8_t> &out, const std::string &text) {
  U32(out, static_cast<uint32_t>(text.size()));
  out.insert(out.end(), text.begin(), text.end());
}

class Reader {
public:
  explicit Reader(const std::vector<uint8_t> &bytes) : bytes_(bytes) {}
  bool Integer(size_t size, uint32_t *value) {
    if (size > bytes_.size() - offset_)
      return false;
    *value = 0;
    for (size_t n = 0; n < size; ++n)
      *value |= static_cast<uint32_t>(bytes_[offset_++]) << (n * 8);
    return true;
  }
  bool String(size_t limit, std::string *value) {
    uint32_t size = 0;
    if (!Integer(4, &size) || size > limit || size > bytes_.size() - offset_)
      return false;
    value->assign(reinterpret_cast<const char *>(bytes_.data() + offset_),
                  size);
    offset_ += size;
    return true;
  }
  bool Payload(std::vector<uint8_t> *value) {
    uint32_t size = 0;
    if (!Integer(4, &size) || size == 0 || size > kMaxPayloadBytes ||
        size > bytes_.size() - offset_)
      return false;
    value->assign(bytes_.begin() + offset_, bytes_.begin() + offset_ + size);
    offset_ += size;
    return true;
  }
  bool End() const { return offset_ == bytes_.size(); }

private:
  const std::vector<uint8_t> &bytes_;
  size_t offset_ = 0;
};

bool ReadHeader(Reader &reader, Tag *tag) {
  uint32_t magic = 0, version = 0, command = 0, reserved = 0;
  if (!reader.Integer(4, &magic) || !reader.Integer(2, &version) ||
      !reader.Integer(1, &command) || !reader.Integer(1, &reserved) ||
      magic != kMagic || version != kProtocolVersion || reserved != 0)
    return false;
  *tag = static_cast<Tag>(command);
  return true;
}

bool ValidGuard(const std::string &guard) {
  const std::string prefix(kGuardPrefix);
  if (guard.size() != prefix.size() + 64 ||
      guard.compare(0, prefix.size(), prefix) != 0)
    return false;
  for (size_t n = prefix.size(); n < guard.size(); ++n)
    if (!((guard[n] >= '0' && guard[n] <= '9') ||
          (guard[n] >= 'a' && guard[n] <= 'f')))
      return false;
  return true;
}

} // namespace

bool ValidUtf8(const std::string &text, size_t max_units, bool allow_empty,
               bool require_visible) {
  if (text.empty())
    return allow_empty;
  size_t units = 0;
  bool visible = false;
  for (size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<uint8_t>(text[offset++]);
    uint32_t code = 0, minimum = 0;
    size_t remaining = 0;
    if (first < 0x80)
      code = first;
    else if (first >= 0xc2 && first <= 0xdf) {
      code = first & 0x1f;
      remaining = 1;
      minimum = 0x80;
    } else if (first >= 0xe0 && first <= 0xef) {
      code = first & 0x0f;
      remaining = 2;
      minimum = 0x800;
    } else if (first >= 0xf0 && first <= 0xf4) {
      code = first & 0x07;
      remaining = 3;
      minimum = 0x10000;
    } else
      return false;
    if (remaining > text.size() - offset)
      return false;
    for (size_t n = 0; n < remaining; ++n) {
      const auto next = static_cast<uint8_t>(text[offset++]);
      if ((next & 0xc0) != 0x80)
        return false;
      code = (code << 6) | (next & 0x3f);
    }
    if (code < minimum || code > 0x10ffff ||
        (code >= 0xd800 && code <= 0xdfff) || code < 32 || code == 127)
      return false;
    units += code > 0xffff ? 2 : 1;
    if (units > max_units)
      return false;
    visible = visible || code > 32;
  }
  return !require_visible || visible;
}

bool DecodeRequest(const std::vector<uint8_t> &frame, Request *request) {
  if (!request || frame.size() > kMaxFrameBytes)
    return false;
  Reader reader(frame);
  Request parsed;
  if (!ReadHeader(reader, &parsed.tag))
    return false;
  if (parsed.tag == Tag::inventory) {
    if (!reader.End())
      return false;
  } else if (parsed.tag == Tag::submit) {
    if (!reader.String(255 * 4, &parsed.queue) ||
        !reader.String(1024 * 4, &parsed.driver) ||
        !reader.String(1024 * 4, &parsed.port) ||
        !reader.String(255 * 4, &parsed.document) ||
        !reader.String(128, &parsed.guard) ||
        !reader.Payload(&parsed.payload) || !reader.End() ||
        !ValidUtf8(parsed.queue, 255, false) ||
        !ValidUtf8(parsed.driver, 1024, false) ||
        !ValidUtf8(parsed.port, 1024, false) ||
        !ValidUtf8(parsed.document, 255, false) || !ValidGuard(parsed.guard))
      return false;
  } else {
    return false;
  }
  *request = std::move(parsed);
  return true;
}

bool IsCommit(const std::vector<uint8_t> &frame) {
  Reader reader(frame);
  Tag tag{};
  return ReadHeader(reader, &tag) && tag == Tag::commit && reader.End();
}

std::vector<uint8_t> Header(Tag tag) {
  std::vector<uint8_t> out;
  U32(out, kMagic);
  U16(out, kProtocolVersion);
  out.push_back(static_cast<uint8_t>(tag));
  out.push_back(0);
  return out;
}

std::vector<uint8_t> EncodeResult(const WireResult &result) {
  if (result.state > 2 || !ValidUtf8(result.stage, 64, false) ||
      !ValidUtf8(result.detail, 2048, true))
    return {};
  auto out = Header(Tag::result);
  out.push_back(result.state);
  out.push_back(result.attempted ? 1 : 0);
  U16(out, 0);
  U32(out, result.bytes_written);
  U32(out, result.job_id);
  U32(out, result.windows_error);
  Text(out, result.stage);
  Text(out, result.detail);
  return out;
}

std::vector<uint8_t> EncodeInventory(const std::vector<Descriptor> &queues) {
  if (queues.size() > 1024)
    return {};
  auto out = Header(Tag::inventory_result);
  U32(out, static_cast<uint32_t>(queues.size()));
  for (const auto &queue : queues) {
    if (!ValidUtf8(queue.name, 255, false) ||
        !ValidUtf8(queue.driver, 1024, true, false) ||
        !ValidUtf8(queue.port, 1024, true, false))
      return {};
    Text(out, queue.name);
    Text(out, queue.driver);
    Text(out, queue.port);
  }
  if (out.size() > kMaxFrameBytes)
    return {};
  return out;
}

} // namespace vynic::print_helper
