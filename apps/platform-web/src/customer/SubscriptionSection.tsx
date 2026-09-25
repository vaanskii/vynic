import { useEffect, useState } from "react";
import { customerApi } from "./api";
import { TrialRequest } from "./TrialRequest";
import { SectionHeader } from "./WebsiteSections";
import type { VenueStatus } from "./portal-types";
import { subscriptionLabels } from "./OperationsSections";
import {
  day,
  money,
  type BillingQuote,
  type SubscriptionDetail,
} from "../subscriptions/types";

type Plan = {
  id: string;
  name: string;
  priceMinor: number;
  currency: string;
  billingPeriod: string;
};
export function SubscriptionSection({
  venue,
  onChanged,
}: {
  venue: VenueStatus;
  onChanged?: () => Promise<void>;
}) {
  const [sub, setSub] = useState<SubscriptionDetail>();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [planId, setPlanId] = useState("");
  const [quote, setQuote] = useState<BillingQuote | null>(null);
  const [pending, setPending] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venue.venue.id}/subscription`;
  const refresh = async () =>
    setSub(await customerApi<SubscriptionDetail>(path));
  useEffect(() => {
    let alive = true;
    const load = () =>
      customerApi<SubscriptionDetail>(path)
        .then((value) => {
          if (alive) setSub(value);
        })
        .catch((e) => {
          if (alive) setError(e.message);
        });
    void load();
    void customerApi<Plan[]>("access-requests/plans")
      .then((value) => {
        if (alive) setPlans(value);
      })
      .catch((e) => {
        if (alive) setError(e.message);
      });
    const timer = setInterval(() => {
      void load();
    }, 60000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [path]);
  const run = async (work: () => Promise<void>) => {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await work();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const act = () =>
    run(async () => {
      await customerApi(`${path}/actions`, {
        action: pending,
        ...(pending === "SCHEDULE_CHANGE"
          ? {
              planId: quote?.planId,
              expectedPriceMinor: quote?.priceMinor,
              expectedCurrency: quote?.currency,
              expectedBillingPeriod: quote?.billingPeriod,
              expectedVersion: quote?.subscriptionVersion,
            }
          : {}),
      });
      setPending(null);
      setQuote(null);
      await refresh();
      await onChanged?.();
      setMessage("გამოწერა განახლებულია.");
    });
  const active = sub?.status === "ACTIVE";
  const canChange = [
    "NO_PLAN",
    "TRIAL",
    "ACTIVE",
    "PAST_DUE",
    "CANCELLED",
  ].includes(sub?.status ?? "");
  const agreement = sub?.assignment;
  const features =
    sub?.features ??
    (["ACTIVE", "TRIAL"].includes(sub?.status ?? "") ? venue.features : []);
  const productNames: Record<string, string> = {
    WEBSITE: "ვებსაიტი",
    POS: "გაყიდვების სისტემა (POS)",
    MANAGER_APP: "მენეჯერის აპლიკაცია",
  };
  const period = (value?: string | null) => (value === "YEAR" ? "წელი" : "თვე");
  return (
    <>
      <SectionHeader title="გამოწერა" />
      {error && (
        <p role="alert">
          {error}{" "}
          <button className="secondary" onClick={() => void run(refresh)}>
            ხელახლა ცდა
          </button>
        </p>
      )}
      {message && <p role="status">{message}</p>}
      {!sub ? (
        <p role="status">გამოწერა იტვირთება…</p>
      ) : (
        <>
          <div className="portal-grid subscription-grid">
            <section className="portal-card">
              <h3>
                {agreement?.plan.name ??
                  venue.plan?.name ??
                  "პაკეტი არჩეული არ არის"}
              </h3>
              <p className="portal-stat">
                {subscriptionLabels[sub.status] ?? sub.status}
              </p>
              {sub.status === "TRIAL" && (
                <p>
                  საცდელი პერიოდი აქტიურია {day(sub.trialEndsAt, "ka-GE")}-მდე
                </p>
              )}
              {sub.currentPeriodEndsAt && (
                <p>
                  {sub.cancelAtPeriodEnd
                    ? "გაუქმდება"
                    : active
                      ? "განახლების თარიღი"
                      : "პერიოდის ბოლო"}
                  : {day(sub.currentPeriodEndsAt, "ka-GE")}
                </p>
              )}
              {agreement && (
                <p>
                  განახლების ფასი:{" "}
                  {money(agreement.agreedPriceMinor, agreement.agreedCurrency)}{" "}
                  / {period(agreement.agreedBillingPeriod)}
                </p>
              )}
              {sub.status === "SUSPENDED" && (
                <p>
                  პროდუქტებზე წვდომა შეჩერებულია. აღსადგენად დაუკავშირდით
                  Vynic-ს.
                </p>
              )}
              {sub.status === "PAST_DUE" && (
                <p>
                  ახალი პერიოდის გასააქტიურებლად საჭიროა გადახდის დადასტურება.
                </p>
              )}
              {sub.pendingPlan && (
                <div className="subscription-next">
                  <h4>შემდეგი პაკეტი: {sub.pendingPlan.name}</h4>
                  <p>
                    დაიწყება {day(sub.pendingChangeAt, "ka-GE")} ·{" "}
                    {money(sub.pendingPriceMinor, sub.pendingCurrency)} /{" "}
                    {period(sub.pendingBillingPeriod)}
                  </p>
                  <p>მიმდინარე შესაძლებლობები პერიოდის ბოლომდე შენარჩუნდება.</p>
                  <button
                    className="secondary"
                    disabled={busy}
                    onClick={() => setPending("CANCEL_CHANGE")}
                  >
                    ცვლილების გაუქმება
                  </button>
                </div>
              )}
              {active && sub.billingManaged && (
                <button
                  className="secondary"
                  disabled={busy}
                  onClick={() =>
                    setPending(
                      sub.cancelAtPeriodEnd ? "UNDO_CANCEL" : "SCHEDULE_CANCEL",
                    )
                  }
                >
                  {sub.cancelAtPeriodEnd
                    ? "გამოწერის შენარჩუნება"
                    : "გამოწერის გაუქმება"}
                </button>
              )}
              <p>
                <a href="/ka#contact">დაუკავშირდით Vynic-ს</a>
              </p>
            </section>
            <section className="portal-card">
              <h3>ჩართული პროდუქტები</h3>
              {features.some((key) => productNames[key]) ? (
                <ul className="portal-features">
                  {features
                    .filter((key) => productNames[key])
                    .map((key) => (
                      <li key={key}>{productNames[key]}</li>
                    ))}
                </ul>
              ) : (
                <p>აქტიური პროდუქტები არ გაქვთ.</p>
              )}
            </section>
          </div>
          {canChange && (
            <section className="portal-card">
              <h3>
                {sub.status === "TRIAL"
                  ? "ფასიან პაკეტზე გადასვლა"
                  : "პაკეტის შეცვლა"}
              </h3>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  void run(async () => {
                    const result = await customerApi<BillingQuote>(
                      `${path}/quote`,
                      { planId },
                    );
                    setQuote(result);
                  });
                }}
              >
                <fieldset disabled={busy}>
                  <label>
                    პაკეტი
                    <select
                      required
                      value={planId}
                      onChange={(e) => {
                        setPlanId(e.target.value);
                        setQuote(null);
                      }}
                    >
                      <option value="">აირჩიეთ პაკეტი</option>
                      {sub.status === "PAST_DUE" &&
                        agreement &&
                        !plans.some((p) => p.id === agreement.planId) && (
                          <option value={agreement.planId}>
                            {agreement.plan.name} ·{" "}
                            {money(
                              agreement.agreedPriceMinor,
                              agreement.agreedCurrency,
                            )}
                          </option>
                        )}
                      {plans
                        .filter(
                          (p) =>
                            p.id !== agreement?.planId ||
                            sub.status === "PAST_DUE" ||
                            sub.status === "TRIAL" ||
                            sub.status === "CANCELLED",
                        )
                        .map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.name} · {money(p.priceMinor, p.currency)} /{" "}
                            {period(p.billingPeriod)}
                          </option>
                        ))}
                    </select>
                  </label>
                  <button>{busy ? "ითვლება…" : "პირობების ნახვა"}</button>
                </fieldset>
              </form>
              {quote && (
                <div className="subscription-next" role="status">
                  <h4>{quote.planName}</h4>
                  {quote.kind === "SCHEDULE_CHANGE" ? (
                    <>
                      <p>
                        ახალი პაკეტი ამოქმედდება{" "}
                        {day(quote.effectiveAt, "ka-GE")}. მანამდე მიმდინარე
                        შესაძლებლობები შენარჩუნდება.
                      </p>
                      <p>
                        შემდეგი ფასი: {money(quote.priceMinor, quote.currency)}{" "}
                        / {period(quote.billingPeriod)}
                      </p>
                      <button
                        disabled={busy}
                        onClick={() => setPending("SCHEDULE_CHANGE")}
                      >
                        ცვლილების დაგეგმვა
                      </button>
                    </>
                  ) : (
                    <>
                      <p>
                        გადასახდელი: {money(quote.amountMinor, quote.currency)}
                      </p>
                      {quote.kind === "UPGRADE" && (
                        <p>
                          განახლების თარიღი უცვლელია:{" "}
                          {day(sub.currentPeriodEndsAt, "ka-GE")}
                        </p>
                      )}
                      <p>
                        გადახდის დასასრულებლად დაუკავშირდით Vynic-ს. წვდომა
                        შეიცვლება გადახდის დადასტურების შემდეგ.
                      </p>
                    </>
                  )}
                </div>
              )}
            </section>
          )}
          {pending && (
            <section className="portal-card" aria-label="ცვლილების დადასტურება">
              <h3>დაადასტურეთ ცვლილება</h3>
              <p>
                {pending === "SCHEDULE_CANCEL"
                  ? `გამოწერა გაუქმდება ${day(sub.currentPeriodEndsAt, "ka-GE")}. მანამდე წვდომა შენარჩუნდება.`
                  : pending === "SCHEDULE_CHANGE"
                    ? `${quote?.planName} ამოქმედდება ${day(quote?.effectiveAt, "ka-GE")}.`
                    : "შენარჩუნდება მიმდინარე პაკეტის პირობები."}
              </p>
              <div className="customer-row">
                <button disabled={busy} onClick={() => void act()}>
                  {busy ? "ინახება…" : "დადასტურება"}
                </button>
                <button
                  className="secondary"
                  disabled={busy}
                  onClick={() => setPending(null)}
                >
                  უკან
                </button>
              </div>
            </section>
          )}
          {sub.status === "NO_PLAN" && (
            <TrialRequest key={venue.venue.id} venueId={venue.venue.id} />
          )}
        </>
      )}
    </>
  );
}
