export function invitationMailStatus(mail?: { status: string; diagnostic?: string }): string {
  switch (mail?.status) {
    case "accepted": return "Google accepted the invitation email. Inbox delivery is not confirmed.";
    case "disabled": return "Email is disabled. Copy and share the invitation link manually.";
    case "misconfigured": return "Email configuration needs attention. Copy and share the invitation link manually.";
    case "failed": return "Email was not accepted. Copy and share the invitation link manually.";
    case "unknown": return "Email submission is unconfirmed. No automatic retry was made. Share this link or regenerate explicitly.";
    case "skipped": return "Email was not sent because the invitation is no longer valid for sending. Review the invitation before sharing.";
    default: return "Email delivery is not confirmed. Copy and share the invitation link manually.";
  }
}
