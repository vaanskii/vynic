import { useCallback, useEffect, useState } from "react";
import { customerApi } from "./api";
import { platformOnboardingApi } from "../platform/api";
type DownloadGrant = {
  id: string;
  expiresAt: string;
  revokedAt: string | null;
};
type DownloadResponse = {
  available: boolean;
  grants?: DownloadGrant[];
  grant?: DownloadGrant;
  downloadUrl?: string;
};

export function ProtectedInstallerDownloads({
  venueId,
  admin = false,
  readonly = false,
}: {
  venueId?: string;
  admin?: boolean;
  readonly?: boolean;
}) {
  const [data, setData] = useState<DownloadResponse>();
  const [link, setLink] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const call = useCallback(
    (suffix = "", body?: unknown): Promise<DownloadResponse> =>
      admin
        ? platformOnboardingApi("downloads" + suffix, body, "POST")
        : customerApi<DownloadResponse>(
            `venues/${venueId}/downloads${suffix}`,
            body,
          ),
    [admin, venueId],
  );
  useEffect(() => {
    let active = true;
    call()
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [call]);
  async function run(work: () => Promise<void>) {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await work();
      setData(await call());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section
      aria-label={admin ? "Protected Windows installer" : "Windows ინსტალერი"}
    >
      {admin ? (
        <h2>Protected Windows installer</h2>
      ) : (
        <h4>Windows ინსტალერი</h4>
      )}
      <p>
        {admin
          ? "Issue a link valid for 15 minutes. It includes Setup, POS and Edge. Anyone holding the link can download until expiry or revocation. Share it manually; email delivery is not configured."
          : "შექმენით 15 წუთით მოქმედი ბმული. პაკეტში შედის ინსტალერი, POS და Edge. ბმულის მიმღებს ჩამოტვირთვა შეუძლია ვადის გასვლამდე ან გაუქმებამდე."}
      </p>
      {error && <p role="alert">{error}</p>}
      {message && <p role="status">{message}</p>}
      {!data && !error && (
        <p role="status">{admin ? "Loading…" : "იტვირთება…"}</p>
      )}
      {data && !data.available && (
        <p role="status">
          {admin
            ? "Protected storage requires configuration before downloads can be issued."
            : "დაცული ჩამოტვირთვა მზადდება. მიმართეთ Vynic-ის ადმინისტრატორს."}
        </p>
      )}
      {!readonly && (
        <button
          disabled={busy || !data?.available}
          onClick={() =>
            void run(async () => {
              const result = await call("", {});
              if (!result.downloadUrl || !result.grant)
                throw new Error(
                  "Download link could not be created. Try again.",
                );
              setLink(result.downloadUrl);
              setExpiresAt(result.grant.expiresAt);
            })
          }
        >
          {admin ? "Create download link" : "ჩამოტვირთვის ბმულის შექმნა"}
        </button>
      )}
      {link && (
        <div className="portal-inset">
          <label>
            {admin ? "Download link" : "ჩამოტვირთვის ბმული"}
            <input
              name="installerDownloadLink"
              autoComplete="off"
              spellCheck={false}
              readOnly
              value={link}
              onFocus={(e) => e.currentTarget.select()}
            />
          </label>
          <p>
            {admin ? "Expires" : "ვადა"}: {new Date(expiresAt).toLocaleString()}
          </p>
          <a href={link} referrerPolicy="no-referrer">
            {admin ? "Open download" : "ჩამოტვირთვის გახსნა"}
          </a>
          <button
            className="secondary"
            disabled={busy}
            onClick={() =>
              void run(async () => {
                await navigator.clipboard.writeText(link);
                setMessage(
                  admin
                    ? "Download link copied."
                    : "ჩამოტვირთვის ბმული დაკოპირებულია.",
                );
              })
            }
          >
            {admin ? "Copy link" : "ბმულის კოპირება"}
          </button>
        </div>
      )}
      {data?.grants
        ?.filter((g) => !g.revokedAt && new Date(g.expiresAt) > new Date())
        .map((g) => (
          <div key={g.id}>
            <p>
              {admin ? "Active until" : "აქტიურია"}{" "}
              {new Date(g.expiresAt).toLocaleString()}
            </p>
            {!readonly && (
              <button
                className="secondary"
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await call(`/${g.id}/revoke`, {});
                    setLink("");
                  })
                }
              >
                {admin ? "Revoke link" : "ბმულის გაუქმება"}
              </button>
            )}
          </div>
        ))}
    </section>
  );
}
