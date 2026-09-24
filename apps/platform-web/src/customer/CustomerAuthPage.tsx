import { AccessRequest } from "./AccessRequest";
import { useState } from "react";
import { Link, Navigate, useLocation, useNavigate } from "react-router-dom";
import { customerApi, hasCustomerSession } from "./api";
import { PublicFrame } from "./PublicFrame";

/** Only dashboard paths are honoured as a return address after sign-in. */
function returnPath(state: unknown) {
  const from = (state as { from?: unknown } | null)?.from;
  return typeof from === "string" && /^\/dashboard(\/|$)/.test(from)
    ? from
    : "/dashboard";
}

/**
 * Approved owners sign in to their dashboard. Public signup is an access
 * request only; invitation acceptance and product assignment are separate.
 */
export function CustomerAuthPage({ mode }: { mode: "login" | "signup" }) {
  const navigate = useNavigate();
  const location = useLocation();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const signup = mode === "signup";
  const title = signup ? "ანგარიშის შექმნა" : "შესვლა";

  if (signup) return <AccessRequest />;

  if (hasCustomerSession())
    return <Navigate to={returnPath(location.state)} replace />;

  return (
    <PublicFrame title={title}>
      <section className="customer-auth">
        <p className="customer-eyebrow">
          {signup ? "დაიწყეთ Vynic-ით" : "რესტორნის მფლობელებისთვის"}
        </p>
        <h1>{title}</h1>
        <p className="customer-lead">
          {signup
            ? "ერთი ანგარიში რესტორნის, ვებსაიტისა და POS-ის სამართავად."
            : "შედით თქვენი რესტორნის მართვის პანელში."}
        </p>
        {error && (
          <p role="alert" className="customer-error">
            {error}
          </p>
        )}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const data = Object.fromEntries(new FormData(e.currentTarget));
            setBusy(true);
            setError("");
            customerApi(`auth/${mode}`, data)
              .then(() =>
                navigate(returnPath(location.state), { replace: true }),
              )
              .catch((e: Error) => {
                setError(e.message);
                setBusy(false);
              });
          }}
        >
          {signup && (
            <label>
              სახელი
              <input
                name="displayName"
                required
                maxLength={100}
                autoComplete="name"
              />
            </label>
          )}
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
            პაროლი
            <input
              name="password"
              type="password"
              required
              minLength={signup ? 15 : 1}
              maxLength={128}
              autoComplete={signup ? "new-password" : "current-password"}
            />
          </label>
          {signup && (
            <p className="customer-hint">
              მინიმუმ 15 სიმბოლო. საცდელ ეტაპზე ელფოსტის დადასტურება და
              პაროლის ავტომატური აღდგენა ჯერ არ არის ხელმისაწვდომი.
            </p>
          )}
          <button disabled={busy}>
            {busy ? "მუშავდება…" : signup ? "ანგარიშის შექმნა" : "შესვლა"}
          </button>
        </form>
        <p className="customer-switch">
          {signup ? "უკვე გაქვთ ანგარიში? " : "ჯერ არ გაქვთ ანგარიში? "}
          <Link to={signup ? "/login" : "/signup"} state={location.state}>
            {signup ? "შესვლა" : "გამოსცადე Vynic"}
          </Link>
        </p>
      </section>
    </PublicFrame>
  );
}
