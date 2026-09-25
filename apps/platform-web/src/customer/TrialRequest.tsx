import { useEffect, useState } from "react";
import { customerApi } from "./api";
export function TrialRequest({ venueId }: { venueId: string }) {
  const [plans, setPlans] = useState<
    {
      id: string;
      name: string;
      description: string | null;
      priceMinor: number;
      currency: string;
      billingPeriod: string;
    }[]
  >([]);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    Promise.all([
      customerApi<typeof plans>("access-requests/plans"),
      customerApi<{ status: string } | null>(
        `venues/${venueId}/trial-requests`,
      ),
    ])
      .then(([p, pending]) => {
        setPlans(p);
        setSent(pending?.status === "PENDING");
        setLoaded(true);
      })
      .catch((e) => setError(e.message));
  }, [venueId]);
  return (
    <section className="portal-card">
      <h3>მოითხოვეთ საცდელი პერიოდი</h3>
      <p>Vynic-ის გუნდი განიხილავს მოთხოვნას და დაგიკავშირდებათ.</p>
      {sent ? (
        <p role="status">მოთხოვნა გაგზავნილია. დაელოდეთ ჩვენი გუნდის პასუხს.</p>
      ) : !loaded ? (
        <p role="status">იტვირთება…</p>
      ) : (
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            const body = Object.fromEntries(new FormData(e.currentTarget));
            setBusy(true);
            setError("");
            try {
              await customerApi(`venues/${venueId}/trial-requests`, body);
              setSent(true);
            } catch (e) {
              setError((e as Error).message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <fieldset disabled={busy}>
            <label>
              პაკეტი
              <select name="requestedPlanId">
                <option value="">შერჩევაში დახმარება მჭირდება</option>
                {plans.map((p) => (
                  <option value={p.id} key={p.id}>
                    {p.name} · {(p.priceMinor / 100).toFixed(2)} {p.currency}
                  </option>
                ))}
              </select>
            </label>
            <label>
              შენიშვნა
              <textarea name="note" maxLength={1000} />
            </label>
            <button>{busy ? "იგზავნება…" : "მოთხოვნის გაგზავნა"}</button>
          </fieldset>
        </form>
      )}
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
