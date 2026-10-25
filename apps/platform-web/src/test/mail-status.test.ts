import { describe, expect, it } from "vitest";
import { invitationMailStatus } from "../platform/mail-status";
describe("invitation mail status", () => {
  it("distinguishes Google acceptance from confirmed delivery", () => {
    expect(invitationMailStatus({ status: "accepted" })).toContain("Inbox delivery is not confirmed");
  });
  it.each(["disabled", "misconfigured", "failed", "unknown", "skipped"])("does not claim success for %s", (status) => {
    const text = invitationMailStatus({ status, diagnostic: "untrusted provider secret" });
    expect(text).not.toContain("untrusted provider secret");
    expect(text).not.toContain("Google accepted");
  });
  it("handles an older server without claiming email was sent", () => {
    expect(invitationMailStatus()).toContain("not confirmed");
  });
});
