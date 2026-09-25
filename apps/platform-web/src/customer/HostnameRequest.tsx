import { useEffect, useState } from "react";
import { customerApi } from "./api";
import { websiteAddress, type Website } from "./useWebsite";
export type HostnameRequestRow = {
  id: string;
  hostname: string;
  status: string;
  reason?: string | null;
};
export function HostnameRequest({ website }: { website: Website }) {
  const settings = website.settings!;
  const [requests, setRequests] = useState<HostnameRequestRow[]>();
  const [slug, setSlug] = useState("");
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const path = `venues/${website.venueId}/website/hostname-requests`;
  useEffect(() => {
    let active = true;
    customerApi<HostnameRequestRow[]>(path)
      .then((r) => {
        if (active) setRequests(r);
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [path]);
  const pending = requests?.find((r) => r.status === "PENDING");
  return (
    <div>
      <p>თქვენი ვებსაიტის მისამართი</p>
      <strong>{websiteAddress(settings)}</strong>
      {settings.commercialStatus === "TRIAL" && (
        <p>საცდელი პერიოდის განმავლობაში მისამართის შეცვლა შეუძლებელია.</p>
      )}
      {pending ? (
        <p role="status">მოთხოვნა განიხილება · PENDING · {pending.hostname}</p>
      ) : (
        settings.hostnameChangeAllowed &&
        requests &&
        (open ? (
          <div>
            <label>
              სასურველი მისამართი
              <input
                value={slug}
                maxLength={48}
                onChange={(e) => setSlug(e.target.value.toLowerCase())}
              />
            </label>
            <p>მისამართი შეიცვლება მხოლოდ Vynic-ის გუნდის თანხმობის შემდეგ.</p>
            <button
              type="button"
              disabled={busy || !slug.trim()}
              onClick={async () => {
                setBusy(true);
                setError("");
                try {
                  const row = await customerApi<HostnameRequestRow>(path, {
                    slug,
                  });
                  setRequests([row, ...requests]);
                  setOpen(false);
                } catch (e) {
                  setError((e as Error).message);
                } finally {
                  setBusy(false);
                }
              }}
            >
              მოთხოვნის გაგზავნა
            </button>
          </div>
        ) : (
          <button type="button" onClick={() => setOpen(true)}>
            მისამართის შეცვლის მოთხოვნა
          </button>
        ))
      )}
      {error && <p role="alert">{error}</p>}
    </div>
  );
}
