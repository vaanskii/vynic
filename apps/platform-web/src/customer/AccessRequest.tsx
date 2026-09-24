import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { customerApi } from "./api";
import { PublicFrame } from "./PublicFrame";
type Plan = { id: string; name: string };
export function AccessRequest() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    customerApi<Plan[]>("access-requests/plans")
      .then(setPlans)
      .catch(() =>
        setError(
          "პაკეტების სია ვერ ჩაიტვირთა. განაცხადის გაგზავნა მაინც შეგიძლიათ.",
        ),
      );
  }, []);
  return (
    <PublicFrame title="გამოსცადე Vynic">
      <section className="customer-auth auth-form-panel">
        <h1>გამოსცადე Vynic</h1>
        {sent ? (
          <div role="status">
            <h2>განაცხადი მიღებულია</h2>
            <p>
              ჩვენი გუნდი დაგიკავშირდებათ. დამტკიცების შემდეგ მიიღებთ მოწვევას
              თქვენს მართვის პანელში.
            </p>
            <Link to="/login">შესვლა</Link>
          </div>
        ) : (
          <>
            <p className="customer-lead">
              მოგვიყევით თქვენი ბიზნესის შესახებ. ერთად შევარჩევთ შესაფერის
              პაკეტს და საცდელ პერიოდს.
            </p>
            <form
              onSubmit={async (e) => {
                e.preventDefault();
                const body = Object.fromEntries(new FormData(e.currentTarget));
                setBusy(true);
                setError("");
                try {
                  await customerApi("access-requests", body);
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
                  თქვენი სახელი
                  <input
                    name="applicantName"
                    required
                    maxLength={100}
                    autoComplete="name"
                  />
                </label>
                <label>
                  რესტორნის / ბიზნესის სახელი
                  <input
                    name="businessName"
                    required
                    maxLength={100}
                    autoComplete="organization"
                  />
                </label>
                <label>
                  ელფოსტა
                  <input
                    name="email"
                    type="email"
                    required
                    maxLength={254}
                    autoComplete="email"
                  />
                </label>
                <label>
                  ტელეფონი
                  <input
                    name="phone"
                    type="tel"
                    required
                    maxLength={40}
                    autoComplete="tel"
                  />
                </label>
                <label>
                  სასურველი პაკეტი
                  <select name="requestedPlanId">
                    <option value="">შერჩევაში დახმარება მჭირდება</option>
                    {plans.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  დამატებითი ინფორმაცია <small>არასავალდებულო</small>
                  <textarea name="note" maxLength={1000} />
                </label>
                <button className="auth-submit" aria-busy={busy}>
                  {busy ? "იგზავნება…" : "განაცხადის გაგზავნა"}
                </button>
              </fieldset>
              {error && (
                <p role="alert" className="customer-error">
                  {error}
                </p>
              )}
            </form>
            <p>
              უკვე გაქვთ ანგარიში? <Link to="/login">შესვლა</Link>
            </p>
          </>
        )}
      </section>
    </PublicFrame>
  );
}
