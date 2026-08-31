import { useState } from "react";
import { ArrowRight, LockKey, ShieldCheck } from "@phosphor-icons/react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import vynicLogo from "../assets/vynic-logo.png";
import { useAuth } from "./auth";
import { errorMessage } from "./format";
import { Button } from "./components/Button";
import { Field, FormError, Input } from "./components/Form";

export function LoginPage() {
  const { login, status } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  if (status === "authenticated") return <Navigate to="/" replace />;

  const destination =
    typeof location.state === "object" &&
    location.state &&
    "from" in location.state &&
    typeof location.state.from === "string"
      ? location.state.from
      : "/";

  return (
    <main className="platform-login">
      <section className="platform-login__context" aria-label="Vynic platform">
        <a className="platform-brand platform-brand--login" href="/product">
          <img src={vynicLogo} alt="" />
          <span>Vynic</span>
        </a>
        <div className="platform-login__message">
          <p className="platform-eyebrow">Platform control plane</p>
          <h1>Operate Vynic with clarity.</h1>
          <p>
            Manage organizations, venues, product access, domains, and POS devices from one audited workspace.
          </p>
        </div>
        <div className="platform-login__trust">
          <ShieldCheck size={20} weight="duotone" />
          <span>Reserved for authorized Vynic administrators</span>
        </div>
      </section>

      <section className="platform-login__form-wrap">
        <form
          className="platform-login__form"
          onSubmit={async (event) => {
            event.preventDefault();
            setError("");
            setSubmitting(true);
            try {
              await login(email, password);
              navigate(destination, { replace: true });
            } catch (cause) {
              setError(errorMessage(cause));
            } finally {
              setSubmitting(false);
            }
          }}
        >
          <div className="platform-login__icon"><LockKey size={22} /></div>
          <div>
            <p className="platform-eyebrow">Secure access</p>
            <h2>Sign in to Platform Admin</h2>
            <p>Use your Vynic PlatformUser credentials.</p>
          </div>
          <Field label="Email">
            <Input
              type="email"
              name="email"
              autoComplete="username"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              autoFocus
            />
          </Field>
          <Field label="Password">
            <Input
              type="password"
              name="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
            />
          </Field>
          <FormError>{error}</FormError>
          <Button type="submit" tone="primary" disabled={submitting}>
            {submitting ? "Signing in…" : "Sign in"} <ArrowRight size={16} />
          </Button>
          <p className="platform-login__help">
            No account? A server operator must create the first administrator with the protected CLI command.
          </p>
        </form>
      </section>
    </main>
  );
}
