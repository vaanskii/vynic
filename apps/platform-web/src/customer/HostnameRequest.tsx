import { websiteAddress, type Website } from "./useWebsite";
export type HostnameRequestRow = {
  id: string;
  hostname: string;
  currentHostname?: string | null;
  status: string;
  createdAt?: string;
  reviewedAt?: string | null;
  reason?: string | null;
  requestedBy?: string;
  reviewedBy?: string | null;
};

/** Website address is read-only. Changes are handled by Vynic support. */
export function HostnameRequest({ website }: { website: Website }) {
  const settings = website.settings!;
  return (
    <div className="portal-hostname">
      <p>თქვენი ვებსაიტის მისამართი</p>
      <strong className="portal-address">{websiteAddress(settings)}</strong>
      <p className="portal-hint">
        მისამართის შესაცვლელად დაუკავშირდით Vynic-ის მხარდაჭერას.
      </p>
      {settings.pendingHostnameRequest && (
        <div className="portal-inset" role="status">
          <strong>წინა მოთხოვნა განხილვაშია</strong>
          <span>
            მოთხოვნილი მისამართი: {settings.pendingHostnameRequest.hostname}
          </span>
          <small>განხილვამდე მოქმედებს მიმდინარე მისამართი.</small>
        </div>
      )}
    </div>
  );
}
