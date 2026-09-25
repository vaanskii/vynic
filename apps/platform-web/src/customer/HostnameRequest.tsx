import { useEffect, useState } from "react";
import { customerApi } from "./api";
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
type Check = "idle" | "checking" | "available" | "taken" | "invalid";
const checkLabels: Record<Exclude<Check, "idle">, string> = {
  checking: "მოწმდება…",
  available: "ამჟამად თავისუფალია",
  taken: "მისამართი დაკავებულია",
  invalid:
    "გამოიყენეთ ლათინური პატარა ასოები, ციფრები ან დეფისი. ზოგი სახელი დაცულია.",
};

/**
 * The owner's view of the server-assigned SaaS address.
 *
 * The address is never edited here. A paid owner may only ask for another
 * one; Vynic reviews it and nothing changes until then.
 */
export function HostnameRequest({ website }: { website: Website }) {
  const settings = website.settings!;
  const trial = settings.commercialStatus === "TRIAL";
  const allowed = !!settings.hostnameChangeAllowed;
  const [requests, setRequests] = useState<HostnameRequestRow[]>();
  const [slug, setSlug] = useState("");
  const [checked, setChecked] = useState<{ slug: string; check: Check }>();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const path = `venues/${website.venueId}/website/hostname-requests`;
  const watch = allowed || !!settings.pendingHostnameRequest;
  useEffect(() => {
    if (!watch) return;
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
  }, [path, watch]);
  // Advisory only: approval checks availability again on the server.
  useEffect(() => {
    if (!open || !slug) return;
    let active = true;
    const timer = setTimeout(() => {
      customerApi<{ valid: boolean; available: boolean }>(
        `venues/${website.venueId}/website/address/${encodeURIComponent(slug)}`,
      )
        .then((r) => {
          if (active)
            setChecked({
              slug,
              check: !r.valid ? "invalid" : r.available ? "available" : "taken",
            });
        })
        .catch(() => {
          if (active) setChecked({ slug, check: "idle" });
        });
    }, 300);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [open, slug, website.venueId]);
  const check: Check =
    !open || !slug
      ? "idle"
      : checked?.slug === slug
        ? checked.check
        : "checking";
  const pending = requests?.find((r) => r.status === "PENDING");
  const decided = requests?.find((r) => r.status !== "PENDING");
  const suffix = settings.baseDomain ? `.${settings.baseDomain}` : "";
  return (
    <div className="portal-hostname">
      <p>თქვენი ვებსაიტის მისამართი</p>
      <strong className="portal-address">{websiteAddress(settings)}</strong>
      {trial ? (
        <p className="portal-hint">
          მისამართი Vynic-მა მიანიჭა ავტომატურად. საცდელი პერიოდის განმავლობაში
          მისამართის შეცვლა შეუძლებელია.
        </p>
      ) : (
        !allowed &&
        !pending && <p className="portal-hint">მისამართს Vynic მართავს.</p>
      )}
      {pending ? (
        <div className="portal-inset" role="status">
          <strong>მისამართის შეცვლის მოთხოვნა გაგზავნილია</strong>
          <span>მოთხოვნილი მისამართი: {pending.hostname}</span>
          <span>სტატუსი: განხილვაშია</span>
          <small>
            დამტკიცებამდე მოქმედებს მიმდინარე მისამართი. ახალი მოთხოვნის
            გაგზავნა შესაძლებელი იქნება განხილვის შემდეგ.
          </small>
        </div>
      ) : (
        allowed &&
        requests && (
          <>
            {decided && (
              <p className="portal-hint">
                ბოლო მოთხოვნა ({decided.hostname}):{" "}
                {decided.status === "APPROVED" ? "დამტკიცდა" : "უარყოფილია"}
                {decided.status === "REJECTED" && decided.reason
                  ? ` — ${decided.reason}`
                  : ""}
              </p>
            )}
            {open ? (
              <form
                className="portal-inset"
                onSubmit={async (e) => {
                  e.preventDefault();
                  setBusy(true);
                  setError("");
                  try {
                    const row = await customerApi<HostnameRequestRow>(path, {
                      slug,
                    });
                    setRequests([row, ...requests]);
                    setOpen(false);
                    setSlug("");
                    if (!website.dirty) void website.load();
                  } catch (e) {
                    setError((e as Error).message);
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                <label>
                  სასურველი მისამართი
                  <input
                    value={slug}
                    maxLength={48}
                    autoComplete="off"
                    spellCheck={false}
                    onChange={(e) =>
                      setSlug(e.target.value.toLowerCase().replace(/\s+/g, ""))
                    }
                  />
                </label>
                {slug && (
                  <span>
                    {slug}
                    {suffix}
                  </span>
                )}
                {check !== "idle" && (
                  <small aria-live="polite">{checkLabels[check]}</small>
                )}
                <small>
                  მისამართი შეიცვლება მხოლოდ Vynic-ის გუნდის თანხმობის შემდეგ;
                  ხელმისაწვდომობა საბოლოოდ მოწმდება დამტკიცებისას.
                </small>
                <div>
                  <button
                    disabled={
                      busy || !slug || check === "invalid" || check === "taken"
                    }
                  >
                    {busy ? "იგზავნება…" : "მოთხოვნის გაგზავნა"}
                  </button>
                  <button
                    type="button"
                    className="secondary"
                    onClick={() => {
                      setOpen(false);
                      setSlug("");
                      setError("");
                    }}
                  >
                    გაუქმება
                  </button>
                </div>
              </form>
            ) : (
              <button type="button" onClick={() => setOpen(true)}>
                მისამართის შეცვლის მოთხოვნა
              </button>
            )}
          </>
        )
      )}
      {error && (
        <p role="alert" className="customer-error">
          {error}
        </p>
      )}
    </div>
  );
}
