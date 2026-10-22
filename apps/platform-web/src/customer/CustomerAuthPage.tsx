import { AccessRequest } from "./AccessRequest";
import { ArrowRight, Check, Eye, EyeSlash } from "@phosphor-icons/react";
import vynicLogo from "../assets/vynic-logo.png";
import posScreen from "../assets/pos-live-floor.jpg";
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
  const [showPassword, setShowPassword] = useState(false);
  const signup = mode === "signup";
  const title = signup ? "ანგარიშის შექმნა" : "შესვლა";

  if (signup) return <AccessRequest />;

  if (hasCustomerSession())
    return <Navigate to={returnPath(location.state)} replace />;

  return (
    <PublicFrame title={title}>
      <div className={`auth-layout auth-layout--${mode}`}>
        <aside className="auth-story" aria-label="Vynic — რესტორნის მართვა">
          <div className="auth-brand">
            <img src={vynicLogo} alt="" />
            <span>Vynic</span>
            <span className="auth-brand-caption">თქვენი რესტორნის რიტმში</span>
          </div>
          <div className="auth-story-copy">
            <p className="auth-kicker">მეტი დრო სტუმრებისთვის</p>
            <h2>
              ყველაფერი,
              <br />
              ერთი სივრციდან.
            </h2>
            <p>თქვენი რესტორანი, ვებსაიტი და POS — ერთად, Vynic-ში.</p>
          </div>
          <div className="auth-computer" aria-hidden="true">
            <div className="auth-monitor">
              <img src={posScreen} alt="" width={800} height={632} />
            </div>
            <div className="auth-monitor-stand" />
            <div className="auth-monitor-base" />
            <div className="auth-computer-note" key={mode}>
              <span className="auth-note-icon">
                <Check size={15} weight="bold" />
              </span>
              {signup ? "თქვენი ახალი დასაწყისი" : "თქვენი სამუშაო სივრცე"}
            </div>
          </div>
          <div className="auth-story-footer">
            <span>რესტორნისთვის შექმნილი.</span>
            <span>თქვენზე მორგებული.</span>
          </div>
        </aside>
        <section
          className="customer-auth auth-form-panel"
          aria-labelledby="auth-title"
        >
          <nav className="auth-mode" aria-label="ანგარიშზე წვდომა">
            <Link
              to="/login"
              state={location.state}
              aria-current={!signup ? "page" : undefined}
            >
              შესვლა
            </Link>
            <Link
              to="/request-access"
              state={location.state}
              aria-current={signup ? "page" : undefined}
            >
              გამოსცადე Vynic
            </Link>
          </nav>
          <div className="auth-form-content" key={mode}>
            <h1 id="auth-title">{title}</h1>
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
                <div>
                  <label>
                    თქვენი სახელი
                    <input
                      name="displayName"
                      required
                      maxLength={100}
                      autoComplete="name"
                      placeholder="მაგალითად, ნინო"
                      aria-describedby="signup-name-hint"
                    />
                  </label>
                  <p id="signup-name-hint" className="customer-hint">
                    თქვენი პირადი სახელი — რესტორანს შემდეგ ეტაპზე დაამატებთ.
                  </p>
                </div>
              )}
              <label>
                ელფოსტა
                <input
                  name="email"
                  type="email"
                  required
                  maxLength={254}
                  autoComplete="email"
                  placeholder="name@example.com"
                />
              </label>
              <div className="auth-password-field">
                <label htmlFor="auth-password">პაროლი</label>
                <div className="auth-password-input">
                  <input
                    id="auth-password"
                    name="password"
                    type={showPassword ? "text" : "password"}
                    required
                    minLength={signup ? 8 : 1}
                    maxLength={128}
                    autoComplete={signup ? "new-password" : "current-password"}
                    placeholder={
                      signup ? "მინიმუმ 8 სიმბოლო" : "შეიყვანეთ თქვენი პაროლი"
                    }
                  />
                  <button
                    type="button"
                    className="auth-password-toggle"
                    aria-label={
                      showPassword ? "პაროლის დამალვა" : "პაროლის ჩვენება"
                    }
                    aria-pressed={showPassword}
                    onClick={() => setShowPassword((value) => !value)}
                  >
                    {showPassword ? <EyeSlash size={20} /> : <Eye size={20} />}
                  </button>
                </div>
              </div>
              {signup && (
                <p className="customer-hint">
                  მინიმუმ 8 სიმბოლო. საცდელ ეტაპზე ელფოსტის დადასტურება და
                  პაროლის ავტომატური აღდგენა ჯერ არ არის ხელმისაწვდომი.
                </p>
              )}
              <button className="auth-submit" disabled={busy} aria-busy={busy}>
                {busy ? "მუშავდება…" : signup ? "ანგარიშის შექმნა" : "შესვლა"}
                <ArrowRight size={18} aria-hidden="true" />
              </button>
            </form>
          </div>
        </section>
      </div>
    </PublicFrame>
  );
}
