#include "session.h"

#include <exception>
#include <utility>

namespace vynic::print_helper {
namespace {

bool Failure(FrameIO &io, const char *stage, const char *detail,
             bool attempted = false, uint32_t code = 0,
             const printing::Submission &submission = {}) {
  return io.Write(EncodeResult(WireResult{
      static_cast<uint8_t>(attempted ? 2 : 0), attempted,
      submission.bytes_written, submission.job_id, code, stage, detail}));
}

} // namespace

bool RunSession(FrameIO &io, printing::SpoolerApi &api, GuardKeeper &guard,
                ToWide wide, ToUtf8 utf8) {
  bool attempted = false;
  try {
    std::vector<uint8_t> frame;
    Request request;
    if (!io.Read(&frame) || !DecodeRequest(frame, &request))
      return Failure(io, "validate", "Incomplete or invalid helper request");
    if (request.tag == Tag::inventory) {
      const auto inventory = api.ListQueues();
      if (inventory.error)
        return Failure(io, inventory.error->stage.c_str(),
                       inventory.error->message.c_str(), false,
                       inventory.error->windows_error);
      std::vector<Descriptor> queues;
      for (const auto &queue : inventory.queues)
        queues.push_back(
            {utf8(queue.name), utf8(queue.driver), utf8(queue.port)});
      auto encoded = EncodeInventory(queues);
      if (encoded.empty())
        return Failure(io, "enumerate", "Invalid inventory encoding");
      return io.Write(encoded);
    }
    if (!guard.Retain(request.guard))
      return Failure(io, "guard", "Parent physical printer guard is not held");
    if (!io.Write(Header(Tag::ready)))
      return false;
    if (!io.Read(&frame) || !IsCommit(frame))
      return Failure(io, "admission",
                     "Helper COMMIT was incomplete or invalid");
    const printing::Queue expected{wide(request.queue), wide(request.driver),
                                   wide(request.port)};
    const auto submission = printing::SubmitRaw(
        api, expected, request.payload, wide(request.document), &attempted);
    if (submission.error)
      return Failure(io, submission.error->stage.c_str(),
                     submission.error->message.c_str(),
                     submission.error->write_attempted,
                     submission.error->windows_error, submission);
    return io.Write(EncodeResult(WireResult{
        1, true, submission.bytes_written, submission.job_id, 0, "accepted",
        "RAW spooler accepted the complete payload; paper delivery is "
        "unconfirmed"}));
  } catch (const std::exception &) {
    return Failure(io, "nativeException", "Helper operation threw an exception",
                   attempted);
  } catch (...) {
    return Failure(io, "nativeException", "Helper operation threw an exception",
                   attempted);
  }
}

} // namespace vynic::print_helper
