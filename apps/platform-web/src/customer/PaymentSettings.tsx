import { useEffect, useState } from "react";
import { customerApi } from "./api";
export type PaymentStatus = {
  configured: boolean;
  entitled: boolean;
  revision: number | null;
};
export function PaymentSettings({ venueId }: { venueId: string }) {
  const [status, setStatus] = useState<PaymentStatus>();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const path = `venues/${venueId}/payments/bog`;
  const load = () =>
    customerApi<PaymentStatus>(path)
      .then(setStatus)
      .catch(() => setError("მონაცემები ვერ ჩაიტვირთა."));
  useEffect(() => {
    void load();
  }, [venueId]);
  if (status && !status.entitled) return null;
  return (
    <section>
      <h2>ონლაინ გადახდები</h2>
      <h3>Bank of Georgia</h3>
      {status ? (
        <>
          <p>
            სტატუსი:{" "}
            {status.configured ? "დაკავშირებულია" : "არ არის დაკავშირებული"}
          </p>
          <p>
            შენახული საიდუმლო არ გამოჩნდება. ცვლილებისას შეიყვანეთ ორივე ახალი
            მონაცემი.
          </p>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const form = e.currentTarget;
              const body = Object.fromEntries(new FormData(form));
              setBusy(true);
              setError("");
              setMessage("");
              try {
                setStatus(await customerApi<PaymentStatus>(path, body, "PUT"));
                form.reset();
                setMessage("შენახულია.");
              } catch {
                setError(
                  "შენახვა ვერ მოხერხდა. შეამოწმეთ მონაცემები და რესტორნის რეგისტრირებული დომენი.",
                );
              } finally {
                setBusy(false);
              }
            }}
          >
            <label>
              Client ID
              <input
                name="clientId"
                required
                maxLength={512}
                autoComplete="off"
                disabled={busy}
              />
            </label>
            <label>
              Client Secret
              <input
                name="clientSecret"
                type="password"
                required
                maxLength={4096}
                autoComplete="new-password"
                disabled={busy}
              />
            </label>
            <label>
              ვებსაიტის მისამართი
              <input
                name="returnOrigin"
                type="url"
                placeholder="https://restaurant.ge"
                required
                disabled={busy}
              />
            </label>
            <button disabled={busy}>შენახვა</button>
          </form>
          <button
            className="secondary"
            disabled={busy || !status.configured}
            onClick={async () => {
              setBusy(true);
              setError("");
              setMessage("");
              try {
                setStatus(
                  await customerApi<PaymentStatus>(`${path}/disable`, {}),
                );
                setMessage(
                  "გამორთულია. არსებული გადახდების დამუშავება გაგრძელდება.",
                );
              } catch {
                setError("გათიშვა ვერ მოხერხდა. სცადეთ ხელახლა.");
              } finally {
                setBusy(false);
              }
            }}
          >
            გათიშვა
          </button>
        </>
      ) : (
        !error && <p role="status">იტვირთება…</p>
      )}
      {error && (
        <p role="alert">
          {error}{" "}
          {!status && (
            <button
              onClick={() => {
                setError("");
                void load();
              }}
            >
              ხელახლა ცდა
            </button>
          )}
        </p>
      )}
      <p role="status">{message}</p>
    </section>
  );
}
